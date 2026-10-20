import Foundation

/// One confirmed cleanup: when it finished and how many bytes it freed.
public struct CleanupLogEntry: Codable, Equatable, Sendable {
  public var completedAt: Date
  public var recoveredBytes: Int64

  public init(completedAt: Date, recoveredBytes: Int64) {
    self.completedAt = completedAt
    self.recoveredBytes = recoveredBytes
  }
}

/// Persists the most recent cleanups, newest first, capped at `limit` entries.
public struct CleanupLogStore: Sendable {
  public static let limit = 50

  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
      self.fileURL = base.appendingPathComponent("CleanScope/cleanup-log.json")
    }
  }

  public func load() throws -> [CleanupLogEntry] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }
    let data = try Data(contentsOf: fileURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([CleanupLogEntry].self, from: data)
  }

  public func append(_ entry: CleanupLogEntry) throws {
    let entries = Array(([entry] + (try load())).prefix(Self.limit))
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(entries).write(to: fileURL, options: .atomic)
  }
}
