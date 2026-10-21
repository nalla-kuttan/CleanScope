import Foundation

/// The four jars of the scan theatre.
public enum TheatreJar: CaseIterable, Sendable {
  case safe, review, appData, keep

  public init(category: SafetyCategory) {
    switch category {
    case .safeToDelete: self = .safe
    case .probablyUnused: self = .review
    case .deleteIfAppUnused: self = .appData
    case .doNotBulkDelete: self = .keep
    }
  }
}

/// Running per-jar counts of a scan's streamed results. Counts are exact; only the particles
/// that decorate a batch are capped.
public struct ScanTheatreModel: Equatable, Sendable {
  /// Most particles a single batch spawns, however large it is.
  public static let particleCap = 40

  public private(set) var counts: [TheatreJar: Int] = Dictionary(
    uniqueKeysWithValues: TheatreJar.allCases.map { ($0, 0) })

  public init() {}

  /// Counts every result in the batch and returns the jars to fly particles to: one per result,
  /// the first `particleCap` of them.
  public mutating func absorb(_ batch: [ScanResult]) -> [TheatreJar] {
    var particles: [TheatreJar] = []
    for result in batch {
      let jar = TheatreJar(category: result.category)
      counts[jar, default: 0] += 1
      if particles.count < Self.particleCap { particles.append(jar) }
    }
    return particles
  }

  /// The jar's count relative to the fullest jar: 0 when every jar is empty.
  public func fill(_ jar: TheatreJar) -> Double {
    let most = counts.values.max() ?? 0
    guard most > 0 else { return 0 }
    return Double(counts[jar] ?? 0) / Double(most)
  }
}
