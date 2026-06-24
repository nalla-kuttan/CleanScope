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

  @Test func readyCacheIncludesOnlyHighConfidenceDeletableCacheData() {
    let included = [
      resultFixture(path: "/Users/me/Library/Caches/com.example.app"),
      resultFixture(path: "/Users/me/.npm/_cacache"),
      resultFixture(path: "/Users/me/.cache/pip/http"),
    ]

    for item in included {
      #expect(ResultPresentation.isReadyToDeleteCache(item), Comment(rawValue: item.path))
    }
  }

  @Test func readyCacheExcludesNonCacheOrUnavailableItems() {
    var protected = resultFixture(path: "/Users/me/Library/Caches/protected")
    protected.isProtected = true
    protected.canDelete = false

    var excluded = resultFixture(path: "/Users/me/Library/Caches/excluded")
    excluded.isExcluded = true
    excluded.canDelete = false

    let rejected = [
      resultFixture(path: "/Users/me/Library/Logs/app.log"),
      resultFixture(path: "/Users/me/.Trash/archive.zip"),
      resultFixture(path: "/Users/me/project/.next"),
      resultFixture(path: "/Users/me/Library/Caches/medium", confidence: .medium),
      protected,
      excluded,
    ]

    for item in rejected {
      #expect(!ResultPresentation.isReadyToDeleteCache(item), Comment(rawValue: item.path))
    }
  }

  @Test func visibleSelectionStateTracksNoneSomeAndAllEligibleRows() {
    let rows = [
      resultFixture(path: "/tmp/a"),
      resultFixture(path: "/tmp/b"),
      resultFixture(path: "/tmp/c", category: .doNotBulkDelete),
    ]

    #expect(ResultSelection.state(visible: rows, selectedIDs: []) == .none)
    #expect(ResultSelection.state(visible: rows, selectedIDs: [rows[0].id]) == .some)
    #expect(
      ResultSelection.state(visible: rows, selectedIDs: [rows[0].id, rows[1].id]) == .all)
  }

  @Test func rangeReturnsOnlyEligibleRowsInVisibleOrder() {
    let rows = [
      resultFixture(path: "/tmp/a"),
      resultFixture(path: "/tmp/b", category: .doNotBulkDelete),
      resultFixture(path: "/tmp/c"),
      resultFixture(path: "/tmp/d"),
    ]

    #expect(
      ResultSelection.eligibleIDs(in: rows, from: rows[0].id, through: rows[3].id)
        == [rows[0].id, rows[2].id, rows[3].id])
    #expect(ResultSelection.eligibleIDs(in: rows, from: "missing", through: rows[3].id).isEmpty)
  }

  @Test func updatingSelectionChangesOnlyEligibleSuppliedRows() {
    let a = resultFixture(path: "/tmp/a")
    let b = resultFixture(path: "/tmp/b")
    let blocked = resultFixture(path: "/tmp/blocked", category: .doNotBulkDelete)

    let selected = ResultSelection.updating(
      [],
      with: [a, blocked],
      isSelected: true
    )
    #expect(selected == [a.id])

    let deselected = ResultSelection.updating(
      [a.id, b.id],
      with: [a],
      isSelected: false
    )
    #expect(deselected == [b.id])
  }

  private func resultFixture(
    path: String,
    category: SafetyCategory = .safeToDelete,
    confidence: Confidence = .high
  ) -> ScanResult {
    var result = ScanResult.fixture(path: path, sizeBytes: 100, category: category)
    result.confidence = confidence
    return result
  }
}
