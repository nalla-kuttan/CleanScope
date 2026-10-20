import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct LeftoverFinderTests {
  private func makeHome(appName: String = "Foo", bundleID: String = "com.foo") throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fm = FileManager.default
    let app = home.appendingPathComponent(".Trash/\(appName).app/Contents")
    try fm.createDirectory(at: app, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundleName": appName], format: .xml,
      options: 0)
    try plist.write(to: app.appendingPathComponent("Info.plist"))
    for folder in [
      "Library/Application Support/\(bundleID)", "Library/Application Support/\(appName)",
      "Library/Caches/\(bundleID)", "Library/Application Support/\(bundleID)bar",
      "Library/Saved Application State/\(bundleID).savedState", "Library/Preferences",
    ] {
      let url = home.appendingPathComponent(folder)
      try fm.createDirectory(at: url, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 100).write(to: url.appendingPathComponent("data"))
    }
    try Data([1]).write(to: home.appendingPathComponent("Library/Preferences/\(bundleID).plist"))
    return home
  }

  @Test func findsExactMatchesForTrashedApp() throws {
    let home = try makeHome()
    let finder = LeftoverFinder(homeDirectory: home.path, isInstalledElsewhere: { _ in false })
    let apps = finder.trashedApps()
    #expect(apps.map(\.bundleID) == ["com.foo"])

    let leftovers = finder.leftovers(for: apps[0])
    let names = Set(leftovers.map { URL(fileURLWithPath: $0.path).lastPathComponent })
    #expect(names == ["com.foo", "Foo", "com.foo.plist", "com.foo.savedState"])
    #expect(!leftovers.contains { $0.path.hasSuffix("com.foobar") })
    for item in leftovers {
      #expect(item.category == .probablyUnused)
      #expect(item.confidence == .medium)
      #expect(item.canDelete)
      #expect(item.ruleId == LeftoverFinder.ruleID)
      #expect(item.ownerApp == "Foo")
    }
  }

  @Test func installedAppHasNoLeftovers() throws {
    let home = try makeHome()
    let finder = LeftoverFinder(homeDirectory: home.path, isInstalledElsewhere: { _ in true })
    #expect(finder.allLeftovers().isEmpty)
  }

  @Test func protectedLocationsAreNeverReturned() throws {
    let home = try makeHome(appName: "1Password", bundleID: "com.agilebits.onepassword")
    let finder = LeftoverFinder(homeDirectory: home.path, isInstalledElsewhere: { _ in false })
    let leftovers = finder.allLeftovers()
    #expect(!leftovers.contains { $0.path.hasSuffix("Application Support/1Password") })
  }
}

@Suite struct DriveCleanerTests {
  let service = ClassificationService()

  @Test func volumeRules() {
    func category(_ path: String, _ type: ItemType) -> SafetyCategory {
      service.classify(ClassifiedItemInput(path: path, sizeBytes: 10, itemType: type)).category
    }
    #expect(category("/Volumes/X/.Trashes/501", .folder) == .safeToDelete)
    #expect(category("/Volumes/X/Photos/._IMG_0001.JPG", .file) == .safeToDelete)
    #expect(category("/Volumes/X/Photos/.DS_Store", .file) == .safeToDelete)
    #expect(category("/Volumes/X/.Spotlight-V100", .folder) == .doNotBulkDelete)
    #expect(category("/Volumes/X/.fseventsd", .folder) == .doNotBulkDelete)
    #expect(category("/Volumes/X/.DocumentRevisions-V100", .folder) == .doNotBulkDelete)
    #expect(category("/Volumes/X/.TemporaryItems", .folder) == .doNotBulkDelete)
  }

  @Test func driveScanGroupsDSStoreAndAppleDouble() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for folder in ["a", "b"] {
      let url = root.appendingPathComponent(folder)
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 10).write(to: url.appendingPathComponent(".DS_Store"))
      try Data(repeating: 1, count: 10).write(to: url.appendingPathComponent("._photo.jpg"))
    }
    let scanner = ScannerService(
      classifier: ClassificationService(), largeFileThresholdBytes: 1_000_000,
      volumeOptions: { _ in VolumeCleanupOptions(groupsDSStore: true, groupsAppleDouble: true) })
    var settings = Settings.default
    settings.scanHiddenFolders = true
    let session = await scanner.scan(paths: [root.path], mode: .full, settings: settings) { _ in }

    let dsStore = try #require(session.results.first { $0.ruleId == "safe.ds-store" })
    #expect(dsStore.memberPaths?.count == 2)
    #expect(dsStore.name == "2 .DS_Store files")
    #expect(dsStore.canDelete)
    let appleDouble = try #require(session.results.first { $0.ruleId == "safe.appledouble" })
    #expect(appleDouble.memberPaths?.count == 2)
  }

  @Test func groupedResultDeletesMembersNotTheFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var item = ScanResult.fixture(path: root.path, sizeBytes: 20, category: .safeToDelete)
    item.memberPaths = [root.appendingPathComponent("a/.DS_Store").path, root.appendingPathComponent("b/.DS_Store").path]
    let moved = MovedPaths()
    let service = DeletionService(
      fileMover: { url in
        moved.append(url.path)
        return true
      }, diskSnapshot: { 1 })

    let session = await service.cleanup(selected: [item])

    #expect(moved.all == item.memberPaths)
    #expect(session.deletedItems.count == 1)
  }
}

final class MovedPaths: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [String] = []
  func append(_ path: String) { lock.withLock { paths.append(path) } }
  var all: [String] { lock.withLock { paths } }
}
