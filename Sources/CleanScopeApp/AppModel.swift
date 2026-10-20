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
    case cleanupHistory = "Cleanup History"
    case settings = "Settings"

    var id: String { rawValue }

    var section: Section {
      switch self {
      case .cleanupHistory, .settings: return .history
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
    let notifications = NotificationCoordinator()
    self.notifications = notifications
    var settingsProvider: () -> CleanScopeCore.Settings = { loadedSettings }
    statusMonitor = StatusMonitor(
      notifications: notifications, settings: { settingsProvider() })
    session = try? repository.loadLatest()
    streamedResults = session?.results ?? []
    if let session {
      permissionSummary = permissionService.summary(skippedPaths: session.skippedPaths)
    }
    settingsProvider = { [weak self] in self?.settings ?? loadedSettings }
    notifications.onAction = { [weak self] action in self?.handle(action) }
    statusMonitor.start()
  }

  // MARK: - Settings side effects

  private func settingsDidChange(from old: CleanScopeCore.Settings) {
    if old.showMenuBarExtra != settings.showMenuBarExtra {
      statusMonitor.reschedule()
    }
    if old.openAtLogin != settings.openAtLogin {
      updateOpenAtLogin(settings.openAtLogin)
    }
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
      classifier: ClassificationService(),
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
      let leftovers = await Task.detached { LeftoverFinder().allLeftovers() }.value
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
