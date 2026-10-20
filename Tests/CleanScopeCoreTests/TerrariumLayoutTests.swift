import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct TerrariumLayoutTests {
  private func summary(
    safe: Int64 = 0, review: Int64 = 0, appData: Int64 = 0, personal: Int64 = 0
  ) -> ScanSummary {
    var summary = ScanSummary()
    summary.safeToDeleteBytes = safe
    summary.probablyUnusedBytes = review
    summary.deleteIfAppUnusedBytes = appData
    summary.doNotBulkDeleteBytes = personal
    return summary
  }

  @Test func layersAreOrderedBottomToTop() {
    let layers = TerrariumLayout.layerHeights(
      for: summary(safe: 1, review: 2, appData: 3, personal: 4), diskUsedBytes: 100)
    #expect(layers.map(\.kind) == [.system, .personal, .appData, .review, .safe])
  }

  @Test func layersMapCategoriesToBytes() {
    let layers = TerrariumLayout.layerHeights(
      for: summary(safe: 1, review: 2, appData: 3, personal: 4), diskUsedBytes: 100)
    #expect(layers.map(\.bytes) == [90, 4, 3, 2, 1])
  }

  @Test func heightsGrowWithBytes() {
    let small = TerrariumLayout.layerHeights(
      for: summary(safe: 4_000_000_000), diskUsedBytes: 50_000_000_000)
    let large = TerrariumLayout.layerHeights(
      for: summary(safe: 8_000_000_000), diskUsedBytes: 54_000_000_000)
    let smallSafe = small.first { $0.kind == .safe }!
    let largeSafe = large.first { $0.kind == .safe }!
    #expect(largeSafe.height > smallSafe.height)
    for (lhs, rhs) in zip(small, large) {
      #expect(rhs.height >= lhs.height - 1e-12)
    }
  }

  @Test func zeroBytesGivesMinimumHeights() {
    let layers = TerrariumLayout.layerHeights(for: ScanSummary(), diskUsedBytes: 0)
    #expect(layers.count == 5)
    for layer in layers {
      #expect(!layer.height.isNaN)
      #expect(abs(layer.height - 0.066) < 1e-9)
    }
  }

  @Test func systemLayerNeverNegative() {
    let layers = TerrariumLayout.layerHeights(
      for: summary(safe: 40, review: 30, appData: 20, personal: 10), diskUsedBytes: 50)
    let system = layers.first { $0.kind == .system }!
    #expect(system.bytes == 0)
    #expect(abs(system.height - 0.066) < 1e-9)
  }

  @Test func growthStageBounds() {
    #expect(TerrariumLayout.growthStage(cleanupsInLast30Days: 0) == 1)
    #expect(TerrariumLayout.growthStage(cleanupsInLast30Days: 1) == 2)
    #expect(TerrariumLayout.growthStage(cleanupsInLast30Days: 3) == 3)
    #expect(TerrariumLayout.growthStage(cleanupsInLast30Days: 99) == 3)
  }
}
