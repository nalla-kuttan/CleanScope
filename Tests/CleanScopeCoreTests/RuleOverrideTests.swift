import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct RuleOverrideTests {
  private let overridingRule = ClassificationRule(
    id: "safe.test-cache",
    name: "Test cache",
    matcher: .all([.pathContains("/library/application support/"), .nameEquals("cache")]),
    category: .safeToDelete,
    confidence: .high,
    specificity: 85,
    reason: "Test cache",
    riskNote: "Rebuilt by the app.",
    overrides: ["tool.application-support"]
  )

  @Test func overrideLetsCacheRuleBeatApplicationSupport() {
    let service = ClassificationService(
      rules: ClassificationService.builtInRules + [overridingRule])
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Application Support/Slack/Cache", sizeBytes: 10,
        itemType: .folder))

    #expect(result.category == .safeToDelete)
    #expect(result.canDelete)
  }

  @Test func protectRuleStillWinsOverOverridingRule() {
    let service = ClassificationService(
      rules: ClassificationService.builtInRules + [overridingRule])
    let result = service.classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Application Support/Google/Chrome/Default/Cache",
        sizeBytes: 10, itemType: .folder))

    #expect(result.category == .doNotBulkDelete)
  }

  @Test func noBuiltInRuleOverridesProtectRules() {
    #expect(ClassificationService.validateOverrides(ClassificationService.builtInRules).isEmpty)
    let allowed: Set<String> = ["tool.application-support", "tool.developer-storage"]
    for rule in ClassificationService.builtInRules {
      #expect(Set(rule.overrides).isSubset(of: allowed), Comment(rawValue: rule.id))
    }
  }

  @Test func validateOverridesFlagsProtectTargets() {
    var bad = overridingRule
    bad.overrides = ["protect.personal-folders"]
    #expect(!ClassificationService.validateOverrides([bad]).isEmpty)
  }

  @Test func cloudOnlyInputIsNeverDeletable() {
    let result = ClassificationService().classify(
      ClassifiedItemInput(
        path: "/Users/me/Library/Caches/App/blob", sizeBytes: 0, itemType: .file,
        isCloudOnly: true, cloudOnlyBytes: 5_000))

    #expect(result.isCloudOnly)
    #expect(result.cloudOnlyBytes == 5_000)
    #expect(!result.canDelete)
    #expect(result.deletionMethod == .manualReview)
  }

  @Test func summaryCountsCloudOnlyBytes() {
    var cloud = ScanResult.fixture(
      path: "/Users/me/Library/Caches/A", sizeBytes: 0, category: .safeToDelete)
    cloud.isCloudOnly = true
    cloud.cloudOnlyBytes = 700
    #expect(ScanSummary(results: [cloud]).cloudOnlyBytes == 700)
  }

  @Test func sessionWithoutNewFieldsDecodes() throws {
    let session = ScanSession(
      status: .completed, scanMode: .limited, diskTotalBytes: 100, diskUsedBytes: 40,
      diskAvailableBytes: 60, scannedPaths: ["/tmp"], skippedPaths: [],
      results: [
        ScanResult.fixture(
          path: "/Users/me/Library/Caches/A", sizeBytes: 10, category: .safeToDelete)
      ])
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session))
      as! [String: Any]
    var results = json["results"] as! [[String: Any]]
    for index in results.indices {
      results[index]["isCloudOnly"] = nil
      results[index]["cloudOnlyBytes"] = nil
      results[index]["requiresAdmin"] = nil
    }
    json["results"] = results
    var summary = json["summary"] as! [String: Any]
    summary["cloudOnlyBytes"] = nil
    json["summary"] = summary

    let decoded = try JSONDecoder().decode(
      ScanSession.self, from: JSONSerialization.data(withJSONObject: json))

    #expect(decoded.results.first?.isCloudOnly == false)
    #expect(decoded.results.first?.requiresAdmin == false)
    #expect(decoded.summary.cloudOnlyBytes == 0)
  }

  @Test func ruleWithoutOverridesKeyDecodes() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(overridingRule))
      as! [String: Any]
    json["overrides"] = nil
    let decoded = try JSONDecoder().decode(
      ClassificationRule.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.overrides.isEmpty)
  }
}
