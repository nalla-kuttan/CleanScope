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

/// Real paths already visited during one scan, shared by every work item.
private final class VisitedPaths: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: Set<String> = []

  /// Inserts `path` and returns true when it was not visited before.
  func insertIfAbsent(_ path: String) -> Bool {
    lock.withLock { paths.insert(path).inserted }
  }
}

/// Extra cleanup applied when the scan root is an external drive.
public struct VolumeCleanupOptions: Equatable, Sendable {
  /// Lists every `.DS_Store` file as one grouped result.
  public var groupsDSStore: Bool
  /// Lists every `._*` AppleDouble file as one grouped result (FAT, exFAT and NTFS drives).
  public var groupsAppleDouble: Bool

  public init(groupsDSStore: Bool, groupsAppleDouble: Bool) {
    self.groupsDSStore = groupsDSStore
    self.groupsAppleDouble = groupsAppleDouble
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
  private let maxConcurrency: Int
  private let treeDepth: Int
  private let volumeOptions: @Sendable (URL) -> VolumeCleanupOptions?
  private let cancellationState = ScanCancellationState()

  public init(
    classifier: ClassificationService,
    largeFileThresholdBytes: Int64 = Settings.default.largeFileThresholdBytes,
    maxConcurrency: Int = min(ProcessInfo.processInfo.activeProcessorCount, 6),
    treeDepth: Int = 6,
    volumeOptions: @escaping @Sendable (URL) -> VolumeCleanupOptions? = ScannerService
      .externalVolumeOptions
  ) {
    self.classifier = classifier
    self.largeFileThresholdBytes = largeFileThresholdBytes
    self.maxConcurrency = max(1, maxConcurrency)
    self.treeDepth = treeDepth
    self.volumeOptions = volumeOptions
  }

  /// Drive cleanup applies to roots under `/Volumes`. AppleDouble files are only listed on
  /// FAT, exFAT and NTFS drives, where they are copies of Mac metadata.
  public static let externalVolumeOptions: @Sendable (URL) -> VolumeCleanupOptions? = { url in
    guard url.path.hasPrefix("/Volumes/") else { return nil }
    let format =
      (try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]))?
      .volumeLocalizedFormatDescription?.lowercased() ?? ""
    let isForeign = format.contains("fat") || format.contains("ntfs")
    return VolumeCleanupOptions(groupsDSStore: true, groupsAppleDouble: isForeign)
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
    let disk = diskSnapshot(for: URL(fileURLWithPath: NSHomeDirectory()))
    let roots = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }

    let outcome = await withoutActuallyEscaping(onResult) { emit in
      await scanRoots(roots, settings: settings, onResult: emit)
    }

    var session = ScanSession(
      completedAt: Date(),
      status: cancellationState.isCancelled ? .cancelled : .completed,
      scanMode: mode,
      diskTotalBytes: disk.totalBytes,
      diskUsedBytes: disk.usedBytes,
      diskAvailableBytes: disk.availableBytes,
      scannedPaths: roots.map(\.path),
      skippedPaths: outcome.skipped,
      results: outcome.results
    )
    session.tree = outcome.tree
    return session
  }

  private struct Outcome {
    var results: [ScanResult] = []
    var skipped: [SkippedPath] = []
    var tree: ScanNode?
  }

  private struct WorkItem: Sendable {
    var rootIndex: Int
    var childIndex: Int
    var url: URL
    var root: TreeWalker.RootContext
  }

  private func scanRoots(
    _ roots: [URL],
    settings: Settings,
    onResult: @escaping @Sendable (ScanResult) -> Void
  ) async -> Outcome {
    let walker = TreeWalker(
      classifier: classifier,
      largeFileThresholdBytes: largeFileThresholdBytes,
      treeDepth: treeDepth,
      settings: settings,
      cancellation: cancellationState,
      visited: VisitedPaths(),
      onResult: onResult
    )
    var outcome = Outcome()
    var openFolders: [Int: TreeWalker.OpenFolder] = [:]
    var rootVisits: [Int: TreeWalker.Visit] = [:]
    var items: [WorkItem] = []
    var rootContexts: [Int: TreeWalker.RootContext] = [:]

    for (index, url) in roots.enumerated() where !cancellationState.isCancelled {
      guard FileManager.default.fileExists(atPath: url.path) else {
        outcome.skipped.append(
          SkippedPath(
            path: url.path,
            reason: .externalDriveUnavailable,
            message: "The scan location is not currently available."
          ))
        continue
      }
      let coveredByOtherRoot = roots.enumerated().contains { otherIndex, other in
        otherIndex != index
          && (url.path.hasPrefix(other.path + "/") || (url.path == other.path && otherIndex < index))
      }
      if coveredByOtherRoot {
        outcome.skipped.append(
          SkippedPath(
            path: url.path,
            reason: .symlinkLoop,
            message: "Path resolves to a location already scanned."
          ))
        continue
      }

      // A root inside a guarded system path (for example an external drive) is scanned as asked.
      let root = TreeWalker.RootContext(
        guarded: !SystemPathGuard.shouldSkip(url.path), volume: volumeOptions(url))
      rootContexts[index] = root
      switch walker.begin(url, depth: 0, root: root) {
      case .done(let visit):
        rootVisits[index] = visit
      case .folder(let folder):
        openFolders[index] = folder
        for (childIndex, child) in folder.children.enumerated() {
          items.append(
            WorkItem(rootIndex: index, childIndex: childIndex, url: child, root: root))
        }
      }
    }

    var childVisits: [Int: [Int: TreeWalker.Visit]] = [:]
    await withTaskGroup(of: (Int, Int, TreeWalker.Visit).self) { group in
      var pending = items.makeIterator()
      for _ in 0..<maxConcurrency {
        guard let item = pending.next() else { break }
        group.addTask {
          (item.rootIndex, item.childIndex, walker.visit(item.url, depth: 1, root: item.root))
        }
      }
      while let (rootIndex, childIndex, visit) = await group.next() {
        childVisits[rootIndex, default: [:]][childIndex] = visit
        if let item = pending.next() {
          group.addTask {
            (item.rootIndex, item.childIndex, walker.visit(item.url, depth: 1, root: item.root))
          }
        }
      }
    }

    for (index, folder) in openFolders {
      let visits = (0..<folder.children.count).compactMap { childVisits[index]?[$0] }
      rootVisits[index] = walker.finish(folder, childVisits: visits)
    }

    var rootNodes: [ScanNode] = []
    for index in roots.indices {
      guard var visit = rootVisits[index] else { continue }
      for group in walker.groupedResults(root: roots[index], members: visit.grouped) {
        visit.results.append(group)
        onResult(group)
      }
      outcome.results += visit.results
      outcome.skipped += visit.skipped
      if let node = visit.node { rootNodes.append(node) }
    }
    if !rootNodes.isEmpty {
      outcome.tree = ScanNode(
        path: "scan://locations",
        name: "Scanned locations",
        sizeBytes: rootNodes.reduce(0) { $0 + $1.sizeBytes },
        itemType: .folder,
        children: rootNodes
      )
    }
    return outcome
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

/// Walks one subtree synchronously. Work items run walkers in parallel; all shared state is
/// lock-protected or immutable.
private struct TreeWalker: Sendable {
  struct RootContext: Sendable {
    /// False when the root itself is inside a guarded system path, such as a drive in /Volumes.
    var guarded: Bool
    var volume: VolumeCleanupOptions?
  }

  struct Member: Sendable {
    var path: String
    var bytes: Int64
  }

  struct Visit: Sendable {
    var bytes: Int64 = 0
    var results: [ScanResult] = []
    var skipped: [SkippedPath] = []
    var node: ScanNode?
    /// Small files collected into one result per root, keyed by rule id.
    var grouped: [String: [Member]] = [:]
  }

  struct OpenFolder: Sendable {
    var url: URL
    var depth: Int
    var lastModified: Date?
    var isProtected: Bool
    var children: [URL]
    var preliminary: Visit
  }

  enum Entry: Sendable {
    case done(Visit)
    case folder(OpenFolder)
  }

  /// Rules whose folders are listed even when they sit outside a Caches folder.
  static let emittedFolderRules: Set<String> = [
    "safe.chromium-caches", "safe.spotify-cache", "safe.adobe-media-cache",
    "review.telegram-media", "safe.diagnostic-reports", "safe.container-caches",
  ]
  private static let emittedFolderNames: Set<String> = Set(
    ClassificationService.chromiumCacheNames + [
      "storage", "media cache files", "user_data", "diagnosticreports", "caches",
    ])

  static let resourceKeys: Set<URLResourceKey> = [
    .isDirectoryKey,
    .isSymbolicLinkKey,
    .fileSizeKey,
    .totalFileAllocatedSizeKey,
    .contentModificationDateKey,
    .isUserImmutableKey,
    .isSystemImmutableKey,
  ]

  let classifier: ClassificationService
  let largeFileThresholdBytes: Int64
  let treeDepth: Int
  let settings: Settings
  let cancellation: ScanCancellationState
  let visited: VisitedPaths
  let onResult: @Sendable (ScanResult) -> Void

  fileprivate init(
    classifier: ClassificationService,
    largeFileThresholdBytes: Int64,
    treeDepth: Int,
    settings: Settings,
    cancellation: ScanCancellationState,
    visited: VisitedPaths,
    onResult: @escaping @Sendable (ScanResult) -> Void
  ) {
    self.classifier = classifier
    self.largeFileThresholdBytes = largeFileThresholdBytes
    self.treeDepth = treeDepth
    self.settings = settings
    self.cancellation = cancellation
    self.visited = visited
    self.onResult = onResult
  }

  func visit(_ url: URL, depth: Int, root: RootContext) -> Visit {
    switch begin(url, depth: depth, root: root) {
    case .done(let visit):
      return visit
    case .folder(let folder):
      var childVisits: [Visit] = []
      childVisits.reserveCapacity(folder.children.count)
      for child in folder.children where !cancellation.isCancelled {
        childVisits.append(visit(child, depth: depth + 1, root: root))
      }
      return finish(folder, childVisits: childVisits)
    }
  }

  /// Checks one item. Files finish here; folders return their children for the caller to visit.
  func begin(_ url: URL, depth: Int, root: RootContext) -> Entry {
    var visit = Visit()
    guard !cancellation.isCancelled else { return .done(visit) }
    if url.lastPathComponent.hasPrefix("."), !settings.scanHiddenFolders {
      return .done(visit)
    }
    if root.guarded, depth > 0, SystemPathGuard.shouldSkip(url.path) {
      return .done(visit)
    }

    do {
      let values = try url.resourceValues(forKeys: Self.resourceKeys)

      if values.isSymbolicLink == true {
        visit.skipped.append(
          SkippedPath(
            path: url.path,
            reason: .symlinkLoop,
            message: "Symlink was recorded but not followed to avoid recursive loops."
          ))
        return .done(visit)
      }

      guard FileManager.default.isReadableFile(atPath: url.path) else {
        visit.skipped.append(permissionSkip(url))
        return .done(visit)
      }

      let realPath = SystemPathGuard.canonical(url.resolvingSymlinksInPath().path)
      guard visited.insertIfAbsent(realPath) else {
        visit.skipped.append(
          SkippedPath(
            path: url.path,
            reason: .symlinkLoop,
            message: "Path resolves to a location already scanned."
          ))
        return .done(visit)
      }

      let flags = FileFlags.read(path: url.path) ?? FileFlags(rawFlags: 0)
      let isProtected =
        values.isUserImmutable == true || values.isSystemImmutable == true || flags.isRestricted

      if values.isDirectory == true {
        // Listing a cloud-only folder would download it, so it is left alone.
        if flags.isDataless { return .done(visit) }
        let children = try FileManager.default.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: Array(Self.resourceKeys),
          options: [.skipsPackageDescendants]
        )
        if root.volume?.groupsAppleDouble == true {
          for file in PosixDirectory.appleDoubleFiles(in: url.path) {
            visit.grouped["safe.appledouble", default: []].append(
              Member(path: file.path, bytes: file.bytes))
            visit.bytes += file.bytes
          }
        }
        return .folder(
          OpenFolder(
            url: url, depth: depth, lastModified: values.contentModificationDate,
            isProtected: isProtected, children: children, preliminary: visit))
      }

      let logicalBytes = Int64(values.fileSize ?? 0)
      let bytes =
        flags.isDataless ? 0 : Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
      var resultId: String?
      if let group = groupRule(for: url.lastPathComponent, root: root) {
        visit.grouped[group, default: []].append(Member(path: url.path, bytes: bytes))
      } else if shouldEmitFile(url: url, bytes: flags.isDataless ? logicalBytes : bytes) {
        let result = classifier.classify(
          ClassifiedItemInput(
            path: url.path,
            sizeBytes: bytes,
            itemType: .file,
            lastModified: values.contentModificationDate,
            isProtected: isProtected,
            isCloudOnly: flags.isDataless,
            cloudOnlyBytes: flags.isDataless ? logicalBytes : 0,
            requiresAdmin: parentIsReadOnly(url)
          ))
        resultId = result.id
        visit.results.append(result)
        onResult(result)
      }
      visit.bytes = bytes
      visit.node = ScanNode(
        path: url.path, name: url.lastPathComponent, sizeBytes: bytes, itemType: .file,
        resultId: resultId, lastModified: values.contentModificationDate)
      return .done(visit)
    } catch CocoaError.fileReadNoPermission {
      visit.skipped.append(permissionSkip(url))
    } catch {
      visit.skipped.append(
        SkippedPath(
          path: url.path,
          reason: .unknownError,
          message: error.localizedDescription
        ))
    }
    return .done(visit)
  }

  /// Sums a folder's children, emits the folder when it is worth listing, and prunes the tree.
  func finish(_ folder: OpenFolder, childVisits: [Visit]) -> Visit {
    var visit = folder.preliminary
    var childNodes: [ScanNode] = []
    for child in childVisits {
      visit.bytes += child.bytes
      visit.results += child.results
      visit.skipped += child.skipped
      visit.grouped.merge(child.grouped) { $0 + $1 }
      if let node = child.node { childNodes.append(node) }
    }

    var resultId: String?
    if let result = emittedFolderResult(folder, bytes: visit.bytes) {
      resultId = result.id
      visit.results.append(result)
      onResult(result)
    }

    var node = ScanNode(
      path: folder.url.path, name: folder.url.lastPathComponent, sizeBytes: visit.bytes,
      itemType: .folder, resultId: resultId, lastModified: folder.lastModified)
    if folder.depth >= treeDepth {
      node.otherBytes = visit.bytes
    } else {
      let cutoff = visit.bytes / 100
      for child in childNodes {
        let keep =
          child.sizeBytes > 0
          && (child.sizeBytes >= cutoff
            || (child.itemType == .file && child.sizeBytes >= largeFileThresholdBytes))
        if keep {
          node.children.append(child)
        } else {
          node.otherBytes += child.sizeBytes
        }
      }
    }
    visit.node = node
    return visit
  }

  private func emittedFolderResult(_ folder: OpenFolder, bytes: Int64) -> ScanResult? {
    let url = folder.url
    let name = url.lastPathComponent
    var listed = false
    if name.hasPrefix(".") && settings.scanHiddenFolders {
      listed = bytes > 0
    } else if url.path.localizedCaseInsensitiveContains("/Library/Caches") {
      listed = bytes > 0
    } else if bytes >= largeFileThresholdBytes {
      listed = true
    }

    let result = { () -> ScanResult in
      classifier.classify(
        ClassifiedItemInput(
          path: url.path,
          sizeBytes: bytes,
          itemType: .folder,
          lastModified: folder.lastModified,
          isProtected: folder.isProtected,
          requiresAdmin: parentIsReadOnly(url)
        ))
    }
    if listed { return result() }
    guard bytes > 0, Self.emittedFolderNames.contains(name.lowercased()) else { return nil }
    let candidate = result()
    guard let ruleId = candidate.ruleId, Self.emittedFolderRules.contains(ruleId) else {
      return nil
    }
    return candidate
  }

  private func groupRule(for name: String, root: RootContext) -> String? {
    guard let volume = root.volume else { return nil }
    if volume.groupsDSStore && name == ".DS_Store" { return "safe.ds-store" }
    if volume.groupsAppleDouble && name.hasPrefix("._") { return "safe.appledouble" }
    return nil
  }

  /// One result per grouped rule, standing for every member file under `root`.
  func groupedResults(root: URL, members: [String: [Member]]) -> [ScanResult] {
    members.keys.sorted().compactMap { ruleId in
      guard let files = members[ruleId], let first = files.first else { return nil }
      let bytes = files.reduce(0) { $0 + $1.bytes }
      var result = classifier.classify(
        ClassifiedItemInput(path: first.path, sizeBytes: bytes, itemType: .file))
      guard result.ruleId == ruleId else { return nil }
      let label = ruleId == "safe.ds-store" ? ".DS_Store" : "AppleDouble (._)"
      result.name = "\(files.count) \(label) file\(files.count == 1 ? "" : "s")"
      result.path = root.path
      result.normalizedPath = root.standardizedFileURL.path
      result.memberPaths = files.map(\.path)
      result.fileExtension = nil
      return result
    }
  }

  private func shouldEmitFile(url: URL, bytes: Int64) -> Bool {
    if bytes >= largeFileThresholdBytes { return true }
    let path = url.path
    return bytes > 0 && (path.hasPrefix("/private/var/log/") || path.hasPrefix("/var/log/"))
  }

  private func parentIsReadOnly(_ url: URL) -> Bool {
    !FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
  }

  private func permissionSkip(_ url: URL) -> SkippedPath {
    if url.path.contains("/Library/Containers/") {
      return SkippedPath(
        path: url.path,
        reason: .protectedByMacOS,
        message: "macOS asks before CleanScope reads other apps' data."
      )
    }
    return SkippedPath(
      path: url.path,
      reason: .permissionDenied,
      message: "Permission required to scan this folder."
    )
  }
}
