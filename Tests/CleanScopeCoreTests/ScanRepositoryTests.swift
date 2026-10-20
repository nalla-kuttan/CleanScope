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

@Suite struct ScanLocationTests {
  private func makeHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let containers = home.appendingPathComponent("Library/Containers")
    try FileManager.default.createDirectory(
      at: containers.appendingPathComponent("com.example.named/Data/Library/Caches"),
      withIntermediateDirectories: true)
    let uuid = containers.appendingPathComponent("4219210F-CE62-4AF4-A44D-31090E3E7834")
    try FileManager.default.createDirectory(
      at: uuid.appendingPathComponent("Data/Library/Caches"), withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["MCMMetadataIdentifier": "com.example.uuid"], format: .xml, options: 0)
    try plist.write(to: uuid.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
    try FileManager.default.createDirectory(
      at: containers.appendingPathComponent("com.example.nocache/Data"),
      withIntermediateDirectories: true)
    return home
  }

  @Test func containerCacheRootsListExistingCacheFolders() throws {
    let home = try makeHome()
    let roots = ScanLocations.containerCacheRoots(homeDirectory: home.path)
    #expect(roots.count == 2)
    #expect(roots.allSatisfy { $0.hasSuffix("/Data/Library/Caches") })
  }

  @Test func containerBundleIdentifierReadsMetadata() throws {
    let home = try makeHome()
    let containers = home.appendingPathComponent("Library/Containers")
    #expect(
      ScanLocations.containerBundleIdentifier(
        containerURL: containers.appendingPathComponent("4219210F-CE62-4AF4-A44D-31090E3E7834"))
        == "com.example.uuid")
    #expect(
      ScanLocations.containerBundleIdentifier(
        containerURL: containers.appendingPathComponent("com.example.named"))
        == "com.example.named")
  }

  @Test func modesIncludeContainerCachesExceptLimited() throws {
    let home = try makeHome()
    let cacheRoot = home.appendingPathComponent(
      "Library/Containers/com.example.named/Data/Library/Caches"
    ).standardizedFileURL.path
    #expect(!ScanLocations.recommended(mode: .limited, homeDirectory: home.path).contains(cacheRoot))
    #expect(ScanLocations.recommended(mode: .developer, homeDirectory: home.path).contains(cacheRoot))
    #expect(ScanLocations.recommended(mode: .full, homeDirectory: home.path).contains(cacheRoot))
  }

  @Test func fullModeCoversSystemLogs() {
    let roots = ScanLocations.recommended(mode: .full, homeDirectory: "/Users/me")
    func covered(_ path: String) -> Bool {
      roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
    for path in [
      "/private/var/log", "/Library/Logs", "/Users/me/Library/Logs/DiagnosticReports",
      "/Library/Logs/DiagnosticReports",
    ] {
      #expect(covered(path), Comment(rawValue: path))
    }
    #expect(Set(roots).count == roots.count)
    for root in roots {
      #expect(!roots.contains { $0 != root && root.hasPrefix($0 + "/") }, Comment(rawValue: root))
    }
  }
}
