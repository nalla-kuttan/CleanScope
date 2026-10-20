import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct TrashServiceTests {
  @Test func trashSizeSumsAllocatedSizes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try Data(repeating: 1, count: 10_000).write(to: folder.appendingPathComponent("a"))
    try Data(repeating: 1, count: 20_000).write(to: folder.appendingPathComponent("nested/b"))
    let size = try TrashService.size(of: folder)
    #expect(size >= 30_000)
  }

  @Test func unreadableTrashNeedsFullDiskAccess() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }
    #expect(throws: TrashServiceError.needsFullDiskAccess) {
      try TrashService.size(of: folder)
    }
  }

  @Test func volumeEligibilityExcludesInternalAndNetwork() {
    #expect(VolumeService.isEligible(isInternal: false, isLocal: true, isRemovable: true))
    #expect(VolumeService.isEligible(isInternal: false, isLocal: true, isRemovable: false))
    #expect(!VolumeService.isEligible(isInternal: true, isLocal: true, isRemovable: false))
    #expect(!VolumeService.isEligible(isInternal: false, isLocal: false, isRemovable: false))
  }

  @Test func cleanupReportMentionsEmptyingTrash() {
    let deleted = CleanupItemResult(
      scanResultId: "1", path: "/a", sizeBytes: 2_000_000_000, status: .deleted,
      message: "Moved to Trash.")
    let session = CleanupSession(
      diskSpaceBeforeBytes: 1, selectedItemIds: ["1"], deletedItems: [deleted], skippedItems: [],
      blockedItems: [], failedItems: [])
    #expect(
      CleanupSummaryCopy.trashReminder(for: session)
        == "2 GB moved to Trash. Empty the Trash in Finder to free the space.")
  }
}
