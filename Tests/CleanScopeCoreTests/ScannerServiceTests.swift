import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct ScannerServiceTests {
  @Test func scannerFindsLargeFileAndClassifiesIt() async throws {
    let root = try makeTempDirectory()
    let cache = root.appendingPathComponent("Library/Caches/App")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let file = cache.appendingPathComponent("blob.cache")
    try Data(repeating: 1, count: 2048).write(to: file)

    let scanner = ScannerService(classifier: ClassificationService(), largeFileThresholdBytes: 1024)
    let session = await scanner.scan(paths: [root.path], mode: .limited, settings: .default) { _ in
    }

    #expect(session.status == .completed)
    let expectedPaths = Set([
      file.resolvingSymlinksInPath().path,
      cache.resolvingSymlinksInPath().path,
    ])
    #expect(session.results.contains { expectedPaths.contains($0.normalizedPath) })
    #expect(session.summary.safeToDeleteBytes > 0)
  }

  @Test func scannerRecordsBrokenSymlinkAsSkipped() async throws {
    let root = try makeTempDirectory()
    let link = root.appendingPathComponent("loop")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.path)

    let scanner = ScannerService(classifier: ClassificationService(), largeFileThresholdBytes: 1)
    let session = await scanner.scan(paths: [root.path], mode: .limited, settings: .default) { _ in
    }

    #expect(session.skippedPaths.contains { $0.reason == .symlinkLoop })
  }

  @Test func scannerDoesNotTraverseHiddenFoldersWhenDisabled() async throws {
    let root = try makeTempDirectory()
    let hidden = root.appendingPathComponent(".private-cache")
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    try Data(repeating: 1, count: 2048).write(to: hidden.appendingPathComponent("blob.cache"))
    var settings = Settings.default
    settings.scanHiddenFolders = false

    let scanner = ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1)
    let session = await scanner.scan(paths: [root.path], mode: .limited, settings: settings) {
      _ in
    }

    #expect(!session.results.contains { $0.path.hasPrefix(hidden.path) })
  }

  @Test func scannerCanBeCancelledDuringProgressiveResults() async throws {
    let root = try makeTempDirectory()
    let cache = root.appendingPathComponent("Library/Caches/App")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    for index in 0..<100 {
      try Data(repeating: UInt8(index % 255), count: 128)
        .write(to: cache.appendingPathComponent("\(index).cache"))
    }

    let scanner = ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1)
    let session = await scanner.scan(paths: [root.path], mode: .limited, settings: .default) {
      _ in
      scanner.cancel()
    }

    #expect(session.status == .cancelled)
    #expect(session.results.count < 100)
  }

  @Test func scannerRecordsPermissionDeniedPath() async throws {
    let root = try makeTempDirectory()
    let blocked = root.appendingPathComponent("blocked")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try Data([1]).write(to: blocked.appendingPathComponent("item"))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0], ofItemAtPath: blocked.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: blocked.path)
    }

    let scanner = ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1)
    let session = await scanner.scan(paths: [root.path], mode: .limited, settings: .default) {
      _ in
    }
    #expect(
      session.skippedPaths.contains {
        URL(fileURLWithPath: $0.path).lastPathComponent == "blocked"
          && $0.reason == .permissionDenied
      })
  }

  @Test func parallelScanMatchesSerialScan() async throws {
    let root = try makeFixtureTree()
    func signature(_ session: ScanSession) -> Set<String> {
      Set(session.results.map { "\($0.normalizedPath)|\($0.sizeBytes)|\($0.category.rawValue)" })
    }
    let paths = [root.path, root.appendingPathComponent("Library/Caches").path, root.path]

    let serial = await ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1_000, maxConcurrency: 1
    ).scan(paths: paths, mode: .developer, settings: .default) { _ in }
    let parallel = await ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1_000, maxConcurrency: 6
    ).scan(paths: paths, mode: .developer, settings: .default) { _ in }

    #expect(!serial.results.isEmpty)
    #expect(signature(serial) == signature(parallel))
    #expect(serial.summary.totalCleanableBytes == parallel.summary.totalCleanableBytes)
  }

  @Test func scanBuildsTreeWithRootSizes() async throws {
    let root = try makeFixtureTree()
    let session = await ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1_000
    ).scan(paths: [root.path], mode: .limited, settings: .default) { _ in }

    let tree = try #require(session.tree)
    let rootNode = try #require(tree.children.first)
    let childTotal = rootNode.children.reduce(0) { $0 + $1.sizeBytes } + rootNode.otherBytes
    #expect(rootNode.sizeBytes > 0)
    #expect(rootNode.sizeBytes == childTotal)
    #expect(tree.sizeBytes == rootNode.sizeBytes)
  }

  @Test func treeIsNotPersisted() throws {
    var session = ScanSession(
      status: .completed, scanMode: .limited, diskTotalBytes: 1, diskUsedBytes: 1,
      diskAvailableBytes: 0, scannedPaths: [], skippedPaths: [], results: [])
    session.tree = ScanNode(path: "/", name: "/", sizeBytes: 1, itemType: .folder)
    let decoded = try JSONDecoder().decode(
      ScanSession.self, from: JSONEncoder().encode(session))
    #expect(decoded.tree == nil)
  }

  @Test func containerPermissionErrorIsProtectedByMacOS() async throws {
    let root = try makeTempDirectory()
    let blocked = root.appendingPathComponent("Library/Containers/com.example/Data/Library/Caches")
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try Data([1]).write(to: blocked.appendingPathComponent("item"))
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: blocked.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: blocked.path)
    }

    let session = await ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1
    ).scan(paths: [blocked.path], mode: .developer, settings: .default) { _ in }

    #expect(session.skippedPaths.contains { $0.reason == .protectedByMacOS })
  }

  @Test func knownCacheFoldersOutsideCachesAreEmitted() async throws {
    let root = try makeTempDirectory()
    let support = root.appendingPathComponent("Library/Application Support/Slack")
    let cache = support.appendingPathComponent("Cache")
    let indexed = support.appendingPathComponent("IndexedDB")
    let reports = root.appendingPathComponent("Library/Logs/DiagnosticReports")
    for folder in [cache, indexed, reports] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 64).write(to: folder.appendingPathComponent("blob"))
    }

    let session = await ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1_000_000
    ).scan(paths: [root.path], mode: .full, settings: .default) { _ in }

    let byName = Dictionary(
      session.results.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    #expect(byName["Cache"]?.category == .safeToDelete)
    #expect(byName["DiagnosticReports"]?.category == .safeToDelete)
    #expect(byName["IndexedDB"] == nil)
  }

  @Test func systemGuardedChildrenAreSkippedSilently() async throws {
    let root = try makeTempDirectory()
    let scanner = ScannerService(classifier: ClassificationService(), largeFileThresholdBytes: 1)
    let session = await scanner.scan(
      paths: [root.path, "/Volumes"], mode: .limited, settings: .default
    ) { _ in }
    #expect(session.status == .completed)
  }

  private func makeFixtureTree() throws -> URL {
    let root = try makeTempDirectory()
    let caches = root.appendingPathComponent("Library/Caches")
    for app in ["A", "B", "C"] {
      let folder = caches.appendingPathComponent(app)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      for index in 0..<4 {
        try Data(repeating: UInt8(index), count: 4_096 * (index + 1))
          .write(to: folder.appendingPathComponent("\(index).bin"))
      }
    }
    let downloads = root.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    try Data(repeating: 9, count: 8_192).write(to: downloads.appendingPathComponent("big.zip"))
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("loop"), withDestinationURL: caches)
    return root
  }

  private func makeTempDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}
