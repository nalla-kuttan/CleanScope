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

  @Test func replacingReturnsNilWhenValueIsUnchanged() {
    let settings = Settings.default
    #expect(settings.replacing(\.showMenuBarExtra, with: false) == nil)
    let changed = settings.replacing(\.showMenuBarExtra, with: true)
    #expect(changed?.showMenuBarExtra == true)
    #expect(changed?.scanDownloads == settings.scanDownloads)
  }
}

@Suite struct ExclusionRuleTests {
  @Test func exclusionStoreRemovesRuleByID() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = ExclusionStore(fileURL: directory.appendingPathComponent("exclusions.json"))
    let keep = ExclusionRule(path: "/Users/me/Keep", ruleType: .exactPath)
    let drop = ExclusionRule(path: "/Users/me/Drop", ruleType: .folderRecursive)
    try store.save([keep, drop])

    try store.remove(id: drop.id)

    #expect(try store.load() == [keep])
  }

  @Test func applyingRulesMarksMatchingResultsUndeletable() {
    let rules = [ExclusionRule(path: "/Users/me/Library/Caches/App", ruleType: .folderRecursive)]
    let inside = ScanResult.fixture(
      path: "/Users/me/Library/Caches/App/data", sizeBytes: 10, category: .safeToDelete)
    let outside = ScanResult.fixture(
      path: "/Users/me/Library/Caches/Other", sizeBytes: 10, category: .safeToDelete)

    let excluded = ExclusionRule.applying(rules, to: inside)
    let untouched = ExclusionRule.applying(rules, to: outside)

    #expect(excluded.isExcluded)
    #expect(!excluded.canDelete)
    #expect(excluded.deletionMethod == .notAllowed)
    #expect(untouched == outside)
  }

  @Test func exactPathRuleDoesNotMatchChildren() {
    let rule = ExclusionRule(path: "/Users/me/file.zip", ruleType: .exactPath)
    #expect(rule.matches(path: "/Users/me/file.zip"))
    #expect(!rule.matches(path: "/Users/me/file.zip/child"))
  }
}

@Suite struct CleanupLogStoreTests {
  private func makeStore() throws -> CleanupLogStore {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return CleanupLogStore(fileURL: directory.appendingPathComponent("cleanup-log.json"))
  }

  @Test func cleanupLogRoundTripsNewestFirst() throws {
    let store = try makeStore()
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = (0..<3).map {
      CleanupLogEntry(completedAt: base.addingTimeInterval(Double($0) * 60), recoveredBytes: Int64($0 + 1) * 1_000)
    }
    for entry in entries { try store.append(entry) }

    #expect(try store.load() == entries.reversed())
  }

  @Test func cleanupLogKeepsFifty() throws {
    let store = try makeStore()
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let entries = (0..<55).map {
      CleanupLogEntry(completedAt: base.addingTimeInterval(Double($0) * 60), recoveredBytes: Int64($0))
    }
    for entry in entries { try store.append(entry) }

    let loaded = try store.load()
    #expect(loaded.count == 50)
    #expect(loaded.first == entries.last)
    #expect(loaded.last == entries[5])
  }

  @Test func missingCleanupLogLoadsEmpty() throws {
    #expect(try makeStore().load().isEmpty)
  }
}
