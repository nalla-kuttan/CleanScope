import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public actor DeletionService {
  public typealias FileMover = @Sendable (URL) async -> Bool
  public typealias FileRemover = @Sendable (URL) async -> Bool
  public typealias DiskSnapshotProvider = @Sendable () -> Int64

  private let fileMover: FileMover
  private let fileRemover: FileRemover
  private let privileged: PrivilegedRunning?
  private let trashBinaryExists: Bool
  private let diskSnapshot: DiskSnapshotProvider

  public init(
    fileMover: @escaping FileMover = { url in
      await DeletionService.defaultTrashMover(url)
    },
    fileRemover: @escaping FileRemover = { url in
      await DeletionService.defaultRemover(url)
    },
    privileged: PrivilegedRunning? = nil,
    trashBinaryExists: Bool = FileManager.default.isExecutableFile(atPath: "/usr/bin/trash"),
    diskSnapshot: @escaping DiskSnapshotProvider = { DeletionService.defaultDiskSnapshot() }
  ) {
    self.fileMover = fileMover
    self.fileRemover = fileRemover
    self.privileged = privileged
    self.trashBinaryExists = trashBinaryExists
    self.diskSnapshot = diskSnapshot
  }

  /// Items are classified with `.trash`; the user's setting decides at cleanup time whether that
  /// means the Trash or permanent deletion, so saved sessions never change.
  public static func effectiveMethod(deleteImmediately: Bool) -> DeletionMethod {
    deleteImmediately ? .permanent : .trash
  }

  public func cleanup(selected: [ScanResult], method: DeletionMethod = .trash) async
    -> CleanupSession
  {
    let method: DeletionMethod = method == .permanent ? .permanent : .trash
    let before = diskSnapshot()
    var deleted: [CleanupItemResult] = []
    var skipped: [CleanupItemResult] = []
    var blocked: [CleanupItemResult] = []
    var failed: [CleanupItemResult] = []
    var adminItems: [ScanResult] = []

    func record(_ item: ScanResult, _ status: CleanupStatus, _ message: String) {
      let result = CleanupItemResult(
        scanResultId: item.id, path: item.path, sizeBytes: item.sizeBytes, status: status,
        message: message)
      switch status {
      case .deleted: deleted.append(result)
      case .skipped: skipped.append(result)
      case .blocked: blocked.append(result)
      case .failed: failed.append(result)
      }
    }

    for item in selected {
      if item.isProtected || item.deletionMethod == .notAllowed {
        record(item, .blocked, "Protected by macOS or unavailable. Item was left in place.")
        continue
      }

      guard item.canDelete, item.deletionMethod == .trash else {
        record(item, .skipped, "Manual review required before deletion.")
        continue
      }

      if item.requiresAdmin {
        adminItems.append(item)
        continue
      }

      // A grouped result removes its members, never its own path.
      let urls = (item.memberPaths ?? [item.normalizedPath]).map { URL(fileURLWithPath: $0) }
      var allRemoved = !urls.isEmpty
      for url in urls {
        let removed = method == .permanent ? await fileRemover(url) : await fileMover(url)
        allRemoved = allRemoved && removed
      }
      if allRemoved {
        record(item, .deleted, method == .permanent ? "Deleted permanently." : "Moved to Trash.")
      } else {
        record(
          item, .failed,
          method == .permanent ? "Could not delete item." : "Could not move item to Trash.")
      }
    }

    if !adminItems.isEmpty {
      for (item, status, message) in await removeWithAdministrator(adminItems, method: method) {
        record(item, status, message)
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

  /// Root-owned items go through one administrator prompt for the whole batch.
  private func removeWithAdministrator(_ items: [ScanResult], method: DeletionMethod) async
    -> [(ScanResult, CleanupStatus, String)]
  {
    if method == .trash && !trashBinaryExists {
      return items.map {
        (
          $0, .skipped,
          "Removed permanently (needs administrator). Turn on Delete immediately in Settings to remove it."
        )
      }
    }
    guard let privileged else {
      return items.map { ($0, .failed, "Needs an administrator to remove.") }
    }

    let paths = items.flatMap { $0.memberPaths ?? [$0.normalizedPath] }
    guard !paths.isEmpty else { return items.map { ($0, .skipped, "Nothing to remove.") } }
    let quoted = paths.map(ShellQuote.quote).joined(separator: " ")
    let command = method == .permanent ? "/bin/rm -rf \(quoted)" : "/usr/bin/trash \(quoted)"
    do {
      _ = try await privileged.run(command: command)
    } catch PrivilegedRunnerError.cancelled {
      return items.map { ($0, .skipped, "Administrator approval was cancelled.") }
    } catch {
      return items.map { ($0, .failed, "The administrator command failed.") }
    }

    let success = method == .permanent ? "Deleted permanently." : "Moved to Trash."
    return items.map { item in
      (item.memberPaths ?? [item.normalizedPath]).contains {
        FileManager.default.fileExists(atPath: $0)
      }
        ? (item, .failed, "The item is still in place.")
        : (item, .deleted, success)
    }
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

  public static func defaultRemover(_ url: URL) async -> Bool {
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch {
      return false
    }
  }

  public static func defaultDiskSnapshot() -> Int64 {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    return (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))
      .flatMap(\.volumeAvailableCapacityForImportantUsage) ?? 0
  }
}
