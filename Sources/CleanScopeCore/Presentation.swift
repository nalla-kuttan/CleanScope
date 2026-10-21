import Foundation

public struct SelectionSummary: Equatable, Sendable {
  public let itemCount: Int
  public let totalBytes: Int64
  public let categoryCounts: [SafetyCategory: Int]

  public init(items: [ScanResult]) {
    itemCount = items.count
    totalBytes = ResultPresentation.totalBytes(items)
    categoryCounts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
  }
}

public enum CountPhrase {
  /// "1 item", "2,709 items". English-only inflection, matching the rest of the app's copy.
  public static func make(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    let number = count.formatted(.number)
    return "\(number) \(count == 1 ? singular : (plural ?? singular + "s"))"
  }
}

/// Which face the Dashboard hero shows.
public enum HeroState: Equatable, Sendable {
  case idle, scanning, results, cleaned

  /// The brand mark's growth stage for this state: lens only, stem, first leaf, both leaves.
  public var sproutStage: Int {
    switch self {
    case .idle: 0
    case .scanning: 1
    case .results: 2
    case .cleaned: 3
    }
  }
}

public enum StoragePresentation {
  /// Scanning beats cleaned beats results beats idle.
  public static func heroState(hasScanned: Bool, isScanning: Bool, cleanedThisSession: Bool)
    -> HeroState
  {
    if isScanning { return .scanning }
    if cleanedThisSession { return .cleaned }
    return hasScanned ? .results : .idle
  }

  public static func headline(hasScanned: Bool, isScanning: Bool, safeBytes: Int64) -> String {
    if isScanning { return "Looking for room to grow…" }
    guard hasScanned else { return "Let’s see where your space went." }
    guard safeBytes > 0 else { return "Your Mac is already breathing easy." }
    return "You found \(ByteCount.string(safeBytes)) of breathing room."
  }

  public static func reviewLine(count: Int) -> String? {
    guard count > 0 else { return nil }
    return "\(CountPhrase.make(count, "item")) \(count == 1 ? "deserves" : "deserve") a closer look."
  }

  /// The hero's sub-line: the first-run reassurance before any scan, the live count while
  /// scanning, and the disk weather once there are results (or a cleanup).
  public static func heroSubline(
    state: HeroState, itemsFound: Int, usedFraction: Double, availableBytes: Int64,
    safeBytes: Int64
  ) -> String {
    switch state {
    case .idle:
      return "CleanScope checks known cleanup locations. Nothing is removed until you review it."
    case .scanning:
      return "\(CountPhrase.make(itemsFound, "item")) found so far."
    case .results, .cleaned:
      return weatherLine(
        usedFraction: usedFraction, availableBytes: availableBytes, safeBytes: safeBytes)
    }
  }

  /// The Dashboard's calm disk-weather line. Only the tightest tier quotes figures, and it
  /// promises quick wins only when there are some.
  public static func weatherLine(usedFraction: Double, availableBytes: Int64, safeBytes: Int64)
    -> String
  {
    if usedFraction < 0.70 { return "Plenty of room." }
    if usedFraction < 0.88 { return "Getting cozy." }
    var line = "Room is tight. \(ByteCount.string(availableBytes)) available."
    if safeBytes > 0 {
      line += " Quick wins can free \(ByteCount.string(safeBytes)) without touching your files."
    }
    return line
  }

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
  /// Drops results that sit inside another result's folder, keeping the original order.
  /// Scans report nested folders separately, so summing every result double-counts bytes.
  public static func outermost(_ results: [ScanResult]) -> [ScanResult] {
    let paths = Set(results.map(\.normalizedPath))
    return results.filter { !hasAncestor($0.normalizedPath, in: paths) }
  }

  /// Results still on disk: leaves out the given ids and anything that sat inside one of those
  /// items, so a trashed folder's nested results are not counted on their own afterwards.
  public static func remaining(_ results: [ScanResult], excluding ids: Set<String>) -> [ScanResult] {
    guard !ids.isEmpty else { return results }
    let gonePaths = Set(results.filter { ids.contains($0.id) }.map(\.normalizedPath))
    return results.filter {
      !ids.contains($0.id) && !hasAncestor($0.normalizedPath, in: gonePaths)
    }
  }

  public static func totalBytes(_ results: [ScanResult]) -> Int64 {
    outermost(results).reduce(0) { $0 + $1.sizeBytes }
  }

  static func hasAncestor(_ path: String, in paths: Set<String>) -> Bool {
    var parent = (path as NSString).deletingLastPathComponent
    while !parent.isEmpty, parent != "/" {
      if paths.contains(parent) { return true }
      parent = (parent as NSString).deletingLastPathComponent
    }
    return false
  }

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

extension ResultPresentation {
  /// Ids to select after a scan when "Preselect Ready to Delete caches" is on.
  public static func preselection(for results: [ScanResult]) -> Set<String> {
    Set(results.filter(isReadyToDeleteCache).map(\.id))
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
    let reviewedEligible = reviewed.compactMap { item -> ScanResult? in
      guard seen.insert(item.id).inserted, let latest = currentByID[item.id] else { return nil }
      return eligible([latest]).first
    }
    // Trashing a folder takes its contents with it, so only the outermost items move and
    // anything inside them leaves the selection too.
    let items = ResultPresentation.outermost(reviewedEligible)
    let trashedPaths = Set(items.map(\.normalizedPath))
    let gone = current.filter {
      trashedPaths.contains($0.normalizedPath)
        || ResultPresentation.hasAncestor($0.normalizedPath, in: trashedPaths)
    }
    let removed = Set(reviewedEligible.map(\.id)).union(gone.map(\.id))
    return CleanupPlan(items: items, remainingSelection: selection.subtracting(removed))
  }
}

public struct CleanupPlan: Equatable, Sendable {
  public let items: [ScanResult]
  public let remainingSelection: Set<String>
}
