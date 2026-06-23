import Testing

@testable import CleanScopeCore

@Suite struct ModelsTests {
  @Test func defaultSettingsUseTrashAndConservativeHistory() {
    let settings = Settings.default
    #expect(settings.defaultDeletionMethod == .trash)
    #expect(settings.scanHiddenFolders)
    #expect(settings.scanDeveloperFolders)
    #expect(settings.largeFileThresholdBytes == 500_000_000)
  }

  @Test func scanSummaryCountsCleanableBytesWithoutRiskyItems() {
    let safe = ScanResult.fixture(
      path: "/Users/me/Library/Caches/App", sizeBytes: 100, category: .safeToDelete)
    let probably = ScanResult.fixture(
      path: "/Users/me/Downloads/old.dmg", sizeBytes: 75, category: .probablyUnused)
    let risky = ScanResult.fixture(
      path: "/Users/me/Documents", sizeBytes: 999, category: .doNotBulkDelete)

    let summary = ScanSummary(results: [safe, probably, risky])

    #expect(summary.totalResults == 3)
    #expect(summary.totalCleanableBytes == 175)
    #expect(summary.doNotBulkDeleteBytes == 999)
  }

  @Test func mostCautiousCategoryWins() {
    #expect(
      SafetyCategory.mostCautious([.safeToDelete, .probablyUnused, .doNotBulkDelete])
        == .doNotBulkDelete)
  }
}
