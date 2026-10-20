import Foundation

/// One soil layer of the terrarium, sized from a storage category.
public struct TerrariumLayer: Equatable, Sendable {
  public enum Kind: CaseIterable, Sendable { case system, personal, appData, review, safe }

  public var kind: Kind
  public var bytes: Int64
  public var height: Double

  public init(kind: Kind, bytes: Int64, height: Double) {
    self.kind = kind
    self.bytes = bytes
    self.height = height
  }
}

/// Pure math mapping storage categories to terrarium soil-layer heights.
public enum TerrariumLayout {
  /// Layers ordered bottom to top: system, personal, app data, review, safe.
  public static func layerHeights(for summary: ScanSummary, diskUsedBytes: Int64) -> [TerrariumLayer] {
    let personal = max(summary.doNotBulkDeleteBytes, 0)
    let appData = max(summary.deleteIfAppUnusedBytes, 0)
    let review = max(summary.probablyUnusedBytes, 0)
    let safe = max(summary.safeToDeleteBytes, 0)
    let system = max(diskUsedBytes - (personal + appData + review + safe), 0)
    let bytesByKind: [(TerrariumLayer.Kind, Int64)] = [
      (.system, system), (.personal, personal), (.appData, appData), (.review, review),
      (.safe, safe),
    ]
    return bytesByKind.map { TerrariumLayer(kind: $0.0, bytes: $0.1, height: height(forBytes: $0.1)) }
  }

  /// 1 = bare, 2 = sprouting, 3 = flourishing.
  public static func growthStage(cleanupsInLast30Days: Int) -> Int {
    switch cleanupsInLast30Days {
    case ..<1: return 1
    case 1...2: return 2
    default: return 3
    }
  }

  private static func height(forBytes bytes: Int64) -> Double {
    let gigabytes = Double(max(bytes, 0)) / 1e9
    return (0.12 + gigabytes.squareRoot() * 0.06) * 0.55
  }
}
