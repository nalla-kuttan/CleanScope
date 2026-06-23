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

  private func makeTempDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}
