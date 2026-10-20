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
