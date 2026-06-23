import Foundation

public struct ScanRepository: Sendable {
  private let fileURL: URL

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
      self.fileURL = base.appendingPathComponent("CleanScope/latest-scan.json")
    }
  }

  public func loadLatest() throws -> ScanSession? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }
    return try JSONDecoder().decode(ScanSession.self, from: Data(contentsOf: fileURL))
  }

  public func saveLatest(_ session: ScanSession) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(session).write(to: fileURL, options: .atomic)
  }
}
