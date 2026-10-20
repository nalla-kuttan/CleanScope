import Foundation

public struct SelectionSummary: Equatable, Sendable {
  public let itemCount: Int
  public let totalBytes: Int64
  public let categoryCounts: [SafetyCategory: Int]

  public init(items: [ScanResult]) {
    itemCount = items.count
    totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
    categoryCounts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
  }
}

public enum StoragePresentation {
  public static func reclaimCopy(bytes: Int64) -> String {
    switch bytes {
    case ..<1:
      return "Your Mac is already breathing easy."
    case ..<1_000_000_000:
      return "A little more room for your next side project."
    default:
      return "Enough room for thousands of photos or a few ambitious side projects."
    }
  }

  public static func growthStage(resultCount: Int, isScanning: Bool) -> Int {
    guard isScanning || resultCount > 0 else { return 0 }
    if resultCount < 10 { return 1 }
    if resultCount < 40 { return 2 }
    return 3
  }
}

public enum ResultPresentation {
  public static func isReadyToDeleteCache(_ result: ScanResult) -> Bool {
    guard
      result.category == .safeToDelete,
      result.confidence == .high,
      result.canDelete,
      !result.isExcluded
    else { return false }

    let path = result.normalizedPath.lowercased()
    let components = Set(
      URL(fileURLWithPath: result.normalizedPath).pathComponents.map { $0.lowercased() })

    return path.contains("/library/caches/")
      || path.contains("/.cache/")
      || components.contains(".npm")
      || components.contains(".yarn")
      || components.contains(".pnpm-store")
      || path.contains("/library/caches/pip")
  }
}

public enum VisibleSelectionState: Equatable, Sendable {
  case none
  case some
  case all
}

public enum ResultSelection {
  public static func eligible(_ results: [ScanResult]) -> [ScanResult] {
    results.filter { $0.canDelete && !$0.isExcluded }
  }

  public static func state(
    visible results: [ScanResult],
    selectedIDs: Set<String>
  ) -> VisibleSelectionState {
    let ids = Set(eligible(results).map(\.id))
    guard !ids.isEmpty else { return .none }
    let selectedVisible = ids.intersection(selectedIDs)
    if selectedVisible.isEmpty { return .none }
    return selectedVisible == ids ? .all : .some
  }

  public static func eligibleIDs(
    in results: [ScanResult],
    from anchorID: String,
    through targetID: String
  ) -> [String] {
    guard
      let anchor = results.firstIndex(where: { $0.id == anchorID }),
      let target = results.firstIndex(where: { $0.id == targetID })
    else { return [] }

    let bounds = min(anchor, target)...max(anchor, target)
    return results[bounds]
      .filter { $0.canDelete && !$0.isExcluded }
      .map(\.id)
  }

  public static func updating(
    _ selection: Set<String>,
    with results: [ScanResult],
    isSelected: Bool
  ) -> Set<String> {
    let ids = Set(eligible(results).map(\.id))
    if isSelected {
      return selection.union(ids)
    }
    return selection.subtracting(ids)
  }

  /// Limits a cleanup to exactly the reviewed items that are still eligible in the current
  /// results, and removes only those items from the selection.
  public static func cleanupPlan(
    reviewed: [ScanResult],
    current: [ScanResult],
    selection: Set<String>
  ) -> CleanupPlan {
    let currentByID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    let items = reviewed.compactMap { item -> ScanResult? in
      guard seen.insert(item.id).inserted, let latest = currentByID[item.id] else { return nil }
      return eligible([latest]).first
    }
    return CleanupPlan(items: items, remainingSelection: selection.subtracting(items.map(\.id)))
  }
}

public struct CleanupPlan: Equatable, Sendable {
  public let items: [ScanResult]
  public let remainingSelection: Set<String>
}
