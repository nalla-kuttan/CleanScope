import CleanScopeCore
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  enum Destination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case safeCleanup = "Safe Cleanup"
    case largeFiles = "Large Files"
    case hiddenFolders = "Hidden Folders"
    case developerFiles = "Developer Files"
    case appSupport = "App Support"
    case downloads = "Downloads"
    case trash = "Trash"
    case cleanupHistory = "Cleanup History"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
      switch self {
      case .dashboard: return "chart.bar.xaxis"
      case .safeCleanup: return "checkmark.shield"
      case .largeFiles: return "externaldrive.fill"
      case .hiddenFolders: return "eye.slash"
      case .developerFiles: return "hammer"
      case .appSupport: return "shippingbox"
      case .downloads: return "arrow.down.circle"
      case .trash: return "trash"
      case .cleanupHistory: return "clock.arrow.circlepath"
      case .settings: return "gearshape"
      }
    }
  }

  @Published var destination: Destination? = .dashboard
  @Published var settings: CleanScopeCore.Settings {
    didSet { try? settingsStore.save(settings) }
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

  private let settingsStore: SettingsStore
  private let repository: ScanRepository
  private let permissionService: PermissionService
  private let deletionService: DeletionService
  private let exclusionStore: ExclusionStore
  private var scanner: ScannerService?

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
    session = try? repository.loadLatest()
    streamedResults = session?.results ?? []
    if let session {
      permissionSummary = permissionService.summary(skippedPaths: session.skippedPaths)
    }
  }

  func startScan(mode: ScanMode) async {
    guard !isScanning else { return }
    isScanning = true
    streamedResults = []
    selection = []

    let activeScanner = ScannerService(
      classifier: ClassificationService(),
      largeFileThresholdBytes: settings.largeFileThresholdBytes
    )
    scanner = activeScanner
    let paths = filteredLocations(for: mode)
    let completed = await activeScanner.scan(paths: paths, mode: mode, settings: settings) {
      [weak self] (result: ScanResult) in
      Task { @MainActor in
        guard let self, self.isScanning else { return }
        self.streamedResults.append(result)
      }
    }

    session = completed
    streamedResults = completed.results
    permissionSummary = permissionService.summary(skippedPaths: completed.skippedPaths)
    if settings.saveScanHistory {
      try? repository.saveLatest(completed)
    }
    scanner = nil
    isScanning = false
  }

  func cancelScan() {
    scanner?.cancel()
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
    cleanupSession = await deletionService.cleanup(selected: selectedResults())
    selection = []
    destination = .cleanupHistory
  }

  func cleanup(_ result: ScanResult) async {
    guard result.canDelete else { return }
    cleanupSession = await deletionService.cleanup(selected: [result])
    selection.remove(result.id)
    destination = .cleanupHistory
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
