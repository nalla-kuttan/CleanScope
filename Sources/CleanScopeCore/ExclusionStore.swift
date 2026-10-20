import Foundation

public struct ExclusionStore: Sendable {
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
      self.fileURL = base.appendingPathComponent("CleanScope/exclusions.json")
    }
  }

  public func load() throws -> [ExclusionRule] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }
    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([ExclusionRule].self, from: data)
  }

  public func save(_ rules: [ExclusionRule]) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(rules)
    try data.write(to: fileURL, options: .atomic)
  }

  public func add(_ rule: ExclusionRule) throws {
    var rules = try load()
    let normalizedRulePath = URL(fileURLWithPath: rule.path).standardizedFileURL.path
    guard
      !rules.contains(where: {
        $0.ruleType == rule.ruleType
          && URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedRulePath
      })
    else {
      return
    }
    rules.append(rule)
    try save(rules)
  }

  public func remove(id: String) throws {
    try save(try load().filter { $0.id != id })
  }

  public func isExcluded(path: String) throws -> Bool {
    try load().contains { $0.matches(path: path) }
  }
}

extension ExclusionRule {
  public func matches(path: String) -> Bool {
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    let rulePath = URL(fileURLWithPath: self.path).standardizedFileURL.path
    switch ruleType {
    case .exactPath:
      return normalized == rulePath
    case .folderRecursive:
      return normalized == rulePath || normalized.hasPrefix(rulePath + "/")
    case .pattern:
      return normalized.localizedCaseInsensitiveContains(self.path)
    case .category:
      return false
    }
  }

  /// Returns the result marked excluded and undeletable when any rule matches its path.
  public static func applying(_ rules: [ExclusionRule], to result: ScanResult) -> ScanResult {
    guard rules.contains(where: { $0.matches(path: result.normalizedPath) }) else { return result }
    var excluded = result
    excluded.isExcluded = true
    excluded.canDelete = false
    excluded.deletionMethod = .notAllowed
    return excluded
  }
}
