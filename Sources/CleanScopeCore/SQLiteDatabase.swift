import Foundation
import SQLite3

public enum SQLiteError: Error, Equatable {
  case openFailed(String)
  case statementFailed(String)
}

/// Small wrapper over the system SQLite3 library for maintenance and privacy tasks.
public enum SQLiteDatabase {
  public static func execute(_ sql: String, at url: URL) throws {
    try withDatabase(url) { db in
      var message: UnsafeMutablePointer<CChar>?
      guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
        let text = message.map { String(cString: $0) } ?? "SQLite error"
        sqlite3_free(message)
        throw SQLiteError.statementFailed(text)
      }
    }
  }

  /// The first column of the first row of `sql`, as an integer.
  public static func integer(_ sql: String, at url: URL) throws -> Int {
    try withDatabase(url, readOnly: true) { db in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw SQLiteError.statementFailed(String(cString: sqlite3_errmsg(db)))
      }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
      return Int(sqlite3_column_int64(statement, 0))
    }
  }

  private static func withDatabase<T>(
    _ url: URL, readOnly: Bool = false, _ body: (OpaquePointer?) throws -> T
  ) throws -> T {
    var db: OpaquePointer?
    let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
      let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
      sqlite3_close(db)
      throw SQLiteError.openFailed(message)
    }
    defer { sqlite3_close(db) }
    return try body(db)
  }
}
