import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct QuarantineHistoryTests {
  private func makeDatabase(rows: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString)-QuarantineEventsV2")
    var sql = "CREATE TABLE LSQuarantineEvent (LSQuarantineEventIdentifier TEXT, LSQuarantineDataURLString TEXT);"
    for index in 0..<rows {
      sql += "INSERT INTO LSQuarantineEvent VALUES ('\(index)', 'https://example.com/\(index).dmg');"
    }
    try SQLiteDatabase.execute(sql, at: url)
    return url
  }

  @Test func countsAndClearsDownloadHistory() throws {
    let history = QuarantineHistory(databaseURL: try makeDatabase(rows: 3))
    #expect(try history.count() == 3)
    try history.clear()
    #expect(try history.count() == 0)
  }

  @Test func missingDatabaseCountsZero() throws {
    let history = QuarantineHistory(
      databaseURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    #expect(try history.count() == 0)
  }

  @Test func defaultLocation() {
    #expect(
      QuarantineHistory.defaultURL(homeDirectory: "/Users/me").path
        == "/Users/me/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
  }
}
