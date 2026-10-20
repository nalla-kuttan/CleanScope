import Foundation

public enum MailVacuumError: Error, Equatable {
  case mailStillRunning
  case vacuumFailed(String)
}

/// Compacts Mail's `Envelope Index` database with a backup that is restored on failure.
public enum MailVacuum {
  public static func envelopeIndexURLs(homeDirectory: String) -> [URL] {
    let mail = URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library/Mail")
    let versions =
      (try? FileManager.default.contentsOfDirectory(at: mail, includingPropertiesForKeys: nil))
      ?? []
    return versions
      .filter { $0.lastPathComponent.hasPrefix("V") }
      .map { $0.appendingPathComponent("MailData/Envelope Index") }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  public static func vacuum(
    databaseURL: URL,
    isMailRunning: () -> Bool,
    vacuum: (URL) throws -> Void = { try SQLiteDatabase.execute("VACUUM;", at: $0) }
  ) throws {
    guard !isMailRunning() else { throw MailVacuumError.mailStillRunning }

    let fm = FileManager.default
    let backupFolder = fm.temporaryDirectory.appendingPathComponent(
      "CleanScope-Mail-\(UUID().uuidString)")
    try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: backupFolder) }

    let companions = ["", "-wal", "-shm"].map {
      URL(fileURLWithPath: databaseURL.path + $0)
    }.filter { fm.fileExists(atPath: $0.path) }
    for file in companions {
      try fm.copyItem(at: file, to: backupFolder.appendingPathComponent(file.lastPathComponent))
    }

    do {
      try vacuum(databaseURL)
    } catch {
      for file in companions {
        let backup = backupFolder.appendingPathComponent(file.lastPathComponent)
        _ = try? fm.replaceItemAt(file, withItemAt: backup)
      }
      throw MailVacuumError.vacuumFailed(String(describing: error))
    }
  }
}
