import AppKit
import CleanScopeCore
import Foundation
import ServiceManagement
import SwiftUI

/// A cleanup was confirmed while another was still running.
struct CleanupBusyError: LocalizedError {
  var errorDescription: String? {
    "Nothing was removed. Wait for the current cleanup to finish, then review again."
  }
}

@MainActor
final class AppModel: ObservableObject {
  enum Destination: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case storageMap
    case readyToDelete
    case safeCleanup
    case largeFiles
    case hiddenFolders
    case developerFiles
    case appSupport
    case downloads
    case trash
    case leftovers
    case maintenance
    case loginItems
    case backgroundItems
    case memory
    case protection
    case privacy
    case lastCleanup

    var id: String { rawValue }

    static let sections: [(title: String, destinations: [Destination])] = [
      ("Overview", [.dashboard, .storageMap, .readyToDelete, .safeCleanup]),
      (
        "Browse",
        [.largeFiles, .hiddenFolders, .developerFiles, .appSupport, .downloads, .trash, .leftovers]
      ),
      ("Performance", [.maintenance, .loginItems, .backgroundItems, .memory]),
      ("Protection", [.protection, .privacy]),
      ("Activity", [.lastCleanup]),
    ]

    /// The sidebar section this destination appears in.
    var section: String {
      Self.sections.first { $0.destinations.contains(self) }?.title ?? ""
    }

    var title: String {
      switch self {
      case .dashboard: return "Dashboard"
      case .storageMap: return "Storage Map"
      case .readyToDelete: return "Ready to Delete"
      case .safeCleanup: return "Safe Cleanup"
      case .largeFiles: return "Large Files"
      case .hiddenFolders: return "Hidden Folders"
      case .developerFiles: return "Developer Files"
      case .appSupport: return "App Support"
      case .downloads: return "Downloads"
      case .trash: return "Trash"
      case .leftovers: return "Leftovers"
      case .maintenance: return "Maintenance"
      case .loginItems: return "Login Items"
      case .backgroundItems: return "Background Items"
      case .memory: return "Memory"
      case .protection: return "Protection"
      case .privacy: return "Privacy"
      case .lastCleanup: return "Last Cleanup"
      }
    }

    var systemImage: String {
      switch self {
      case .dashboard: return "square.grid.2x2"
      case .storageMap: return "square.grid.3x3.square"
      case .readyToDelete: return "externaldrive.badge.checkmark"
      case .safeCleanup: return "checkmark.shield"
      case .largeFiles: return "externaldrive"
      case .hiddenFolders: return "eye.slash"
      case .developerFiles: return "hammer"
      case .appSupport: return "shippingbox"
      case .downloads: return "arrow.down.circle"
      case .trash: return "trash"
      case .leftovers: return "shippingbox.and.arrow.backward"
      case .maintenance: return "wrench.and.screwdriver"
      case .loginItems: return "person.badge.key"
      case .backgroundItems: return "gearshape.2"
      case .memory: return "memorychip"
      case .protection: return "shield.lefthalf.filled"
      case .privacy: return "hand.raised"
      case .lastCleanup: return "clock.arrow.circlepath"
      }
    }

    /// The 3D module icon for this destination; nil for destinations without one.
    var icon: ModuleIconKey? {
      switch self {
      case .dashboard: return .scan
      case .readyToDelete, .safeCleanup: return .cleanup
      case .storageMap: return .map
      case .largeFiles: return .large
      case .developerFiles: return .dev
      case .downloads: return .downloads
      case .leftovers: return .leftovers
      case .maintenance: return .maintenance
      case .memory: return .memory
      case .loginItems, .backgroundItems: return .login
      case .protection: return .protection
      case .privacy: return .privacy
      case .hiddenFolders, .appSupport, .trash, .lastCleanup: return nil
      }
    }

    var subtitle: String? {
      switch self {
      case .readyToDelete: return "High-confidence cache files that apps can recreate."
      case .safeCleanup: return "Generated files and caches CleanScope considers safe to remove."
      case .largeFiles: return "Files above your large-file threshold. Review each one yourself."
      case .hiddenFolders: return "Folders macOS hides by default, often left behind by tools."
      case .developerFiles: return "Build output and package caches from developer tools."
      case .appSupport: return "Data apps keep in Application Support. Remove only for apps you no longer use."
      case .downloads: return "Files in your Downloads folder."
      case .trash: return "Items already in the Trash."
      case .leftovers: return "Files left behind by apps you moved to the Trash."
      case .dashboard, .storageMap, .maintenance, .loginItems, .backgroundItems, .memory,
        .protection, .privacy, .lastCleanup:
        return nil
      }
    }

    var emptyTitle: String {
      switch self {
      case .readyToDelete: return "No cache files are ready"
      case .leftovers: return "No leftovers found"
      default: return "Nothing in \(title) yet"
      }
    }

    /// Shown when the last scan found nothing for this result list.
    var emptyMessage: String {
      switch self {
      case .leftovers:
        return
          "When an app is in the Trash and no other copy is installed, its leftover files appear here after a scan."
      default:
        return
          "The last scan found nothing here. Turn on more scan sources in Settings to look further."
      }
    }

    var isResultList: Bool {
      switch self {
      case .dashboard, .storageMap, .maintenance, .loginItems, .backgroundItems, .memory,
        .protection, .privacy, .lastCleanup:
        return false
      case .readyToDelete, .safeCleanup, .largeFiles, .hiddenFolders, .developerFiles,
        .appSupport, .downloads, .trash, .leftovers:
        return true
      }
    }

    /// `nil` for destinations that are not result lists.
    func includes(_ result: ScanResult, largeFileThreshold: Int64) -> Bool? {
      switch self {
      case .dashboard, .storageMap, .maintenance, .loginItems, .backgroundItems, .memory,
        .protection, .privacy, .lastCleanup:
        return nil
      case .readyToDelete: return ResultPresentation.isReadyToDeleteCache(result)
      case .safeCleanup: return result.category == .safeToDelete
      case .largeFiles: return result.sizeBytes >= largeFileThreshold
      case .hiddenFolders: return result.isHidden
      case .developerFiles: return result.ownerTool != nil
      case .appSupport:
        return result.normalizedPath.localizedCaseInsensitiveContains("/Library/Application Support/")
      case .downloads: return result.normalizedPath.localizedCaseInsensitiveContains("/Downloads/")
      case .trash: return result.normalizedPath.localizedCaseInsensitiveContains("/.Trash/")
      case .leftovers: return result.ruleId == LeftoverFinder.ruleID
      }
    }

    /// Matches a destination by raw value or title, for `--open-destination`.
    init?(argument: String) {
      guard
        let match = Self.allCases.first(where: {
          $0.rawValue.caseInsensitiveCompare(argument) == .orderedSame
            || $0.title.caseInsensitiveCompare(argument) == .orderedSame
        })
      else { return nil }
      self = match
    }
  }

  struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
  }

  struct ExclusionUndo: Identifiable {
    let id = UUID()
    var rule: ExclusionRule
    var name: String
    var previous: [ScanResult]
  }

  struct Disk: Equatable {
    var totalBytes: Int64
    var availableBytes: Int64
    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }
  }

  @Published var destination: Destination? = .dashboard
  @Published var settings: CleanScopeCore.Settings {
    didSet {
      do { try settingsStore.save(settings) } catch {
        report("Settings couldn’t be saved", error)
      }
      if settings.largeFileThresholdBytes != oldValue.largeFileThresholdBytes { recomputeDerived() }
      settingsDidChange(from: oldValue)
    }
  }
  @Published var session: ScanSession?
  @Published private(set) var streamedResults: [ScanResult] = [] {
    didSet { recomputeDerived() }
  }
  @Published var selection: Set<String> = []
  @Published var cleanupSession: CleanupSession?
  @Published var isScanning = false
  /// True for the duration of `cleanup(_:)`; the harvest basket stays disabled meanwhile, so a
  /// second review can't start a cleanup that collides with this one.
  @Published private(set) var isCleaningUp = false
  /// Help text on every cleanup entry point while `isCleaningUp`.
  static let cleanupRunningNote = "A cleanup is already running"
  /// Fraction of top-level scan items finished: 0 at scan start, 1 once a scan completes. A
  /// cancelled scan leaves it where it stopped.
  @Published private(set) var scanProgress: Double = 0
  /// Ids of results the app has moved to the Trash or deleted since the current scan began. The
  /// Storage Map leaves their tiles out, as the scan's tree itself is not rewritten.
  @Published private(set) var trashedResultIDs: Set<String> = [] {
    didSet { refreshTerrariumLayers() }
  }
  /// Category of the last result in the most recently flushed batch; nil until one arrives.
  @Published private(set) var latestStreamedCategory: SafetyCategory?
  @Published var permissionSummary: PermissionSummary?
  @Published var disk: Disk? {
    didSet { if disk != oldValue { refreshTerrariumLayers() } }
  }
  @Published var exclusions: [ExclusionRule] = []
  @Published var alert: AppAlert?
  @Published var exclusionUndo: ExclusionUndo?
  @Published var openAtLoginError: String?
  @Published var purgeableBytes: Int64 = 0
  @Published var localSnapshots: [Date] = []
  #if DEBUG
    /// Lets `DebugSnapshot` open an item's detail sheet.
    @Published var debugDetail: ScanResult?
    /// Result ids `DebugSnapshot` asks the Storage Map to collapse, as if they were just trashed.
    @Published var debugCollapseRequest: Set<String>?
  #endif

  /// Derived once per results change instead of on every view render.
  @Published private(set) var summary = ScanSummary()
  @Published private(set) var counts: [Destination: Int] = [:]
  @Published private(set) var safeCount = 0
  @Published private(set) var reviewCount = 0
  /// Soil layers for the terrarium: the scan's categories without items already moved to the
  /// Trash, over the disk's used space.
  @Published private(set) var terrariumLayers: [TerrariumLayer] = []
  /// The terrarium as it stood just before the current `cleanupSession`; Last Cleanup composts
  /// from it. Nil when that cleanup removed nothing.
  @Published private(set) var terrariumBeforeCleanup: TerrariumState?
  /// A 120 × 80 pt still of the terrarium for the menu bar popover, refreshed after each scan
  /// and cleanup.
  @Published private(set) var terrariumSnapshot: NSImage?

  private let settingsStore: SettingsStore
  private let repository: ScanRepository
  private let permissionService: PermissionService
  private let deletionService: DeletionService
  private let exclusionStore: ExclusionStore
  private let cleanupLogStore: CleanupLogStore
  /// Confirmed cleanups, newest first.
  @Published private(set) var cleanupLog: [CleanupLogEntry]
  /// When the app first ran on this Mac; anchors the terrarium's age.
  let firstLaunchDate: Date
  private var scanner: ScannerService?
  private var pendingResults: [ScanResult] = []
  private var flushScheduled = false
  private var undoDismissal: Task<Void, Never>?
  private let systemSpace = SystemSpaceService()
  let notifications: NotificationCoordinator
  let statusMonitor: StatusMonitor
  let motion = MotionPolicy()
  let hungAppMonitor: HungAppMonitor
  let metrics = MetricsSampler()
  @Published private(set) var activeRules: ActiveRules
  @Published var ruleUpdateMessage: String?
  private let ruleRepository = RuleRepository()
  private let ruleUpdater = RuleUpdater()
  private var ruleTimer: Timer?
  @Published private(set) var protectionReport: MalwareScanReport?
  @Published private(set) var isProtectionScanning = false
  private var protectionScanner: MalwareScanner?
  private var realTimeMonitor: RealTimeMonitor?
  private let protectionStore = ProtectionStore()
  private let ignoredThreatsKey = "CleanScope.ignoredThreats"
  var lastProtectionScan: Date? { protectionReport?.date }
  var threatsFound: Int? { protectionReport?.threats.count }
  private var pressureSince: Date?
  private var pressureTimer: Timer?

  init(
    settingsStore: SettingsStore = SettingsStore(),
    repository: ScanRepository = ScanRepository(),
    permissionService: PermissionService = PermissionService(),
    deletionService: DeletionService = DeletionService(privileged: AppleScriptPrivilegedRunner()),
    exclusionStore: ExclusionStore = ExclusionStore(),
    cleanupLogStore: CleanupLogStore = CleanupLogStore()
  ) {
    self.settingsStore = settingsStore
    self.repository = repository
    self.permissionService = permissionService
    self.deletionService = deletionService
    self.exclusionStore = exclusionStore
    self.cleanupLogStore = cleanupLogStore
    cleanupLog = (try? cleanupLogStore.load()) ?? []
    let firstLaunchKey = "firstLaunchDate"
    if let stored = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date {
      firstLaunchDate = stored
    } else {
      let now = Date()
      UserDefaults.standard.set(now, forKey: firstLaunchKey)
      firstLaunchDate = now
    }
    let loadedSettings = (try? settingsStore.load()) ?? .default
    settings = loadedSettings
    activeRules = RuleRepository().loadActive()
    let notifications = NotificationCoordinator()
    self.notifications = notifications
    var settingsProvider: () -> CleanScopeCore.Settings = { loadedSettings }
    statusMonitor = StatusMonitor(
      notifications: notifications, settings: { settingsProvider() })
    hungAppMonitor = HungAppMonitor(notifications: notifications)
    exclusions = (try? exclusionStore.load()) ?? []
    session = try? repository.loadLatest()
    streamedResults = (session?.results ?? []).map { ExclusionRule.applying(exclusions, to: $0) }
    if let session {
      permissionSummary = permissionService.summary(skippedPaths: session.skippedPaths)
    }
    refreshDisk()
    settingsProvider = { [weak self] in self?.settings ?? loadedSettings }
    notifications.onAction = { [weak self] action in self?.handle(action) }
    statusMonitor.supplementalInputs = { [weak self] in self?.supplementalAlertInputs() ?? AlertInputs() }
    protectionReport = protectionStore.load()
    let monitor = RealTimeMonitor(
      rules: { [weak self] in self?.activeMalwareRules ?? .bundled },
      trustedTeamIDs: { [weak self] in Set(self?.settings.trustedTeamIDs ?? []) },
      onThreats: { [weak self] threats in self?.realTimeDetected(threats) })
    realTimeMonitor = monitor
    monitor.setEnabled(loadedSettings.realTimeProtectionEnabled)
    statusMonitor.start()
    hungAppMonitor.setEnabled(loadedSettings.hungAppMonitoringEnabled, prompt: false)
    updatePressureTracking()
    refreshTerrariumLayers()
    Task { @MainActor [weak self] in self?.refreshTerrariumSnapshot() }
    Task { await checkForRuleUpdates() }
    ruleTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.checkForRuleUpdates() }
    }
  }

  var hasScanned: Bool { session != nil }

  func results(for destination: Destination) -> [ScanResult] {
    streamedResults.filter {
      destination.includes($0, largeFileThreshold: settings.largeFileThresholdBytes) == true
    }
  }

  func currentResult(for result: ScanResult) -> ScanResult {
    streamedResults.first(where: { $0.id == result.id }) ?? result
  }

  /// Memory pressure, uptime and Bluetooth batteries for the alert evaluator.
  private func supplementalAlertInputs() -> AlertInputs {
    var inputs = AlertInputs()
    let level = MemoryService.pressureLevel()
    inputs.memoryPressureLevel = level
    inputs.pressureSince = pressureSince
    inputs.uptime = Uptime.bootTime().map { Uptime.since(bootTime: $0) }
    inputs.bluetooth = BluetoothBatteries.read()
    return inputs
  }

  /// Samples memory pressure every 30 seconds while the memory alert is on, so a sustained
  /// 2-minute episode can be noticed.
  private func updatePressureTracking() {
    pressureTimer?.invalidate()
    pressureTimer = nil
    pressureSince = nil
    guard settings.memoryAlertEnabled else { return }
    pressureTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if MemoryService.pressureLevel() >= 2 {
          if self.pressureSince == nil { self.pressureSince = Date() }
          self.statusMonitor.evaluateAlerts()
        } else {
          self.pressureSince = nil
        }
      }
    }
  }

  // MARK: - Protection

  /// The malware rules in effect: a verified downloaded set when present, else the bundled one.
  var activeMalwareRules: MalwareRuleSet { activeRules.malware }

  var ruleStatusLine: String {
    activeRules.version == 0 ? "Built in" : "Version \(activeRules.version)"
  }

  /// Checks for signed rule updates at most once a day while the app is open.
  func checkForRuleUpdates(force: Bool = false) async {
    let outcome = await ruleUpdater.checkForUpdates(force: force)
    switch outcome {
    case .updated:
      activeRules = ruleRepository.loadActive()
      ruleUpdateMessage = "Rules updated to version \(activeRules.version)."
    case .disabled:
      ruleUpdateMessage = force ? "Rule updates aren't set up in this build." : nil
    case .noUpdate:
      ruleUpdateMessage = force ? "Rules are up to date." : nil
    case .skippedRecently:
      ruleUpdateMessage = nil
    case .rejected(let reason), .failed(let reason):
      ruleUpdateMessage = force ? reason : nil
    }
  }

  private var ignoredThreatIDs: Set<String> {
    get { Set(UserDefaults.standard.stringArray(forKey: ignoredThreatsKey) ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: ignoredThreatsKey) }
  }

  func runProtectionScan(targets: [MalwareTarget] = MalwareTarget.standard) async {
    guard !isProtectionScanning else { return }
    isProtectionScanning = true
    let rules = activeMalwareRules
    let scanner = MalwareScanner(
      rules: rules, yara: ExternalYara(ruleSet: rules),
      trustedTeamIDs: Set(settings.trustedTeamIDs))
    protectionScanner = scanner
    var report = await scanner.scan(targets: targets)
    let ignored = ignoredThreatIDs
    report.threats.removeAll { ignored.contains($0.id) }
    protectionReport = report
    try? protectionStore.save(report)
    protectionScanner = nil
    isProtectionScanning = false
  }

  /// Adds real-time detections to the latest report and posts one notification each.
  private func realTimeDetected(_ threats: [Threat]) {
    let ignored = ignoredThreatIDs
    let fresh = threats.filter { !ignored.contains($0.id) }
    guard !fresh.isEmpty else { return }
    var report =
      protectionReport
      ?? MalwareScanReport(
        date: Date(), threats: [], scannedFiles: 0, yaraAvailable: false,
        ruleVersion: activeMalwareRules.version)
    let known = Set(report.threats.map(\.id))
    report.threats += fresh.filter { !known.contains($0.id) }
    protectionReport = report
    try? protectionStore.save(report)
    for threat in fresh where !known.contains(threat.id) {
      notifications.post(
        AlertPayload(
          kind: .malwareDetected, discriminator: threat.id,
          title: "CleanScope found \(threat.name)",
          body: "\(URL(fileURLWithPath: threat.location).lastPathComponent) matched a \(threat.category.title.lowercased()) rule. Review it in CleanScope."))
    }
  }

  func cancelProtectionScan() {
    Task { await protectionScanner?.cancel() }
  }

  func ignoreThreat(_ threat: Threat) {
    ignoredThreatIDs.insert(threat.id)
    forgetThreat(threat)
  }

  func forgetThreat(_ threat: Threat) {
    guard var report = protectionReport else { return }
    report.threats.removeAll { $0.id == threat.id }
    protectionReport = report
    try? protectionStore.save(report)
  }

  var statusSummary: StatusSummary {
    StatusSummary.evaluate(
      StatusInputs(
        disk: statusMonitor.disk,
        trashBytes: statusMonitor.trashBytes,
        threatsFound: threatsFound,
        lastProtectionScan: lastProtectionScan,
        batteryHealth: BatteryHealth.read()?.healthFraction,
        memoryPressure: MemoryService.pressureLevel()),
      thresholds: AlertThresholds(settings: settings))
  }

  // MARK: - Settings side effects

  /// A binding that writes only real changes. SwiftUI's `MenuBarExtra` keeps writing its
  /// `isInserted` value back; passing those no-op writes to the `@Published` settings rebuilt
  /// the whole scene each time and looped until the stack overflowed.
  func settingBinding<Value: Equatable>(
    _ keyPath: WritableKeyPath<CleanScopeCore.Settings, Value>
  ) -> Binding<Value> {
    Binding(
      get: { self.settings[keyPath: keyPath] },
      set: { newValue in
        if let updated = self.settings.replacing(keyPath, with: newValue) {
          self.settings = updated
        }
      })
  }

  private func settingsDidChange(from old: CleanScopeCore.Settings) {
    if old.showMenuBarExtra != settings.showMenuBarExtra {
      statusMonitor.reschedule()
    }
    if old.openAtLogin != settings.openAtLogin {
      updateOpenAtLogin(settings.openAtLogin)
    }
    if old.hungAppMonitoringEnabled != settings.hungAppMonitoringEnabled {
      hungAppMonitor.setEnabled(settings.hungAppMonitoringEnabled, prompt: true)
    }
    if old.memoryAlertEnabled != settings.memoryAlertEnabled {
      updatePressureTracking()
    }
    if old.realTimeProtectionEnabled != settings.realTimeProtectionEnabled {
      realTimeMonitor?.setEnabled(settings.realTimeProtectionEnabled)
    }
    metrics.includesTemperature = settings.experimentalTemperature
    let alertToggles: [KeyPath<CleanScopeCore.Settings, Bool>] = [
      \.lowDiskAlertEnabled, \.trashAlertEnabled, \.externalDriveAlertEnabled,
      \.memoryAlertEnabled, \.restartReminderEnabled, \.bluetoothBatteryAlertEnabled,
      \.hungAppMonitoringEnabled, \.realTimeProtectionEnabled, \.externalDriveMountedNotice,
    ]
    if alertToggles.contains(where: { !old[keyPath: $0] && settings[keyPath: $0] }) {
      Task { await notifications.requestAuthorizationIfNeeded() }
    }
  }

  private func updateOpenAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      openAtLoginError = nil
    } catch {
      openAtLoginError = "macOS did not allow this change: \(error.localizedDescription)"
    }
  }

  // MARK: - Notification actions

  func handle(_ action: NotificationCoordinator.Action) {
    NSApp.activate(ignoringOtherApps: true)
    switch action {
    case .scan:
      destination = .dashboard
      Task { await startScan() }
    case .openTrash:
      NSWorkspace.shared.open(TrashService.userTrash)
    case .scanDrive(let volumePath):
      Task { await scanDrive(at: volumePath) }
    case .open(let target):
      destination = target
    case .forceQuit(let pid):
      NSRunningApplication(processIdentifier: pid)?.forceTerminate()
    case .snooze(let kind, let discriminator, let option):
      statusMonitor.snooze(kind, discriminator: discriminator, option: option)
    case .ignoreThreat(let id):
      if let threat = protectionReport?.threats.first(where: { $0.id == id }) {
        ignoreThreat(threat)
      }
    }
  }

  /// Asks Finder to empty the Trash. Callers confirm with the user first.
  func emptyTrash() {
    var error: NSDictionary?
    NSAppleScript(source: TrashService.emptyTrashScript)?.executeAndReturnError(&error)
    statusMonitor.refresh()
  }

  // MARK: - Scanning

  func startScan() async {
    await startScan(mode: settings.scanDeveloperFolders ? .developer : .limited)
  }

  func startScan(mode: ScanMode) async {
    await startScan(paths: filteredLocations(for: mode), mode: mode)
  }

  /// Scans an external drive's root, including hidden folders such as `.Trashes`.
  func scanDrive(at path: String) async {
    var driveSettings = settings
    driveSettings.scanHiddenFolders = true
    destination = .safeCleanup
    await startScan(paths: [path], mode: .full, settings: driveSettings)
  }

  /// Scans explicit paths, for example an external drive's root.
  func startScan(
    paths: [String], mode: ScanMode, settings scanSettings: CleanScopeCore.Settings? = nil
  ) async {
    guard !isScanning else { return }
    let scanSettings = scanSettings ?? settings
    isScanning = true
    scanProgress = 0
    trashedResultIDs = []
    latestStreamedCategory = nil
    streamedResults = []
    pendingResults = []
    selection = []

    let activeScanner = ScannerService(
      classifier: ClassificationService(rules: activeRules.classification),
      largeFileThresholdBytes: settings.largeFileThresholdBytes
    )
    scanner = activeScanner
    let rules = exclusions
    var completed = await activeScanner.scan(
      paths: paths, mode: mode, settings: scanSettings,
      onProgress: { [weak self] done, total in
        Task { @MainActor in
          guard let self, self.isScanning else { return }
          // Progress only moves forward; hops can arrive out of order.
          self.scanProgress = max(self.scanProgress, Double(done) / Double(max(total, 1)))
        }
      }
    ) {
      [weak self] (result: ScanResult) in
      Task { @MainActor in
        guard let self, self.isScanning else { return }
        self.enqueue(ExclusionRule.applying(rules, to: result))
      }
    }

    if completed.status == .completed {
      let known = Set(completed.results.map(\.normalizedPath))
      let classification = activeRules.classification
      let leftovers = await Task.detached {
        LeftoverFinder(classifier: ClassificationService(rules: classification)).allLeftovers()
      }.value
      completed.results += leftovers.filter { !known.contains($0.normalizedPath) }
      completed.summary = ScanSummary(results: completed.results)
    }
    pendingResults = []
    session = completed
    streamedResults = completed.results.map { ExclusionRule.applying(rules, to: $0) }
    if settings.preselectSafeCaches && completed.status == .completed {
      // Built from the exclusion-applied results, so excluded items are never preselected.
      selection = ResultPresentation.preselection(for: streamedResults)
    }
    permissionSummary = permissionService.summary(skippedPaths: completed.skippedPaths)
    disk = Disk(totalBytes: completed.diskTotalBytes, availableBytes: completed.diskAvailableBytes)
    if settings.saveScanHistory {
      do { try repository.saveLatest(completed) } catch {
        report("This scan couldn’t be saved", error)
      }
    }
    scanner = nil
    if completed.status == .completed { scanProgress = 1 }
    isScanning = false
    refreshTerrariumSnapshot()
  }

  /// Verification hooks: `--open-destination "<name>"` and `--start-scan limited|developer|full`.
  func applyLaunchArguments(_ arguments: [String]) async {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    if let name = value(after: "--open-destination"), let match = Destination(argument: name) {
      destination = match
    }
    if let path = value(after: "--scan-path") {
      await startScan(paths: [path], mode: .limited)
    } else if let modeName = value(after: "--start-scan"), let mode = ScanMode(rawValue: modeName) {
      await startScan(mode: mode)
    }
  }

  func cancelScan() {
    scanner?.cancel()
  }

  /// Streams results to the UI in batches so a large scan publishes a few times a second,
  /// not once per file.
  private func enqueue(_ result: ScanResult) {
    pendingResults.append(result)
    guard !flushScheduled else { return }
    flushScheduled = true
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 150_000_000)
      flushScheduled = false
      guard isScanning, !pendingResults.isEmpty else { return }
      latestStreamedCategory = pendingResults.last?.category
      streamedResults.append(contentsOf: pendingResults)
      pendingResults = []
    }
  }

  #if DEBUG
    /// Puts the model into a mid-scan state from the saved scan without scanning anything:
    /// the first `progress` fraction of its results are streamed in.
    /// With `cancelled`, the scan has stopped where it was: not scanning, progress left in place.
    func debugSimulateScan(progress: Double, cancelled: Bool = false) {
      let fraction = min(max(progress, 0), 1)
      let all = session?.results ?? []
      let shown = Array(all.prefix(Int((Double(all.count) * fraction).rounded(.down))))
      isScanning = !cancelled
      scanProgress = fraction
      streamedResults = shown.map { ExclusionRule.applying(exclusions, to: $0) }
      latestStreamedCategory = shown.last?.category
    }

    /// Marks results as trashed without touching the file system, for the map's collapse check.
    func debugMarkTrashed(_ ids: Set<String>) {
      trashedResultIDs.formUnion(ids)
      selection.subtract(ids)
    }

    /// Pretends the largest Ready to Delete items were just moved to the Trash, for the Last
    /// Cleanup snapshot (`--snapshot-cleanup`). It never calls `DeletionService` and writes no
    /// files: the session and log entry live in memory only.
    func debugSeedCleanup() {
      let items = Array(
        ResultPresentation.outermost(results(for: .readyToDelete))
          .sorted { $0.sizeBytes > $1.sizeBytes }
          .prefix(6))
      guard !items.isEmpty else { return }
      let before = TerrariumState(layers: terrariumLayers, growthStage: terrariumGrowthStage)
      let available = disk?.availableBytes ?? 0
      let deleted = items.map {
        CleanupItemResult(
          scanResultId: $0.id, path: $0.path, sizeBytes: $0.sizeBytes, status: .deleted,
          message: "Moved to Trash")
      }
      var session = CleanupSession(
        completedAt: Date(), diskSpaceBeforeBytes: available, selectedItemIds: items.map(\.id),
        deletedItems: deleted, skippedItems: [], blockedItems: [], failedItems: [])
      session.diskSpaceAfterBytes = available + session.recoveredBytes
      cleanupLog.insert(
        CleanupLogEntry(completedAt: Date(), recoveredBytes: session.recoveredBytes), at: 0)
      debugMarkTrashed(Set(items.map(\.id)))
      terrariumBeforeCleanup = before
      cleanupSession = session
    }

    /// Replaces the session with a synthetic one for Storage Map checks (`--map-fixture`).
    func debugLoadMapFixture(_ fixture: ScanSession, selection fixtureSelection: Set<String>) {
      session = fixture
      trashedResultIDs = []
      streamedResults = fixture.results
      selection = fixtureSelection
    }
  #endif

  // MARK: - System space

  func refreshSystemSpace() async {
    purgeableBytes = systemSpace.purgeableBytes()
    localSnapshots = await systemSpace.localSnapshots()
  }

  /// Asks macOS to thin local snapshots. Returns a short outcome message for the UI.
  func thinLocalSnapshots(requestedBytes: Int64) async -> String {
    do {
      try await systemSpace.thin(requestedBytes: requestedBytes)
      await refreshSystemSpace()
      return "macOS finished thinning local snapshots."
    } catch SystemSpaceError.commandFailed(let message) {
      return message.isEmpty ? "macOS could not thin local snapshots." : message
    } catch {
      return "macOS could not thin local snapshots."
    }
  }

  // MARK: - Selection

  func toggleSelection(_ result: ScanResult) {
    setSelection(!selection.contains(result.id), for: result)
  }

  func setSelection(_ isSelected: Bool, for result: ScanResult) {
    guard result.canDelete, !result.isExcluded else {
      selection.remove(result.id)
      return
    }

    if isSelected {
      selection.insert(result.id)
    } else {
      selection.remove(result.id)
    }
  }

  func setSelection(_ isSelected: Bool, for results: [ScanResult]) {
    selection = ResultSelection.updating(selection, with: results, isSelected: isSelected)
  }

  func clearSelection() {
    selection.removeAll()
  }

  func selectedResults() -> [ScanResult] {
    streamedResults.filter {
      selection.contains($0.id) && $0.canDelete && !$0.isExcluded
    }
  }

  var selectionSummary: SelectionSummary {
    SelectionSummary(items: selectedResults())
  }

  // MARK: - Cleanup

  /// Removes exactly `items`, re-validated against the current results. Every destructive
  /// path in the app goes through `CleanupReviewSheet` before calling this. `method` defaults
  /// to the user's setting (Trash, or permanent deletion when "Delete immediately" is on).
  /// The Storage Map passes `navigatesToReport: false` to play its collapse first, then opens
  /// the report itself.
  func cleanup(
    _ items: [ScanResult], method: DeletionMethod? = nil, navigatesToReport: Bool = true
  ) async {
    // Every entry point is disabled while a cleanup runs; this backstop tells the user rather
    // than letting a confirmed review vanish silently.
    guard !isCleaningUp else {
      report(Self.cleanupRunningNote, CleanupBusyError())
      return
    }
    isCleaningUp = true
    defer { isCleaningUp = false }
    let plan = ResultSelection.cleanupPlan(
      reviewed: items, current: streamedResults, selection: selection)
    guard !plan.items.isEmpty else { return }
    let terrariumBefore = TerrariumState(layers: terrariumLayers, growthStage: terrariumGrowthStage)
    cleanupSession = await deletionService.cleanup(
      selected: plan.items, method: method ?? cleanupMethod)
    let removedAny = !(cleanupSession?.deletedItems.isEmpty ?? true)
    terrariumBeforeCleanup = removedAny ? terrariumBefore : nil
    if let session = cleanupSession, !session.deletedItems.isEmpty {
      do {
        try cleanupLogStore.append(
          CleanupLogEntry(
            completedAt: session.completedAt ?? Date(), recoveredBytes: session.recoveredBytes))
      } catch {
        report("Couldn't record this cleanup", error)
      }
      cleanupLog = (try? cleanupLogStore.load()) ?? cleanupLog
    }
    selection = plan.remainingSelection
    if let session = cleanupSession {
      trashedResultIDs.formUnion(session.deletedItems.map(\.scanResultId))
    }
    refreshDisk()
    refreshTerrariumSnapshot()
    if navigatesToReport { destination = .lastCleanup }
  }

  // MARK: - Terrarium

  /// 1…3 from the confirmed cleanups of the last 30 days.
  var terrariumGrowthStage: Int {
    let monthAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    return TerrariumLayout.growthStage(
      cleanupsInLast30Days: cleanupLog.filter { $0.completedAt > monthAgo }.count)
  }

  /// The terrarium layer glowing while a scan streams results in.
  var terrariumGlowingLayer: TerrariumLayer.Kind? {
    guard isScanning else { return nil }
    return latestStreamedCategory.map(TerrariumLayer.Kind.init(category:))
  }

  private func refreshTerrariumLayers() {
    let remaining =
      trashedResultIDs.isEmpty
      ? summary
      : ScanSummary(results: streamedResults.filter { !trashedResultIDs.contains($0.id) })
    let next = TerrariumLayout.layerHeights(for: remaining, diskUsedBytes: disk?.usedBytes ?? 0)
    if next != terrariumLayers { terrariumLayers = next }
  }

  /// Renders the popover thumbnail offscreen. Called after a scan or cleanup, never per render.
  private func refreshTerrariumSnapshot() {
    terrariumSnapshot = TerrariumScene.snapshot(
      layers: terrariumLayers, growthStage: terrariumGrowthStage)
  }

  var cleanupMethod: DeletionMethod {
    DeletionService.effectiveMethod(deleteImmediately: settings.deleteImmediately)
  }

  // MARK: - Exclusions

  func exclude(_ result: ScanResult) {
    let ruleType: ExclusionRuleType =
      result.itemType == .folder ? .folderRecursive : .exactPath
    let rule = ExclusionRule(
      path: result.normalizedPath,
      ruleType: ruleType,
      reason: "Excluded from CleanScope results"
    )

    do {
      try exclusionStore.add(rule)
    } catch {
      report("\(result.name) couldn’t be excluded", error)
      return
    }

    exclusions = (try? exclusionStore.load()) ?? exclusions + [rule]
    let affected = streamedResults.filter { rule.matches(path: $0.normalizedPath) }
    selection.subtract(affected.map(\.id))
    streamedResults = streamedResults.map { ExclusionRule.applying([rule], to: $0) }
    showUndo(ExclusionUndo(rule: rule, name: result.name, previous: affected))
  }

  func undoExclusion(_ undo: ExclusionUndo) {
    do {
      try exclusionStore.remove(id: undo.rule.id)
    } catch {
      report("The exclusion couldn’t be undone", error)
      return
    }
    exclusions.removeAll { $0.id == undo.rule.id }
    let restored = Dictionary(undo.previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    streamedResults = streamedResults.map { restored[$0.id] ?? $0 }
    exclusionUndo = nil
  }

  /// Removes a saved rule. Items already marked excluded return on the next scan.
  func removeExclusion(_ rule: ExclusionRule) {
    do {
      try exclusionStore.remove(id: rule.id)
      exclusions.removeAll { $0.id == rule.id }
    } catch {
      report("The exclusion couldn’t be removed", error)
    }
  }

  private func showUndo(_ undo: ExclusionUndo) {
    exclusionUndo = undo
    undoDismissal?.cancel()
    undoDismissal = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 8_000_000_000)
      guard !Task.isCancelled, self?.exclusionUndo?.id == undo.id else { return }
      self?.exclusionUndo = nil
    }
  }

  // MARK: - Helpers

  private func recomputeDerived() {
    summary = ScanSummary(results: streamedResults)
    defer { refreshTerrariumLayers() }
    safeCount = streamedResults.filter { $0.category == .safeToDelete }.count
    reviewCount = streamedResults.filter {
      $0.category == .probablyUnused || $0.category == .deleteIfAppUnused
    }.count
    var next: [Destination: Int] = [:]
    for destination in Destination.allCases where destination.isResultList {
      next[destination] = results(for: destination).count
    }
    counts = next
  }

  private func refreshDisk() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let values = try? home.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ])
    guard let total = values?.volumeTotalCapacity, total > 0 else { return }
    disk = Disk(
      totalBytes: Int64(total),
      availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0
    )
  }

  private func report(_ title: String, _ error: Error) {
    alert = AppAlert(title: title, message: error.localizedDescription)
  }

  private func filteredLocations(for mode: ScanMode) -> [String] {
    ScanLocations.recommended(mode: mode).filter { path in
      if !settings.scanDownloads && path.localizedCaseInsensitiveContains("/Downloads") {
        return false
      }
      if !settings.scanDeveloperFolders && mode == .developer {
        let limited = Set(ScanLocations.recommended(mode: .limited))
        return limited.contains(path)
      }
      if !settings.scanAppSupport && path.localizedCaseInsensitiveContains("/Application Support") {
        return false
      }
      return true
    }
  }
}
