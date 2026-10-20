import CleanScopeCore
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  enum Destination: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case readyToDelete
    case safeCleanup
    case largeFiles
    case hiddenFolders
    case developerFiles
    case appSupport
    case downloads
    case trash
    case lastCleanup

    var id: String { rawValue }

    static let sections: [(title: String, destinations: [Destination])] = [
      ("Overview", [.dashboard, .readyToDelete, .safeCleanup]),
      ("Browse", [.largeFiles, .hiddenFolders, .developerFiles, .appSupport, .downloads, .trash]),
      ("Activity", [.lastCleanup]),
    ]

    var title: String {
      switch self {
      case .dashboard: return "Dashboard"
      case .readyToDelete: return "Ready to Delete"
      case .safeCleanup: return "Safe Cleanup"
      case .largeFiles: return "Large Files"
      case .hiddenFolders: return "Hidden Folders"
      case .developerFiles: return "Developer Files"
      case .appSupport: return "App Support"
      case .downloads: return "Downloads"
      case .trash: return "Trash"
      case .lastCleanup: return "Last Cleanup"
      }
    }

    var systemImage: String {
      switch self {
      case .dashboard: return "square.grid.2x2"
      case .readyToDelete: return "externaldrive.badge.checkmark"
      case .safeCleanup: return "checkmark.shield"
      case .largeFiles: return "externaldrive"
      case .hiddenFolders: return "eye.slash"
      case .developerFiles: return "hammer"
      case .appSupport: return "shippingbox"
      case .downloads: return "arrow.down.circle"
      case .trash: return "trash"
      case .lastCleanup: return "clock.arrow.circlepath"
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
      case .dashboard, .lastCleanup: return nil
      }
    }

    var emptyTitle: String {
      switch self {
      case .readyToDelete: return "No cache files are ready"
      default: return "Nothing in \(title) yet"
      }
    }

    var isResultList: Bool { self != .dashboard && self != .lastCleanup }

    /// `nil` for destinations that are not result lists.
    func includes(_ result: ScanResult, largeFileThreshold: Int64) -> Bool? {
      switch self {
      case .dashboard, .lastCleanup: return nil
      case .readyToDelete: return ResultPresentation.isReadyToDeleteCache(result)
      case .safeCleanup: return result.category == .safeToDelete
      case .largeFiles: return result.sizeBytes >= largeFileThreshold
      case .hiddenFolders: return result.isHidden
      case .developerFiles: return result.ownerTool != nil
      case .appSupport:
        return result.normalizedPath.localizedCaseInsensitiveContains("/Library/Application Support/")
      case .downloads: return result.normalizedPath.localizedCaseInsensitiveContains("/Downloads/")
      case .trash: return result.normalizedPath.localizedCaseInsensitiveContains("/.Trash/")
      }
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
    }
  }
  @Published var session: ScanSession?
  @Published private(set) var streamedResults: [ScanResult] = [] {
    didSet { recomputeDerived() }
  }
  @Published var selection: Set<String> = []
  @Published var cleanupSession: CleanupSession?
  @Published var isScanning = false
  @Published var permissionSummary: PermissionSummary?
  @Published var disk: Disk?
  @Published var exclusions: [ExclusionRule] = []
  @Published var alert: AppAlert?
  @Published var exclusionUndo: ExclusionUndo?
  #if DEBUG
    /// Lets `DebugSnapshot` open an item's detail sheet.
    @Published var debugDetail: ScanResult?
  #endif

  /// Derived once per results change instead of on every view render.
  @Published private(set) var summary = ScanSummary()
  @Published private(set) var counts: [Destination: Int] = [:]
  @Published private(set) var safeCount = 0
  @Published private(set) var reviewCount = 0

  private let settingsStore: SettingsStore
  private let repository: ScanRepository
  private let permissionService: PermissionService
  private let deletionService: DeletionService
  private let exclusionStore: ExclusionStore
  private var scanner: ScannerService?
  private var pendingResults: [ScanResult] = []
  private var flushScheduled = false
  private var undoDismissal: Task<Void, Never>?

  init(
    settingsStore: SettingsStore = SettingsStore(),
    repository: ScanRepository = ScanRepository(),
    permissionService: PermissionService = PermissionService(),
    deletionService: DeletionService = DeletionService(),
    exclusionStore: ExclusionStore = ExclusionStore()
  ) {
    self.settingsStore = settingsStore
    self.repository = repository
    self.permissionService = permissionService
    self.deletionService = deletionService
    self.exclusionStore = exclusionStore
    settings = (try? settingsStore.load()) ?? .default
    exclusions = (try? exclusionStore.load()) ?? []
    session = try? repository.loadLatest()
    streamedResults = (session?.results ?? []).map { ExclusionRule.applying(exclusions, to: $0) }
    if let session {
      permissionSummary = permissionService.summary(skippedPaths: session.skippedPaths)
    }
    refreshDisk()
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

  // MARK: - Scanning

  func startScan() async {
    await startScan(mode: settings.scanDeveloperFolders ? .developer : .limited)
  }

  func startScan(mode: ScanMode) async {
    guard !isScanning else { return }
    isScanning = true
    streamedResults = []
    pendingResults = []
    selection = []

    let activeScanner = ScannerService(
      classifier: ClassificationService(),
      largeFileThresholdBytes: settings.largeFileThresholdBytes
    )
    scanner = activeScanner
    let rules = exclusions
    let paths = filteredLocations(for: mode)
    let completed = await activeScanner.scan(paths: paths, mode: mode, settings: settings) {
      [weak self] (result: ScanResult) in
      Task { @MainActor in
        guard let self, self.isScanning else { return }
        self.enqueue(ExclusionRule.applying(rules, to: result))
      }
    }

    pendingResults = []
    session = completed
    streamedResults = completed.results.map { ExclusionRule.applying(rules, to: $0) }
    permissionSummary = permissionService.summary(skippedPaths: completed.skippedPaths)
    disk = Disk(totalBytes: completed.diskTotalBytes, availableBytes: completed.diskAvailableBytes)
    if settings.saveScanHistory {
      do { try repository.saveLatest(completed) } catch {
        report("This scan couldn’t be saved", error)
      }
    }
    scanner = nil
    isScanning = false
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
      streamedResults.append(contentsOf: pendingResults)
      pendingResults = []
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

  // MARK: - Cleanup

  /// Moves exactly `items` to Trash, re-validated against the current results. Every
  /// destructive path in the app goes through `CleanupReviewSheet` before calling this.
  func cleanup(_ items: [ScanResult]) async {
    let plan = ResultSelection.cleanupPlan(
      reviewed: items, current: streamedResults, selection: selection)
    guard !plan.items.isEmpty else { return }
    cleanupSession = await deletionService.cleanup(selected: plan.items)
    selection = plan.remainingSelection
    refreshDisk()
    destination = .lastCleanup
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
