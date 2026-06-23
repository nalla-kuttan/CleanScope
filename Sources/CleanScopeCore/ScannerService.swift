import Foundation

private final class ScanCancellationState: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func reset() {
    lock.withLock {
      cancelled = false
    }
  }

  func cancel() {
    lock.withLock {
      cancelled = true
    }
  }

  var isCancelled: Bool {
    lock.withLock { cancelled }
  }
}

public struct DiskSnapshot: Equatable, Sendable {
  public var totalBytes: Int64
  public var availableBytes: Int64
  public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }

  public init(totalBytes: Int64, availableBytes: Int64) {
    self.totalBytes = totalBytes
    self.availableBytes = availableBytes
  }
}

public actor ScannerService {
  private let classifier: ClassificationService
  private let largeFileThresholdBytes: Int64
  private let cancellationState = ScanCancellationState()
  private var visitedRealPaths: Set<String> = []

  public init(
    classifier: ClassificationService,
    largeFileThresholdBytes: Int64 = Settings.default.largeFileThresholdBytes
  ) {
    self.classifier = classifier
    self.largeFileThresholdBytes = largeFileThresholdBytes
  }

  public nonisolated func cancel() {
    cancellationState.cancel()
  }

  public func scan(
    paths: [String],
    mode: ScanMode,
    settings: Settings,
    onResult: @Sendable (ScanResult) -> Void
  ) async -> ScanSession {
    cancellationState.reset()
    visitedRealPaths = []
    let disk = diskSnapshot(for: URL(fileURLWithPath: NSHomeDirectory()))
    var results: [ScanResult] = []
    var skipped: [SkippedPath] = []
    var scanned: [String] = []

    for path in paths where !cancellationState.isCancelled {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      scanned.append(url.path)
      guard FileManager.default.fileExists(atPath: url.path) else {
        skipped.append(
          SkippedPath(
            path: url.path,
            reason: .externalDriveUnavailable,
            message: "The scan location is not currently available."
          ))
        continue
      }
      await scanURL(
        url, settings: settings, results: &results, skipped: &skipped, onResult: onResult)
    }

    return ScanSession(
      completedAt: Date(),
      status: cancellationState.isCancelled ? .cancelled : .completed,
      scanMode: mode,
      diskTotalBytes: disk.totalBytes,
      diskUsedBytes: disk.usedBytes,
      diskAvailableBytes: disk.availableBytes,
      scannedPaths: scanned,
      skippedPaths: skipped,
      results: results
    )
  }

  @discardableResult
  private func scanURL(
    _ url: URL,
    settings: Settings,
    results: inout [ScanResult],
    skipped: inout [SkippedPath],
    onResult: @Sendable (ScanResult) -> Void
  ) async -> Int64 {
    guard !cancellationState.isCancelled else { return 0 }
    if url.lastPathComponent.hasPrefix("."), !settings.scanHiddenFolders {
      return 0
    }

    do {
      let keys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .isUserImmutableKey,
        .isSystemImmutableKey,
      ]
      let values = try url.resourceValues(forKeys: keys)

      guard FileManager.default.isReadableFile(atPath: url.path) else {
        skipped.append(
          SkippedPath(
            path: url.path,
            reason: .permissionDenied,
            message: "Permission required to scan this folder."
          ))
        return 0
      }

      if values.isSymbolicLink == true {
        skipped.append(
          SkippedPath(
            path: url.path,
            reason: .symlinkLoop,
            message: "Symlink was recorded but not followed to avoid recursive loops."
          ))
        return 0
      }

      let realPath = url.resolvingSymlinksInPath().path
      guard !visitedRealPaths.contains(realPath) else {
        skipped.append(
          SkippedPath(
            path: url.path,
            reason: .symlinkLoop,
            message: "Path resolves to a location already scanned."
          ))
        return 0
      }
      visitedRealPaths.insert(realPath)

      let isProtected = values.isUserImmutable == true || values.isSystemImmutable == true
      if values.isDirectory == true {
        let children = try FileManager.default.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: Array(keys),
          options: [.skipsPackageDescendants]
        )
        var folderBytes: Int64 = 0
        for child in children where !cancellationState.isCancelled {
          folderBytes += await scanURL(
            child,
            settings: settings,
            results: &results,
            skipped: &skipped,
            onResult: onResult
          )
        }
        if shouldEmitFolder(url: url, bytes: folderBytes, settings: settings) {
          let result = classifier.classify(
            ClassifiedItemInput(
              path: url.path,
              sizeBytes: folderBytes,
              itemType: .folder,
              lastModified: values.contentModificationDate,
              isProtected: isProtected
            ))
          results.append(result)
          onResult(result)
        }
        return folderBytes
      }

      let bytes = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
      if bytes >= largeFileThresholdBytes {
        let result = classifier.classify(
          ClassifiedItemInput(
            path: url.path,
            sizeBytes: bytes,
            itemType: .file,
            lastModified: values.contentModificationDate,
            isProtected: isProtected
          ))
        results.append(result)
        onResult(result)
      }
      return bytes
    } catch CocoaError.fileReadNoPermission {
      skipped.append(
        SkippedPath(
          path: url.path,
          reason: .permissionDenied,
          message: "Permission required to scan this folder."
        ))
    } catch {
      skipped.append(
        SkippedPath(
          path: url.path,
          reason: .unknownError,
          message: error.localizedDescription
        ))
    }
    return 0
  }

  private func shouldEmitFolder(url: URL, bytes: Int64, settings: Settings) -> Bool {
    let name = url.lastPathComponent
    if name.hasPrefix(".") && settings.scanHiddenFolders { return bytes > 0 }
    if url.path.localizedCaseInsensitiveContains("/Library/Caches") { return bytes > 0 }
    if bytes >= largeFileThresholdBytes { return true }
    return false
  }

  public nonisolated func diskSnapshot(for url: URL) -> DiskSnapshot {
    let values = try? url.resourceValues(forKeys: [
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey,
    ])
    return DiskSnapshot(
      totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
      availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0
    )
  }
}
