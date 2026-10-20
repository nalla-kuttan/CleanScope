import Foundation

/// The download history macOS keeps for every file downloaded by a quarantine-aware app.
/// Clearing it leaves the files' own quarantine flags alone, so Gatekeeper still checks them.
public struct QuarantineHistory: Sendable {
  public let databaseURL: URL

  public init(databaseURL: URL = QuarantineHistory.defaultURL()) {
    self.databaseURL = databaseURL
  }

  public static func defaultURL(homeDirectory: String = NSHomeDirectory()) -> URL {
    URL(fileURLWithPath: homeDirectory)
      .appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
  }

  public func count() throws -> Int {
    guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
    return try SQLiteDatabase.integer("SELECT COUNT(*) FROM LSQuarantineEvent;", at: databaseURL)
  }

  public func clear() throws {
    guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
    try SQLiteDatabase.execute("DELETE FROM LSQuarantineEvent; VACUUM;", at: databaseURL)
  }
}
