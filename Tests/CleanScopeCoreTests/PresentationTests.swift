import Testing

@testable import CleanScopeCore

@Suite struct PresentationTests {
  @Test func reclaimCopyScalesWithRecoveredSpace() {
    #expect(StoragePresentation.reclaimCopy(bytes: 0) == "Your Mac is already breathing easy.")
    #expect(StoragePresentation.reclaimCopy(bytes: 700_000_000).contains("side project"))
    #expect(StoragePresentation.reclaimCopy(bytes: 7_000_000_000).contains("photos"))
  }

  @Test func selectionSummaryCountsBytesAndCategories() {
    let items = [
      ScanResult.fixture(path: "/tmp/a", sizeBytes: 100, category: .safeToDelete),
      ScanResult.fixture(path: "/tmp/b", sizeBytes: 50, category: .probablyUnused),
    ]

    let summary = SelectionSummary(items: items)

    #expect(summary.itemCount == 2)
    #expect(summary.totalBytes == 150)
    #expect(summary.categoryCounts[.safeToDelete] == 1)
    #expect(summary.categoryCounts[.probablyUnused] == 1)
  }

  @Test func growthStageIsBounded() {
    #expect(StoragePresentation.growthStage(resultCount: 0, isScanning: false) == 0)
    #expect(StoragePresentation.growthStage(resultCount: 1, isScanning: true) == 1)
    #expect(StoragePresentation.growthStage(resultCount: 10, isScanning: true) == 2)
    #expect(StoragePresentation.growthStage(resultCount: 50, isScanning: true) == 3)
    #expect(StoragePresentation.growthStage(resultCount: 500, isScanning: false) == 3)
  }
}
