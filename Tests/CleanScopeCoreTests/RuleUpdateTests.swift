import CryptoKit
import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct RuleUpdateTests {
  let key = Curve25519.Signing.PrivateKey()
  let classification = ClassificationService.builtInRules + [
    ClassificationRule(
      id: "safe.example-cache", name: "Example cache",
      matcher: .all([.pathContains("/library/application support/example/"), .nameEquals("cache")]),
      category: .safeToDelete, confidence: .high, specificity: 85, reason: "Example cache",
      riskNote: "Rebuilt by the app.", overrides: ["tool.application-support"])
  ]
  var malware: MalwareRuleSet { MalwareRuleSet(version: 7) }

  private func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private func manifest(version: Int = 2, minAppVersion: String = "1.0.0", rulesData: Data, malwareData: Data) throws
    -> RuleManifest
  {
    var manifest = RuleManifest(
      version: version, minAppVersion: minAppVersion,
      rules: URL(string: "https://rules.example.com/classification.json")!,
      malware: URL(string: "https://rules.example.com/malware.json")!,
      rulesSHA256: RuleManifest.sha256(rulesData), malwareSHA256: RuleManifest.sha256(malwareData),
      signature: "")
    manifest.signature = try key.signature(for: manifest.signingPayload()).base64EncodedString()
    return manifest
  }

  private var verifier: RuleUpdateVerifier {
    RuleUpdateVerifier(publicKey: key.publicKey.rawRepresentation.base64EncodedString())!
  }

  @Test func validSignatureIsAccepted() throws {
    let rules = try encoded(classification)
    let malwareData = try encoded(malware)
    let signed = try manifest(rulesData: rules, malwareData: malwareData)
    #expect(verifier.verify(signed))
    try verifier.accept(signed, currentVersion: 1, appVersion: "1.2.0")
  }

  @Test func tamperedManifestIsRejected() throws {
    var signed = try manifest(rulesData: Data("a".utf8), malwareData: Data("b".utf8))
    signed.version = 99
    #expect(!verifier.verify(signed))
    #expect(throws: RuleUpdateError.badSignature) {
      try verifier.accept(signed, currentVersion: 1, appVersion: "1.0.0")
    }
  }

  @Test func downgradeAndOldAppAreRejected() throws {
    let signed = try manifest(version: 3, minAppVersion: "2.1.0", rulesData: Data(), malwareData: Data())
    #expect(throws: RuleUpdateError.notNewer) {
      try verifier.accept(signed, currentVersion: 3, appVersion: "9.0.0")
    }
    #expect(throws: RuleUpdateError.appTooOld) {
      try verifier.accept(signed, currentVersion: 1, appVersion: "2.0.9")
    }
    #expect(RuleUpdateVerifier.isVersion("2.10.0", atLeast: "2.9.1"))
    #expect(!RuleUpdateVerifier.isVersion("2", atLeast: "2.0.1"))
  }

  @Test func validatorRejectsProtectChanges() throws {
    try RuleSetValidator.validate(classification)

    var removed = classification
    removed.removeAll { $0.id == "protect.personal-folders" }
    #expect(throws: RuleUpdateError.self) { try RuleSetValidator.validate(removed) }

    var changed = classification
    let index = changed.firstIndex { $0.id == "protect.cloud-synced" }!
    changed[index].category = .safeToDelete
    #expect(throws: RuleUpdateError.self) { try RuleSetValidator.validate(changed) }

    var overriding = classification
    overriding[overriding.count - 1].overrides = ["protect.source-code"]
    #expect(throws: RuleUpdateError.self) { try RuleSetValidator.validate(overriding) }

    var added = classification
    added.append(
      ClassificationRule(
        id: "protect.new", name: "New", matcher: .pathContains("/x/"), category: .doNotBulkDelete,
        confidence: .high, specificity: 1, reason: "x", riskNote: "x"))
    #expect(throws: RuleUpdateError.self) { try RuleSetValidator.validate(added) }
  }

  @Test func updaterDownloadsVerifiesAndActivates() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository = RuleRepository(folder: folder)
    #expect(repository.loadActive().version == 0)

    let rules = try encoded(classification)
    let malwareData = try encoded(malware)
    let signed = try manifest(rulesData: rules, malwareData: malwareData)
    let manifestData = try encoded(signed)
    let fetch: @Sendable (URL) async throws -> Data = { url in
      switch url.lastPathComponent {
      case "manifest.json": return manifestData
      case "classification.json": return rules
      default: return malwareData
      }
    }
    let defaults = UserDefaults(suiteName: "CleanScopeRules-\(UUID().uuidString)")!
    let updater = RuleUpdater(
      configuration: RuleUpdateConfiguration(
        manifestURL: URL(string: "https://rules.example.com/manifest.json")!,
        publicKey: key.publicKey.rawRepresentation.base64EncodedString()),
      repository: repository, fetch: fetch, defaults: defaults, appVersion: "1.0.0")

    let outcome = await updater.checkForUpdates(now: Date())
    #expect(outcome == .updated(version: 2))
    let active = repository.loadActive()
    #expect(active.version == 2)
    #expect(active.classification.contains { $0.id == "safe.example-cache" })
    #expect(active.malware.version == 7)

    let again = await updater.checkForUpdates(now: Date().addingTimeInterval(60))
    #expect(again == .skippedRecently)
  }

  @Test func updaterRejectsMismatchedFileHash() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository = RuleRepository(folder: folder)
    let rules = try encoded(classification)
    let signed = try manifest(rulesData: rules, malwareData: try encoded(malware))
    let manifestData = try encoded(signed)
    let fetch: @Sendable (URL) async throws -> Data = { url in
      url.lastPathComponent == "manifest.json" ? manifestData : Data("tampered".utf8)
    }
    let updater = RuleUpdater(
      configuration: RuleUpdateConfiguration(
        manifestURL: URL(string: "https://rules.example.com/manifest.json")!,
        publicKey: key.publicKey.rawRepresentation.base64EncodedString()),
      repository: repository, fetch: fetch,
      defaults: UserDefaults(suiteName: "CleanScopeRules-\(UUID().uuidString)")!, appVersion: "1.0.0")
    let outcome = await updater.checkForUpdates(now: Date())
    #expect(outcome == .rejected("A downloaded rule file doesn't match the signed manifest."))
    #expect(repository.loadActive().version == 0)
  }

  @Test func disabledWithoutConfiguration() async {
    let updater = RuleUpdater(
      configuration: RuleUpdateConfiguration(manifestURL: nil, publicKey: nil),
      repository: RuleRepository(folder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
      fetch: { _ in Data() }, defaults: UserDefaults(suiteName: "x-\(UUID().uuidString)")!,
      appVersion: "1.0.0")
    #expect(await updater.checkForUpdates(now: Date()) == .disabled)
  }

  @Test func repositoryRejectsInvalidStoredRules() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository = RuleRepository(folder: folder)
    var bad = classification
    bad.removeAll { $0.id.hasPrefix("protect.") }
    try repository.store(
      version: 5, classificationData: try encoded(bad), malwareData: try encoded(malware))
    #expect(repository.loadActive().version == 0)
    #expect(repository.loadActive().classification == ClassificationService.builtInRules)
  }
}
