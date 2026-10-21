import Foundation

/// One soil layer of the terrarium, sized from a storage category.
public struct TerrariumLayer: Equatable, Sendable {
  public enum Kind: CaseIterable, Sendable {
    case system, personal, appData, review, safe

    /// The layer a scan result of `category` belongs to (it glows while such results stream in).
    public init(category: SafetyCategory) {
      switch category {
      case .safeToDelete: self = .safe
      case .probablyUnused: self = .review
      case .deleteIfAppUnused: self = .appData
      case .doNotBulkDelete: self = .personal
      }
    }
  }

  public var kind: Kind
  public var bytes: Int64
  public var height: Double

  public init(kind: Kind, bytes: Int64, height: Double) {
    self.kind = kind
    self.bytes = bytes
    self.height = height
  }
}

/// The Sprout Lens beside the terrarium: parked by the dome, or out on its scanning orbit.
public enum TerrariumLensPose: Equatable, Sendable {
  case parked(bobbing: Bool)
  case scanning(orbiting: Bool)
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

  /// Where the Sprout Lens rests and whether it moves. It moves (bobs when parked, orbits while
  /// scanning) only while the view animates; under Reduce Motion or while paused it holds still.
  public static func lensPose(isScanning: Bool, animates: Bool) -> TerrariumLensPose {
    isScanning ? .scanning(orbiting: animates) : .parked(bobbing: animates)
  }

  /// The terrarium's single VoiceOver label, top layer first: "Storage terrarium: 5.94 GB safe to
  /// reclaim, 6.3 GB worth a closer look, 22.9 GB app data, 75 GB personal files, 48 GB macOS and
  /// apps."
  public static func accessibilityLabel(for layers: [TerrariumLayer]) -> String {
    func bytes(_ kind: TerrariumLayer.Kind) -> String {
      ByteCount.string(layers.first { $0.kind == kind }?.bytes ?? 0)
    }
    return "Storage terrarium: \(bytes(.safe)) safe to reclaim, "
      + "\(bytes(.review)) worth a closer look, \(bytes(.appData)) app data, "
      + "\(bytes(.personal)) personal files, \(bytes(.system)) macOS and apps."
  }

  private static func height(forBytes bytes: Int64) -> Double {
    let gigabytes = Double(max(bytes, 0)) / 1e9
    return (0.12 + gigabytes.squareRoot() * 0.06) * 0.55
  }
}
