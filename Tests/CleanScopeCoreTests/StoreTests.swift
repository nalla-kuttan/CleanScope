import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct StoreTests {
  @Test func settingsStoreRoundTripsSettings() throws {
    let defaults = UserDefaults(suiteName: "CleanScopeTests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)

    var settings = Settings.default
    settings.scanDownloads = false
    settings.largeFileThresholdBytes = 1_000_000_000

    try store.save(settings)

    #expect(try store.load() == settings)
  }

  @Test func exclusionStoreMatchesRecursiveFolder() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json"))
    let rule = ExclusionRule(
      path: "/Users/me/Projects", ruleType: .folderRecursive, reason: "Source code")

    try store.save([rule])

    #expect(try store.isExcluded(path: "/Users/me/Projects/App/.build"))
    #expect(try !store.isExcluded(path: "/Users/me/Downloads/file.zip"))
  }
}
