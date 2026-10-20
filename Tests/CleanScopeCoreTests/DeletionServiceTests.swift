import Foundation
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

  @Test func permanentUsesRemoverNotMover() async {
    let item = ScanResult.fixture(
      path: "/Users/me/Library/Caches/App", sizeBytes: 100, category: .safeToDelete)
    let service = DeletionService(
      fileMover: { _ in
        Issue.record("Mover used for permanent deletion")
        return false
      },
      fileRemover: { _ in true },
      diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: [item], method: .permanent)

    #expect(session.deletedItems.count == 1)
    #expect(session.deletedItems.first?.message == "Deleted permanently.")
  }

  @Test func permanentStillSkipsManualReviewAndBlocksNotAllowed() async {
    let manual = ScanResult.fixture(
      path: "/Users/me/Documents", sizeBytes: 100, category: .doNotBulkDelete)
    var notAllowed = ScanResult.fixture(
      path: "/Users/me/Library/Caches/X", sizeBytes: 100, category: .safeToDelete)
    notAllowed.deletionMethod = .notAllowed
    notAllowed.canDelete = false
    let service = DeletionService(
      fileMover: { _ in true },
      fileRemover: { _ in
        Issue.record("Remover reached a blocked item")
        return true
      },
      diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: [manual, notAllowed], method: .permanent)

    #expect(session.skippedItems.map(\.path) == ["/Users/me/Documents"])
    #expect(session.blockedItems.map(\.path) == ["/Users/me/Library/Caches/X"])
    #expect(session.deletedItems.isEmpty)
  }

  @Test func effectiveMethodIsTrashUnlessDeleteImmediately() {
    #expect(DeletionService.effectiveMethod(deleteImmediately: false) == .trash)
    #expect(DeletionService.effectiveMethod(deleteImmediately: true) == .permanent)
  }

  @Test func adminItemsShareOnePrivilegedTrashCall() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var items: [ScanResult] = []
    for name in ["system.log.0.gz", "it's.log.1.gz"] {
      var item = ScanResult.fixture(
        path: directory.appendingPathComponent(name).path, sizeBytes: 10, category: .safeToDelete)
      item.requiresAdmin = true
      items.append(item)
    }
    let privileged = StubPrivilegedRunner()
    let service = DeletionService(
      fileMover: { _ in
        Issue.record("Admin item used the normal mover")
        return true
      },
      privileged: privileged,
      trashBinaryExists: true,
      diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: items, method: .trash)

    #expect(privileged.recorded.count == 1)
    let command = try #require(privileged.recorded.first)
    #expect(command.hasPrefix("/usr/bin/trash "))
    #expect(command.contains(ShellQuote.quote(items[1].normalizedPath)))
    #expect(session.deletedItems.count == 2)
  }

  @Test func adminItemsWithoutTrashBinaryNeedPermanentDelete() async {
    var item = ScanResult.fixture(
      path: "/private/var/log/system.log.0.gz", sizeBytes: 10, category: .safeToDelete)
    item.requiresAdmin = true
    let privileged = StubPrivilegedRunner()
    let service = DeletionService(
      fileMover: { _ in true }, privileged: privileged, trashBinaryExists: false,
      diskSnapshot: { 1_000 })

    let session = await service.cleanup(selected: [item], method: .trash)

    #expect(privileged.recorded.isEmpty)
    #expect(session.skippedItems.first?.message.contains("Removed permanently (needs administrator)") == true)
  }

  @Test func adminPermanentDeleteUsesRm() async {
    var item = ScanResult.fixture(
      path: "/private/var/log/old.log.2.gz", sizeBytes: 10, category: .safeToDelete)
    item.requiresAdmin = true
    let privileged = StubPrivilegedRunner()
    let service = DeletionService(
      fileMover: { _ in true }, privileged: privileged, trashBinaryExists: false,
      diskSnapshot: { 1_000 })

    _ = await service.cleanup(selected: [item], method: .permanent)

    #expect(privileged.recorded == ["/bin/rm -rf '\(item.normalizedPath)'"])
  }

  @Test func shellQuoteEscapesSingleQuotes() {
    #expect(ShellQuote.quote("/a/it's") == #"'/a/it'\''s'"#)
    #expect(ShellQuote.appleScriptLiteral(#"echo "hi" \ x"#) == #""echo \"hi\" \\ x""#)
  }

  @Test func preselectionPicksOnlyReadyCaches() {
    var cache = ScanResult.fixture(
      path: "/Users/me/Library/Caches/App", sizeBytes: 100, category: .safeToDelete)
    cache.confidence = .high
    var log = ScanResult.fixture(
      path: "/Users/me/Library/Logs/App", sizeBytes: 100, category: .safeToDelete)
    log.confidence = .high
    let download = ScanResult.fixture(
      path: "/Users/me/Downloads/old.zip", sizeBytes: 100, category: .probablyUnused)
    #expect(ResultPresentation.preselection(for: [cache, log, download]) == [cache.id])
  }

  @Test func shellQuoteRoundTripsThroughRealShell() async throws {
    let hostile = #"a b'c"d$(touch /tmp/cleanscope-pwned)`id`;\ \n*"#
    let output = try await ProcessRunner().run(
      "/bin/sh", ["-c", "printf %s " + ShellQuote.quote(hostile)], timeout: 5)
    #expect(output.stdout == hostile)
    #expect(!FileManager.default.fileExists(atPath: "/tmp/cleanscope-pwned"))
  }
}
