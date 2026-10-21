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
}
