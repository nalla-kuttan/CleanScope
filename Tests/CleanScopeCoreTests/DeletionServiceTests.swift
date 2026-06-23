import Testing

@testable import CleanScopeCore

@Suite struct DeletionServiceTests {
  @Test func deletionSkipsManualReviewItems() async {
    let item = ScanResult.fixture(
      path: "/Users/me/Documents", sizeBytes: 100, category: .doNotBulkDelete)
    let service = DeletionService(fileMover: { _ in true }, diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: [item])

    #expect(session.deletedItems.isEmpty)
    #expect(session.skippedItems.count == 1)
    #expect(session.recoveredBytes == 0)
  }

  @Test func deletionReportsTrashSuccess() async {
    let item = ScanResult.fixture(
      path: "/Users/me/Library/Caches/App", sizeBytes: 100, category: .safeToDelete)
    let service = DeletionService(fileMover: { _ in true }, diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: [item])

    #expect(session.deletedItems.count == 1)
    #expect(session.recoveredBytes == 100)
  }

  @Test func reportServiceKeepsBlockedItemsVisible() {
    let blocked = CleanupItemResult(
      scanResultId: "1", path: "/System/file", sizeBytes: 10, status: .blocked,
      message: "Protected by macOS")
    let session = CleanupSession(
      diskSpaceBeforeBytes: 100, diskSpaceAfterBytes: 90, selectedItemIds: ["1"], deletedItems: [],
      skippedItems: [], blockedItems: [blocked], failedItems: [])

    let report = ReportService().report(from: session)

    #expect(report.contains("Protected by macOS"))
    #expect(report.contains("0 bytes"))
  }

  @Test func deletionBlocksProtectedItemsWithoutCallingMover() async {
    var item = ScanResult.fixture(
      path: "/Users/me/Library/Caches/Protected", sizeBytes: 100, category: .safeToDelete)
    item.isProtected = true
    let service = DeletionService(
      fileMover: { _ in
        Issue.record("Protected item reached the file mover")
        return true
      },
      diskSnapshot: { 1_000 }
    )

    let session = await service.cleanup(selected: [item])

    #expect(session.deletedItems.isEmpty)
    #expect(session.blockedItems.count == 1)
  }
}
