import Foundation

/// What the menu bar icon shows: how far the sprout has grown and whether a size label appears.
public enum MenuBarPresentation {
  /// 0 = bare lens, 1 = stem and one leaf, 2 = both leaves.
  public static func sproutStage(daysSinceCleanup: Int, safeBytes: Int64) -> Int {
    if daysSinceCleanup < 5 || safeBytes < 250_000_000 { return 0 }
    if daysSinceCleanup >= 12 && safeBytes >= 1_000_000_000 { return 2 }
    return 1
  }

  /// The size shown beside the icon, once caches have been waiting two weeks.
  public static func sizeLabel(daysSinceCleanup: Int, safeBytes: Int64) -> String? {
    guard daysSinceCleanup >= 14, safeBytes >= 500_000_000 else { return nil }
    return ByteCount.string(safeBytes)
  }

  /// The menu bar item's accessibility label, extended when the size label shows.
  public static func accessibilityLabel(sizeLabel: String?) -> String {
    guard let sizeLabel else { return "CleanScope" }
    return "CleanScope, \(sizeLabel) of caches ready"
  }

  /// Whole days since the newest cleanup (the log is newest first), else since first launch.
  public static func daysSinceCleanup(log: [CleanupLogEntry], firstLaunch: Date, now: Date) -> Int
  {
    let start = log.first?.completedAt ?? firstLaunch
    let days = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
    return max(days, 0)
  }
}
