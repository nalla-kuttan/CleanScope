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

  public func isExcluded(path: String) throws -> Bool {
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    return try load().contains { rule in
      let rulePath = URL(fileURLWithPath: rule.path).standardizedFileURL.path
      switch rule.ruleType {
      case .exactPath:
        return normalized == rulePath
      case .folderRecursive:
        return normalized == rulePath || normalized.hasPrefix(rulePath + "/")
      case .pattern:
        return normalized.localizedCaseInsensitiveContains(rule.path)
      case .category:
        return false
      }
    }
  }
}
