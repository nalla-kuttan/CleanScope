import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public actor DeletionService {
  public typealias FileMover = @Sendable (URL) async -> Bool
  public typealias DiskSnapshotProvider = @Sendable () -> Int64

  private let fileMover: FileMover
  private let diskSnapshot: DiskSnapshotProvider

  public init(
    fileMover: @escaping FileMover = { url in
      await DeletionService.defaultTrashMover(url)
    },
    diskSnapshot: @escaping DiskSnapshotProvider = { DeletionService.defaultDiskSnapshot() }
  ) {
    self.fileMover = fileMover
    self.diskSnapshot = diskSnapshot
  }

  public func cleanup(selected: [ScanResult]) async -> CleanupSession {
    let before = diskSnapshot()
    var deleted: [CleanupItemResult] = []
    var skipped: [CleanupItemResult] = []
    var blocked: [CleanupItemResult] = []
    var failed: [CleanupItemResult] = []

    for item in selected {
      if item.isProtected || item.deletionMethod == .notAllowed {
        blocked.append(
          CleanupItemResult(
            scanResultId: item.id,
            path: item.path,
            sizeBytes: item.sizeBytes,
            status: .blocked,
            message: "Protected by macOS or unavailable. Item was left in place."
          ))
        continue
      }

      guard item.canDelete, item.deletionMethod == .trash else {
        skipped.append(
          CleanupItemResult(
            scanResultId: item.id,
            path: item.path,
            sizeBytes: item.sizeBytes,
            status: .skipped,
            message: "Manual review required before deletion."
          ))
        continue
      }

      if await fileMover(URL(fileURLWithPath: item.normalizedPath)) {
        deleted.append(
          CleanupItemResult(
            scanResultId: item.id,
            path: item.path,
            sizeBytes: item.sizeBytes,
            status: .deleted,
            message: "Moved to Trash."
          ))
      } else {
        failed.append(
          CleanupItemResult(
            scanResultId: item.id,
            path: item.path,
            sizeBytes: item.sizeBytes,
            status: .failed,
            message: "Could not move item to Trash."
          ))
      }
    }

    return CleanupSession(
      completedAt: Date(),
      diskSpaceBeforeBytes: before,
      diskSpaceAfterBytes: diskSnapshot(),
      selectedItemIds: selected.map(\.id),
      deletedItems: deleted,
      skippedItems: skipped,
      blockedItems: blocked,
      failedItems: failed
    )
  }

  public static func defaultTrashMover(_ url: URL) async -> Bool {
    #if canImport(AppKit)
      do {
        _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        return true
      } catch {
        return false
      }
    #else
      return false
    #endif
  }

  public static func defaultDiskSnapshot() -> Int64 {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
      .flatMap(\.volumeAvailableCapacityForImportantUsage) ?? 0
  }
}
