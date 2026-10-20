import CryptoKit
import Foundation

public enum RuleUpdateError: Error, Equatable {
  case badSignature
  case notNewer
  case appTooOld
  case fileMismatch
  case invalidRules(String)
}

/// Signed description of a rule release. The signature covers every field except itself,
/// including the SHA-256 of both rule files, so the files are verified too.
public struct RuleManifest: Codable, Equatable, Sendable {
  public var version: Int
  public var minAppVersion: String
  public var rules: URL
  public var malware: URL
  public var rulesSHA256: String
  public var malwareSHA256: String
  public var signature: String

  public init(
    version: Int, minAppVersion: String, rules: URL, malware: URL, rulesSHA256: String,
    malwareSHA256: String, signature: String
  ) {
    self.version = version
    self.minAppVersion = minAppVersion
    self.rules = rules
    self.malware = malware
    self.rulesSHA256 = rulesSHA256
    self.malwareSHA256 = malwareSHA256
    self.signature = signature
  }

  private struct Payload: Encodable {
    var version: Int
    var minAppVersion: String
    var rules: URL
    var malware: URL
    var rulesSHA256: String
    var malwareSHA256: String
  }

  /// Canonical bytes that are signed: sorted-key JSON without the signature.
  public func signingPayload() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(
      Payload(
        version: version, minAppVersion: minAppVersion, rules: rules, malware: malware,
        rulesSHA256: rulesSHA256, malwareSHA256: malwareSHA256))
  }

  public static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

public struct RuleUpdateVerifier: Sendable {
  private let publicKey: Curve25519.Signing.PublicKey

  /// `publicKey` is the base64 raw Ed25519 public key embedded in the app.
  public init?(publicKey: String) {
    guard let data = Data(base64Encoded: publicKey),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    else { return nil }
    self.publicKey = key
  }

  public func verify(_ manifest: RuleManifest) -> Bool {
    guard let signature = Data(base64Encoded: manifest.signature),
      let payload = try? manifest.signingPayload()
    else { return false }
    return publicKey.isValidSignature(signature, for: payload)
  }

  /// Accepts only signed manifests that are newer than what is installed and supported by this
  /// version of the app.
  public func accept(_ manifest: RuleManifest, currentVersion: Int, appVersion: String) throws {
    guard verify(manifest) else { throw RuleUpdateError.badSignature }
    guard manifest.version > currentVersion else { throw RuleUpdateError.notNewer }
    guard Self.isVersion(appVersion, atLeast: manifest.minAppVersion) else {
      throw RuleUpdateError.appTooOld
    }
  }

  public static func isVersion(_ version: String, atLeast minimum: String) -> Bool {
    let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
    let rhs = minimum.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(lhs.count, rhs.count) {
      let a = index < lhs.count ? lhs[index] : 0
      let b = index < rhs.count ? rhs[index] : 0
      if a != b { return a > b }
    }
    return true
  }
}

public enum RuleSetValidator {
  /// Downloaded classification rules may add or change ordinary rules, but every `protect.*`
  /// rule must match the built-in one exactly, and no rule may override a protected rule.
  public static func validate(
    _ rules: [ClassificationRule], builtIn: [ClassificationRule] = ClassificationService.builtInRules
  ) throws {
    let protectedBuiltIn = builtIn.filter { $0.id.hasPrefix("protect.") }
    let protectedDownloaded = rules.filter { $0.id.hasPrefix("protect.") }
    guard protectedDownloaded.count == protectedBuiltIn.count else {
      throw RuleUpdateError.invalidRules("Protected rules were added or removed.")
    }
    for rule in protectedBuiltIn where !protectedDownloaded.contains(rule) {
      throw RuleUpdateError.invalidRules("Protected rule \(rule.id) was changed.")
    }
    guard Set(rules.map(\.id)).count == rules.count else {
      throw RuleUpdateError.invalidRules("Rule ids must be unique.")
    }
    let violations = ClassificationService.validateOverrides(rules)
    guard violations.isEmpty else {
      throw RuleUpdateError.invalidRules(violations.joined(separator: "; "))
    }
  }
}

public struct ActiveRules: Sendable {
  public var version: Int
  public var classification: [ClassificationRule]
  public var malware: MalwareRuleSet
  public var updatedAt: Date?
}

/// Stores downloaded rules in Application Support. Anything that fails validation at load time
/// is ignored and the rules built into the app are used instead.
public struct RuleRepository: Sendable {
  private let folder: URL

  public init(folder: URL? = nil) {
    self.folder =
      folder
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("CleanScope/Rules")
  }

  private var versionURL: URL { folder.appendingPathComponent("version.json") }
  private var classificationURL: URL { folder.appendingPathComponent("classification.json") }
  private var malwareURL: URL { folder.appendingPathComponent("malware.json") }

  public static let bundled = ActiveRules(
    version: 0, classification: ClassificationService.builtInRules, malware: .bundled,
    updatedAt: nil)

  public func loadActive() -> ActiveRules {
    guard let versionData = try? Data(contentsOf: versionURL),
      let info = try? JSONDecoder().decode(StoredVersion.self, from: versionData),
      let rulesData = try? Data(contentsOf: classificationURL),
      let malwareData = try? Data(contentsOf: malwareURL),
      let classification = try? JSONDecoder().decode([ClassificationRule].self, from: rulesData),
      let malware = try? JSONDecoder().decode(MalwareRuleSet.self, from: malwareData),
      (try? RuleSetValidator.validate(classification)) != nil
    else { return Self.bundled }
    return ActiveRules(
      version: info.version, classification: classification, malware: malware,
      updatedAt: info.updatedAt)
  }

  public func store(version: Int, classificationData: Data, malwareData: Data) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try classificationData.write(to: classificationURL, options: .atomic)
    try malwareData.write(to: malwareURL, options: .atomic)
    try JSONEncoder().encode(StoredVersion(version: version, updatedAt: Date()))
      .write(to: versionURL, options: .atomic)
  }

  private struct StoredVersion: Codable {
    var version: Int
    var updatedAt: Date
  }
}

public struct RuleUpdateConfiguration: Sendable {
  public var manifestURL: URL?
  /// Base64 raw Ed25519 public key that signs rule releases.
  public var publicKey: String?

  public init(manifestURL: URL?, publicKey: String?) {
    self.manifestURL = manifestURL
    self.publicKey = publicKey
  }

  /// Updates are off until a manifest host and signing key are chosen.
  public static let shipping = RuleUpdateConfiguration(manifestURL: nil, publicKey: nil)
}

public enum RuleUpdateOutcome: Equatable, Sendable {
  case disabled
  case skippedRecently
  case noUpdate
  case updated(version: Int)
  case rejected(String)
  case failed(String)
}

/// Checks for signed rule updates at most once a day, silently when nothing changed.
public struct RuleUpdater: @unchecked Sendable {
  private let configuration: RuleUpdateConfiguration
  private let repository: RuleRepository
  private let fetch: @Sendable (URL) async throws -> Data
  private let defaults: UserDefaults
  private let appVersion: String
  private let lastCheckKey = "CleanScope.ruleUpdateLastCheck"

  public init(
    configuration: RuleUpdateConfiguration = .shipping,
    repository: RuleRepository = RuleRepository(),
    fetch: @escaping @Sendable (URL) async throws -> Data = { url in
      try await URLSession.shared.data(from: url).0
    },
    defaults: UserDefaults = .standard,
    appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "1.0.0"
  ) {
    self.configuration = configuration
    self.repository = repository
    self.fetch = fetch
    self.defaults = defaults
    self.appVersion = appVersion
  }

  public var lastCheck: Date? { defaults.object(forKey: lastCheckKey) as? Date }

  public func checkForUpdates(now: Date = Date(), force: Bool = false) async -> RuleUpdateOutcome {
    guard let manifestURL = configuration.manifestURL, let key = configuration.publicKey,
      let verifier = RuleUpdateVerifier(publicKey: key)
    else { return .disabled }
    if !force, let last = lastCheck, now.timeIntervalSince(last) < 86_400 {
      return .skippedRecently
    }
    defaults.set(now, forKey: lastCheckKey)

    do {
      let manifest = try JSONDecoder().decode(RuleManifest.self, from: try await fetch(manifestURL))
      let current = repository.loadActive().version
      do {
        try verifier.accept(manifest, currentVersion: current, appVersion: appVersion)
      } catch RuleUpdateError.notNewer {
        return .noUpdate
      } catch RuleUpdateError.appTooOld {
        return .rejected("These rules need a newer version of CleanScope.")
      } catch {
        return .rejected("The rule update isn't signed by CleanScope.")
      }

      let rulesData = try await fetch(manifest.rules)
      let malwareData = try await fetch(manifest.malware)
      guard RuleManifest.sha256(rulesData) == manifest.rulesSHA256,
        RuleManifest.sha256(malwareData) == manifest.malwareSHA256
      else { return .rejected("A downloaded rule file doesn't match the signed manifest.") }

      let rules = try JSONDecoder().decode([ClassificationRule].self, from: rulesData)
      _ = try JSONDecoder().decode(MalwareRuleSet.self, from: malwareData)
      do {
        try RuleSetValidator.validate(rules)
      } catch RuleUpdateError.invalidRules(let reason) {
        return .rejected(reason)
      }
      try repository.store(
        version: manifest.version, classificationData: rulesData, malwareData: malwareData)
      return .updated(version: manifest.version)
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}
