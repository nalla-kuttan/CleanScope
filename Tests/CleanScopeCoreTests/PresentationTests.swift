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

  @Test func heroStatePriority() {
    // Scanning beats cleaned beats results beats idle.
    #expect(
      StoragePresentation.heroState(hasScanned: true, isScanning: true, cleanedThisSession: true)
        == .scanning)
    #expect(
      StoragePresentation.heroState(hasScanned: false, isScanning: true, cleanedThisSession: false)
        == .scanning)
    #expect(
      StoragePresentation.heroState(hasScanned: true, isScanning: false, cleanedThisSession: true)
        == .cleaned)
    #expect(
      StoragePresentation.heroState(hasScanned: true, isScanning: false, cleanedThisSession: false)
        == .results)
    #expect(
      StoragePresentation.heroState(hasScanned: false, isScanning: false, cleanedThisSession: false)
        == .idle)
  }

  @Test func heroSproutStagesFollowTheState() {
    #expect(HeroState.idle.sproutStage == 0)
    #expect(HeroState.scanning.sproutStage == 1)
    #expect(HeroState.results.sproutStage == 2)
    #expect(HeroState.cleaned.sproutStage == 3)
  }

  @Test func remainingResultsDropTrashedItemsAndWhatSatInsideThem() {
    let folder = resultFixture(path: "/Users/me/Library/Caches/big")
    let nested = resultFixture(path: "/Users/me/Library/Caches/big/inner")
    let kept = resultFixture(path: "/Users/me/Library/Caches/kept")
    let all = [folder, nested, kept]

    let remaining = ResultPresentation.remaining(all, excluding: [folder.id])
    #expect(remaining.map(\.id) == [kept.id])
    #expect(ResultPresentation.remaining(all, excluding: []).count == 3)
  }

  @Test func summaryAfterCleanupLeavesOutTrashedBytes() {
    let trashed = ScanResult.fixture(path: "/tmp/a", sizeBytes: 600, category: .safeToDelete)
    let kept = ScanResult.fixture(path: "/tmp/b", sizeBytes: 400, category: .safeToDelete)
    let review = ScanResult.fixture(path: "/tmp/c", sizeBytes: 50, category: .probablyUnused)

    let summary = ScanSummary(
      results: ResultPresentation.remaining([trashed, kept, review], excluding: [trashed.id]))

    #expect(summary.safeToDeleteBytes == 400)
    #expect(summary.probablyUnusedBytes == 50)
    #expect(summary.totalResults == 2)
  }

  @Test func cleanupPlanTouchesOnlyReviewedItems() async {
    let reviewed = [resultFixture(path: "/tmp/quick-a"), resultFixture(path: "/tmp/quick-b")]
    let selectedElsewhere = (0..<50).map { resultFixture(path: "/tmp/elsewhere-\($0)") }
    let current = reviewed + selectedElsewhere
    let selection = Set(selectedElsewhere.map(\.id))

    let plan = ResultSelection.cleanupPlan(
      reviewed: reviewed, current: current, selection: selection)

    #expect(plan.items.map(\.id) == reviewed.map(\.id))
    #expect(plan.remainingSelection == selection)

    let trashed = TrashedPaths()
    let service = DeletionService(
      fileMover: { url in
        await trashed.append(url.path)
        return true
      },
      diskSnapshot: { 1_000 })
    let session = await service.cleanup(selected: plan.items)

    let trashedPaths = await trashed.paths
    #expect(Set(trashedPaths) == Set(reviewed.map(\.normalizedPath)))
    #expect(session.deletedItems.count == reviewed.count)
  }

  @Test func cleanupPlanRevalidatesReviewedItemsAgainstCurrentResults() {
    let kept = resultFixture(path: "/tmp/kept")
    var excludedSinceReview = resultFixture(path: "/tmp/excluded")
    let missing = resultFixture(path: "/tmp/missing")
    let reviewed = [kept, excludedSinceReview, missing]
    excludedSinceReview.isExcluded = true
    excludedSinceReview.canDelete = false

    let plan = ResultSelection.cleanupPlan(
      reviewed: reviewed,
      current: [kept, excludedSinceReview],
      selection: [kept.id, missing.id]
    )

    #expect(plan.items.map(\.id) == [kept.id])
    #expect(plan.remainingSelection == [missing.id])
  }

  @Test func cleanupPlanOverRemainingResultsNeverIncludesTrashedItems() {
    let trashedFolder = resultFixture(path: "/Users/me/Library/Caches/big")
    let nested = resultFixture(path: "/Users/me/Library/Caches/big/inner")
    let trashedFile = resultFixture(path: "/Users/me/Library/Caches/old")
    let kept = resultFixture(path: "/Users/me/Library/Caches/kept")
    let all = [trashedFolder, nested, trashedFile, kept]
    let trashed: Set<String> = [trashedFolder.id, trashedFile.id]
    let gone = trashed.union([nested.id])
    let current = ResultPresentation.remaining(all, excluding: trashed)

    // A stale review (or a lingering selection) that still names the trashed items.
    let plan = ResultSelection.cleanupPlan(
      reviewed: all, current: current, selection: Set(all.map(\.id)))

    #expect(plan.items.map(\.id) == [kept.id])
    #expect(Set(plan.items.map(\.id)).isDisjoint(with: gone))
    // Preselection over the same remaining results never re-selects what already left.
    #expect(ResultPresentation.preselection(for: current) == [kept.id])
    #expect(ResultPresentation.preselection(for: current).isDisjoint(with: gone))
  }

  @Test func cleanedCopyFollowsHowItemsLeft() {
    #expect(StoragePresentation.cleanedHeadline(method: .trash) == "Moved safely to Trash.")
    #expect(StoragePresentation.cleanedHeadline(method: .permanent) == "Deleted permanently.")
    #expect(!StoragePresentation.cleanedHeadline(method: .permanent).contains("Trash"))
    #expect(StoragePresentation.quickWinsSubtitle(deleteImmediately: false).contains("Trash"))
    #expect(!StoragePresentation.quickWinsSubtitle(deleteImmediately: true).contains("Trash"))
    #expect(
      StoragePresentation.quickWinsSubtitle(deleteImmediately: true).contains("permanently"))
    #expect(StoragePresentation.nothingRemovableNote(deleteImmediately: false).contains("Trash"))
    #expect(!StoragePresentation.nothingRemovableNote(deleteImmediately: true).contains("Trash"))
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

private actor TrashedPaths {
  private(set) var paths: [String] = []

  func append(_ path: String) {
    paths.append(path)
  }

  @Test func countPhraseInflectsSingularAndPlural() {
    #expect(CountPhrase.make(0, "item") == "0 items")
    #expect(CountPhrase.make(1, "item") == "1 item")
    #expect(CountPhrase.make(2_709, "item") == "2,709 items")
    #expect(CountPhrase.make(3, "category", plural: "categories") == "3 categories")
  }

  @Test func headlineFollowsScanState() {
    #expect(
      StoragePresentation.headline(hasScanned: false, isScanning: false, safeBytes: 0)
        == "Let’s see where your space went.")
    #expect(
      StoragePresentation.headline(hasScanned: false, isScanning: true, safeBytes: 0)
        == "Looking for room to grow…")
    #expect(
      StoragePresentation.headline(hasScanned: true, isScanning: false, safeBytes: 0)
        == "Your Mac is already breathing easy.")
    #expect(
      StoragePresentation.headline(hasScanned: true, isScanning: false, safeBytes: 6_210_000_000)
        .hasPrefix("You found "))
  }

  @Test func reviewLineCountsItemsNeedingAttention() {
    #expect(StoragePresentation.reviewLine(count: 0) == nil)
    #expect(StoragePresentation.reviewLine(count: 1) == "1 item deserves a closer look.")
    #expect(StoragePresentation.reviewLine(count: 3) == "3 items deserve a closer look.")
  }

  @Test func outermostDropsResultsNestedInsideOtherResults() {
    let parent = ScanResult.fixture(path: "/u/Library/Caches/Brave", sizeBytes: 100, category: .safeToDelete)
    let child = ScanResult.fixture(path: "/u/Library/Caches/Brave/Default", sizeBytes: 90, category: .safeToDelete)
    let sibling = ScanResult.fixture(path: "/u/Library/Caches/BraveOther", sizeBytes: 5, category: .safeToDelete)

    let kept = ResultPresentation.outermost([child, parent, sibling])

    #expect(kept.map(\ScanResult.path) == [parent.path, sibling.path])
    #expect(ResultPresentation.totalBytes([child, parent, sibling]) == 105)
  }

  @Test func summariesDoNotDoubleCountNestedFolders() {
    let parent = ScanResult.fixture(path: "/u/Library/Caches/Brave", sizeBytes: 100, category: .safeToDelete)
    let child = ScanResult.fixture(path: "/u/Library/Caches/Brave/Default", sizeBytes: 90, category: .safeToDelete)

    #expect(ScanSummary(results: [parent, child]).safeToDeleteBytes == 100)
    #expect(SelectionSummary(items: [parent, child]).totalBytes == 100)
    #expect(SelectionSummary(items: [parent, child]).itemCount == 2)
  }

  @Test func cleanupPlanTrashesOnlyOutermostAndDeselectsDescendants() {
    let parent = ScanResult.fixture(path: "/u/Library/Caches/Brave", sizeBytes: 100, category: .safeToDelete)
    let child = ScanResult.fixture(path: "/u/Library/Caches/Brave/Default", sizeBytes: 90, category: .safeToDelete)
    let other = ScanResult.fixture(path: "/u/Library/Caches/Other", sizeBytes: 1, category: .safeToDelete)

    let plan = ResultSelection.cleanupPlan(
      reviewed: [parent], current: [parent, child, other],
      selection: [parent.id, child.id, other.id])

    #expect(plan.items == [parent])
    #expect(plan.remainingSelection == [other.id])
  }

  @Test func singleSelectionPlaysOneFlight() {
    let item = ScanResult.fixture(path: "/u/Library/Caches/Brave", sizeBytes: 100, category: .safeToDelete)

    #expect(BasketPresentation.flights(newlySelected: [item]) == [item])
  }

  @Test func bulkSelectionPlaysOneFlight() {
    let items = (0..<2_709).map {
      ScanResult.fixture(path: "/u/Library/Caches/Item\($0)", sizeBytes: 1, category: .safeToDelete)
    }

    let flights = BasketPresentation.flights(newlySelected: items)

    #expect(flights.count == 1)
    #expect(flights.first == items.first)
  }

  @Test func deselectionPlaysNoFlight() {
    #expect(BasketPresentation.flights(newlySelected: []).isEmpty)
  }

  @Test func selectedOutsideCountsOnlyItemsNotInTheVisibleSection() {
    let here = ScanResult.fixture(path: "/u/Library/Caches/A", sizeBytes: 1, category: .safeToDelete)
    let alsoHere = ScanResult.fixture(path: "/u/Library/Caches/B", sizeBytes: 1, category: .safeToDelete)
    let elsewhere = ScanResult.fixture(path: "/u/Downloads/C", sizeBytes: 1, category: .safeToDelete)
    let other = ScanResult.fixture(path: "/u/Downloads/D", sizeBytes: 1, category: .safeToDelete)

    let outside = BasketPresentation.selectedOutside(
      selected: [here, elsewhere, other], visibleIDs: [here.id, alsoHere.id])

    #expect(outside == 2)
    #expect(BasketPresentation.selectedOutside(selected: [here], visibleIDs: [here.id]) == 0)
    #expect(BasketPresentation.selectedOutside(selected: [], visibleIDs: [here.id]) == 0)
  }

  @Test func otherSectionsPhraseHidesAtZero() {
    #expect(BasketPresentation.otherSectionsPhrase(0) == nil)
    #expect(BasketPresentation.otherSectionsPhrase(1) == "1 selected in other sections")
    #expect(BasketPresentation.otherSectionsPhrase(211) == "211 selected in other sections")
  }

  @Test func chipLabelNamesTheItemAndCountsTheRest() {
    let item = ScanResult.fixture(path: "/u/Library/Caches/Brave", sizeBytes: 100, category: .safeToDelete)

    #expect(BasketPresentation.chipLabel(for: item, totalNewlySelected: 1) == "Brave")
    #expect(BasketPresentation.chipLabel(for: item, totalNewlySelected: 2_709) == "Brave +2,708")
  }
}
