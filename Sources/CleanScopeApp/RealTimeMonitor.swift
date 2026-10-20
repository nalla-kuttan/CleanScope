import AppKit
import CleanScopeCore
import CoreServices

/// Opt-in real-time protection while CleanScope runs: watches Downloads, launch item folders
/// and Chromium extension folders with FSEvents, scans newly launched app versions, and checks
/// the top level of drives as they mount. It reports; it never blocks or removes on its own.
@MainActor
final class RealTimeMonitor {
  private var stream: FSEventStreamRef?
  private var coalescer = EventCoalescer(window: 10)
  private var launchCache = LaunchScanCache()
  private var observers: [NSObjectProtocol] = []
  private let onThreats: @MainActor ([Threat]) -> Void
  private let rules: () -> MalwareRuleSet
  private let trustedTeamIDs: () -> Set<String>

  init(
    rules: @escaping () -> MalwareRuleSet,
    trustedTeamIDs: @escaping () -> Set<String>,
    onThreats: @escaping @MainActor ([Threat]) -> Void
  ) {
    self.rules = rules
    self.trustedTeamIDs = trustedTeamIDs
    self.onThreats = onThreats
  }

  var isRunning: Bool { stream != nil }

  func setEnabled(_ enabled: Bool) {
    enabled ? start() : stop()
  }

  private func start() {
    guard stream == nil else { return }
    let paths = RealTimeWatchList.paths().filter { FileManager.default.fileExists(atPath: $0) }
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
      guard let info else { return }
      let monitor = Unmanaged<RealTimeMonitor>.fromOpaque(info).takeUnretainedValue()
      let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
      Task { @MainActor in monitor.handle(paths: Array(paths.prefix(count))) }
    }
    let flags = UInt32(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        | kFSEventStreamCreateFlagNoDefer)
    guard
      let created = FSEventStreamCreate(
        nil, callback, &context, paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0, flags)
    else { return }
    FSEventStreamSetDispatchQueue(created, DispatchQueue.global(qos: .utility))
    FSEventStreamStart(created)
    stream = created

    let center = NSWorkspace.shared.notificationCenter
    observers.append(
      center.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
      ) { [weak self] note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        Task { @MainActor in self?.appLaunched(app?.bundleURL) }
      })
    observers.append(
      center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) {
        [weak self] note in
        let volume = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        Task { @MainActor in self?.volumeMounted(volume) }
      })
  }

  private func stop() {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    stream = nil
    observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
  }

  private func handle(paths: [String]) {
    let home = NSHomeDirectory()
    var files: [String] = []
    var launchItemsChanged = false
    for path in paths where coalescer.shouldProcess(path: path) {
      if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") {
        launchItemsChanged = true
      } else if path.hasPrefix("\(home)/Library/Application Support/") {
        if path.contains("/Extensions/") { files.append(path) }
      } else if !Self.isPartialDownload(path) {
        files.append(path)
      }
    }
    var targets: [MalwareTarget] = []
    let existing = files.filter { FileManager.default.fileExists(atPath: $0) }
    if !existing.isEmpty { targets.append(.paths(existing)) }
    if launchItemsChanged { targets.append(.launchItems) }
    if existing.contains(where: { $0.contains("/Extensions/") }) {
      targets.append(.browserExtensions)
    }
    scan(targets)
  }

  private static func isPartialDownload(_ path: String) -> Bool {
    ["download", "crdownload", "part", "partial"].contains(
      URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  private func appLaunched(_ bundle: URL?) {
    guard let bundle, !bundle.path.hasPrefix("/System/") else { return }
    let modified = (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]))?
      .contentModificationDate
    guard launchCache.shouldScan(path: bundle.path, modified: modified) else { return }
    scan([.paths([bundle.path])])
  }

  private func volumeMounted(_ volume: URL?) {
    guard let volume else { return }
    let topLevel =
      ((try? FileManager.default.contentsOfDirectory(
        at: volume, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true }
      .map(\.path)
    if !topLevel.isEmpty { scan([.paths(topLevel)]) }
  }

  private func scan(_ targets: [MalwareTarget]) {
    guard !targets.isEmpty else { return }
    let rules = rules()
    let trusted = trustedTeamIDs()
    Task {
      let scanner = MalwareScanner(
        rules: rules, yara: ExternalYara(ruleSet: rules), trustedTeamIDs: trusted)
      let report = await scanner.scan(targets: targets)
      if !report.threats.isEmpty { onThreats(report.threats) }
    }
  }
}
