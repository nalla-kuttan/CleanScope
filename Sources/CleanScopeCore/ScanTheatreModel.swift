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

  /// How many of the scan's streamed results have been counted, so `sync` takes each exactly once.
  public private(set) var absorbedCount = 0

  public init() {}

  /// Brings the counts up to date with the scan's full streamed list: counts the results past
  /// `absorbedCount` (however many batches arrived since the last call) and returns their particles.
  /// A list shorter than what was counted means a new scan began, so the counts start over.
  public mutating func sync(with results: [ScanResult]) -> [TheatreJar] {
    if results.count < absorbedCount { self = ScanTheatreModel() }
    guard results.count > absorbedCount else { return [] }
    return absorb(Array(results[absorbedCount...]))
  }

  /// Counts every result in the batch and returns the jars to fly particles to: one per result,
  /// the first `particleCap` of them.
  public mutating func absorb(_ batch: [ScanResult]) -> [TheatreJar] {
    var particles: [TheatreJar] = []
    absorbedCount += batch.count
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
