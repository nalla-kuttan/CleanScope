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
