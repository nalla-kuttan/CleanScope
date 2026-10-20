import Foundation

public enum TrashServiceError: Error, Equatable {
  case needsFullDiskAccess
}

public enum TrashService {
  public static var userTrash: URL {
    URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
  }

  /// Total allocated size of everything in `folder`. Throws when macOS blocks reading it.
  public static func size(of folder: URL = userTrash) throws -> Int64 {
    do {
      _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    } catch CocoaError.fileReadNoPermission {
      throw TrashServiceError.needsFullDiskAccess
    } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == EPERM {
      throw TrashServiceError.needsFullDiskAccess
    }
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
        options: [],
        errorHandler: { _, _ in true })
    else { return 0 }
    var total: Int64 = 0
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
      total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }
    return total
  }

  /// The AppleScript CleanScope sends to Finder after its own confirmation.
  public static let emptyTrashScript = #"tell application "Finder" to empty trash"#
}

public enum CleanupSummaryCopy {
  /// The reminder shown after a cleanup that moved items to Trash, or nil when nothing moved.
  public static func trashReminder(for session: CleanupSession) -> String? {
    let moved = session.deletedItems
      .filter { $0.message.hasPrefix("Moved to Trash") }
      .reduce(Int64(0)) { $0 + $1.sizeBytes }
    guard moved > 0 else { return nil }
    return "\(ByteCount.string(moved)) moved to Trash. Empty the Trash in Finder to free the space."
  }
}

public enum VolumeService {
  public static func isEligible(isInternal: Bool, isLocal: Bool, isRemovable: Bool) -> Bool {
    !isInternal && isLocal
  }

  /// Mounted external and removable volumes. Internal and network volumes are left out.
  public static func externalVolumes() -> [VolumeStatus] {
    let keys: [URLResourceKey] = [
      .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsRemovableKey, .volumeUUIDStringKey,
      .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeLocalizedNameKey,
    ]
    let urls =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        isEligible(
          isInternal: values.volumeIsInternal ?? true,
          isLocal: values.volumeIsLocal ?? false,
          isRemovable: values.volumeIsRemovable ?? false)
      else { return nil }
      return VolumeStatus(
        uuid: values.volumeUUIDString ?? url.path,
        name: values.volumeLocalizedName ?? url.lastPathComponent,
        totalBytes: Int64(values.volumeTotalCapacity ?? 0),
        availableBytes: Int64(values.volumeAvailableCapacity ?? 0),
        url: url)
    }
  }
}
