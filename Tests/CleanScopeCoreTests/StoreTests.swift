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

  @Test func exclusionStoreAddsRulesWithoutDuplicates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json"))
    let rule = ExclusionRule(
      path: "/Users/me/Projects", ruleType: .folderRecursive, reason: "Excluded in results")

    try store.add(rule)
    try store.add(rule)

    #expect(try store.load().count == 1)
  }

  @Test func oldSettingsJSONDecodesWithDefaults() throws {
    let json = """
      {"scanHiddenFolders":false,"scanDeveloperFolders":true,"scanDownloads":true,
       "scanAppSupport":true,"defaultDeletionMethod":"trash","showAdvancedCategories":false,
       "saveScanHistory":true,"largeFileThresholdBytes":500000000}
      """
    let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    var expected = Settings.default
    expected.scanHiddenFolders = false
    #expect(settings == expected)
    #expect(!settings.showMenuBarExtra)
    #expect(!settings.deleteImmediately)
    #expect(!settings.preselectSafeCaches)
    #expect(!settings.allowSnapshotThinning)
    #expect(settings.lowDiskThresholdBytes == 10_000_000_000)
    #expect(settings.trashThresholdBytes == 5_000_000_000)
  }

  @Test func newSettingsRoundTrip() throws {
    var settings = Settings.default
    settings.showMenuBarExtra = true
    settings.trustedTeamIDs = ["ABCDE12345"]
    settings.deleteImmediately = true
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
  }
}
