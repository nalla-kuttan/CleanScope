import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct ScanTheatreModelTests {
  private func batch(_ category: SafetyCategory, _ count: Int) -> [ScanResult] {
    (0..<count).map { ScanResult.fixture(path: "/\(category.rawValue)/\($0)", sizeBytes: 1, category: category) }
  }

  @Test func absorbCountsEveryResult() {
    var model = ScanTheatreModel()
    _ = model.absorb(batch(.safeToDelete, 100) + batch(.probablyUnused, 3))
    _ = model.absorb(batch(.deleteIfAppUnused, 2) + batch(.doNotBulkDelete, 1))
    #expect(model.counts[.safe] == 100)
    #expect(model.counts[.review] == 3)
    #expect(model.counts[.appData] == 2)
    #expect(model.counts[.keep] == 1)
  }

  @Test func particlesAreCappedAtForty() {
    var model = ScanTheatreModel()
    let particles = model.absorb(batch(.safeToDelete, 500))
    #expect(particles.count == 40)
    #expect(model.counts[.safe] == 500)
    #expect(model.absorb(batch(.safeToDelete, 5)).count == 5)
  }

  @Test func fillIsRelativeToLargestJar() {
    var model = ScanTheatreModel()
    _ = model.absorb(batch(.safeToDelete, 8) + batch(.probablyUnused, 2))
    #expect(model.fill(.safe) == 1)
    #expect(model.fill(.review) == 0.25)
    #expect(model.fill(.keep) == 0)
  }

  @Test func emptyModelFillsZero() {
    let model = ScanTheatreModel()
    for jar in TheatreJar.allCases { #expect(model.fill(jar) == 0) }
  }

  @Test func syncCountsEveryResultAppendedSinceLastSync() {
    var model = ScanTheatreModel()
    var results = batch(.safeToDelete, 3)
    _ = model.sync(with: results)
    // Two batches land before the next sync: both are counted, the first ones not twice.
    results += batch(.probablyUnused, 4)
    results += batch(.doNotBulkDelete, 2)
    let particles = model.sync(with: results)
    #expect(particles.count == 6)
    #expect(model.counts[.safe] == 3)
    #expect(model.counts[.review] == 4)
    #expect(model.counts[.keep] == 2)
    #expect(model.absorbedCount == 9)
  }

  @Test func syncWithUnchangedResultsDoesNothing() {
    var model = ScanTheatreModel()
    let results = batch(.safeToDelete, 5)
    _ = model.sync(with: results)
    #expect(model.sync(with: results).isEmpty)
    #expect(model.counts[.safe] == 5)
  }

  @Test func syncResetsWhenTheResultsShrink() {
    var model = ScanTheatreModel()
    _ = model.sync(with: batch(.safeToDelete, 10))
    _ = model.sync(with: batch(.probablyUnused, 2))
    #expect(model.counts[.safe] == 0)
    #expect(model.counts[.review] == 2)
    #expect(model.absorbedCount == 2)
  }
}
