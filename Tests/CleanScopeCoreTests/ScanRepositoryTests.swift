import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct ScanRepositoryTests {
  @Test func repositoryPersistsLatestScan() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let repository = ScanRepository(fileURL: directory.appendingPathComponent("latest.json"))
    let session = ScanSession(
      status: .completed, scanMode: .limited, diskTotalBytes: 100, diskUsedBytes: 40,
      diskAvailableBytes: 60, scannedPaths: ["/tmp"], skippedPaths: [], results: [])

    try repository.saveLatest(session)

    #expect(try repository.loadLatest() == session)
  }

  @Test func limitedPathsAvoidDesktopAndDocumentsByDefault() {
    let paths = ScanLocations.recommended(mode: .limited, homeDirectory: "/Users/me")

    #expect(paths.contains("/Users/me/Library/Caches"))
    #expect(!paths.contains("/Users/me/Documents"))
    #expect(!paths.contains("/Users/me/Desktop"))
  }
}
