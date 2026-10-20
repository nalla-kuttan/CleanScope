import AppKit
import CleanScopeCore
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  enum Destination: String, CaseIterable, Identifiable {
    enum Section: String, CaseIterable, Identifiable {
      case storage = "Storage"
      case performance = "Performance"
      case protection = "Protection"
      case history = "History"

      var id: String { rawValue }
    }

    case dashboard = "Dashboard"
    case storageMap = "Storage Map"
    case safeCleanup = "Safe Cleanup"
    case readyToDelete = "Ready to Delete"
    case largeFiles = "Large Files"
    case hiddenFolders = "Hidden Folders"
    case developerFiles = "Developer Files"
    case appSupport = "App Support"
    case downloads = "Downloads"
    case trash = "Trash"
    case leftovers = "Leftovers"
    case maintenance = "Maintenance"
    case loginItems = "Login Items"
    case backgroundItems = "Background Items"
    case memory = "Memory"
    case protection = "Protection"
    case privacy = "Privacy"
    case cleanupHistory = "Cleanup History"
    case settings = "Settings"

    var id: String { rawValue }

    var section: Section {
      switch self {
      case .cleanupHistory, .settings: return .history
      case .protection, .privacy: return .protection
      case .maintenance, .loginItems, .backgroundItems, .memory: return .performance
      default: return .storage
      }
    }

    var systemImage: String {
      switch self {
      case .dashboard: return "chart.bar.xaxis"
      case .storageMap: return "square.grid.3x3.square"
      case .safeCleanup: return "checkmark.shield"
      case .readyToDelete: return "externaldrive.badge.checkmark"
      case .largeFiles: return "externaldrive.fill"
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
      case .cleanupHistory: return "clock.arrow.circlepath"
      case .settings: return "gearshape"
      }
    }
  }

  @Published var destination: Destination? = .dashboard
  @Published var settings: CleanScopeCore.Settings {
    didSet {
      try? settingsStore.save(settings)
      settingsDidChange(from: oldValue)
    }
  }
  @Published var session: ScanSession?
  @Published var streamedResults: [ScanResult] = []
  @Published var selection: Set<String> = []
  @Published var cleanupSession: CleanupSession?
  @Published var isScanning = false
  @Published var permissionSummary = PermissionSummary(
    isLikelyComplete: true,
    message: "Scan not started.",
    setupSteps: []
  )
  @Published var openAtLoginError: String?
  @Published var purgeableBytes: Int64 = 0
  @Published var localSnapshots: [Date] = []

  private let settingsStore: SettingsStore
  private let repository: ScanRepository
  private let permissionService: PermissionService
  private let deletionService: DeletionService
  private let exclusionStore: ExclusionStore
  private var scanner: ScannerService?
  private let systemSpace = SystemSpaceService()
  let notifications: NotificationCoordinator
  let statusMonitor: StatusMonitor
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
    exclusionStore: ExclusionStore = ExclusionStore()
  ) {
    self.settingsStore = settingsStore
    self.repository = repository
    self.permissionService = permissionService
    self.deletionService = deletionService
    self.exclusionStore = exclusionStore
    let loadedSettings = (try? settingsStore.load()) ?? .default
    settings = loadedSettings
    activeRules = RuleRepository().loadActive()
    let notifications = NotificationCoordinator()
    self.notifications = notifications
    var settingsProvider: () -> CleanScopeCore.Settings = { loadedSettings }
    statusMonitor = StatusMonitor(
      notifications: notifications, settings: { settingsProvider() })
    hungAppMonitor = HungAppMonitor(notifications: notifications)
    session = try? repository.loadLatest()
    streamedResults = session?.results ?? []
    if let session {
      permissionSummary = permissionService.summary(skippedPaths: session.skippedPaths)
    }
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
    Task { await checkForRuleUpdates() }
    ruleTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.checkForRuleUpdates() }
    }
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
      Task { await startScan(mode: settings.scanDeveloperFolders ? .developer : .limited) }
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
    BrandTheme.triggerHaptic()
    isScanning = true
    streamedResults = []
    selection = []

    let activeScanner = ScannerService(
      classifier: ClassificationService(rules: activeRules.classification),
      largeFileThresholdBytes: settings.largeFileThresholdBytes
    )
    scanner = activeScanner
    var completed = await activeScanner.scan(paths: paths, mode: mode, settings: scanSettings) {
      [weak self] (result: ScanResult) in
      Task { @MainActor in
        guard let self, self.isScanning else { return }
        self.streamedResults.append(result)
      }
    }

    if completed.status == .completed {
      let known = Set(completed.results.map(\.normalizedPath))
      let rules = activeRules.classification
      let leftovers = await Task.detached {
        LeftoverFinder(classifier: ClassificationService(rules: rules)).allLeftovers()
      }.value
      completed.results += leftovers.filter { !known.contains($0.normalizedPath) }
      completed.summary = ScanSummary(results: completed.results)
    }
    session = completed
    streamedResults = completed.results
    if settings.preselectSafeCaches && completed.status == .completed {
      selection = ResultPresentation.preselection(for: completed.results)
    }
    permissionSummary = permissionService.summary(skippedPaths: completed.skippedPaths)
    if settings.saveScanHistory {
      try? repository.saveLatest(completed)
    }
    scanner = nil
    isScanning = false
    BrandTheme.triggerHaptic()
  }

  /// Verification hooks: `--open-destination "<name>"` and `--start-scan limited|developer|full`.
  func applyLaunchArguments(_ arguments: [String]) async {
    func value(after flag: String) -> String? {
      guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
        return nil
      }
      return arguments[index + 1]
    }
    if let name = value(after: "--open-destination"), let match = Destination(rawValue: name) {
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

  func cleanupSelected() async {
    cleanupSession = await deletionService.cleanup(
      selected: selectedResults(), method: cleanupMethod)
    selection = []
    destination = .cleanupHistory
  }

  func cleanup(_ result: ScanResult) async {
    guard result.canDelete else { return }
    cleanupSession = await deletionService.cleanup(selected: [result], method: cleanupMethod)
    selection.remove(result.id)
    destination = .cleanupHistory
  }

  var cleanupMethod: DeletionMethod {
    DeletionService.effectiveMethod(deleteImmediately: settings.deleteImmediately)
  }

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
      selection.remove(result.id)
      streamedResults = streamedResults.map { item in
        guard exclusionRule(rule, matches: item.normalizedPath) else { return item }
        var excluded = item
        excluded.isExcluded = true
        excluded.canDelete = false
        excluded.deletionMethod = .notAllowed
        return excluded
      }
    } catch {
      return
    }
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

  private func exclusionRule(_ rule: ExclusionRule, matches path: String) -> Bool {
    let rulePath = URL(fileURLWithPath: rule.path).standardizedFileURL.path
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    switch rule.ruleType {
    case .exactPath:
      return normalized == rulePath
    case .folderRecursive:
      return normalized == rulePath || normalized.hasPrefix(rulePath + "/")
    case .pattern:
      return normalized.localizedCaseInsensitiveContains(rule.path)
    case .category:
      return false
    }
  }
}
