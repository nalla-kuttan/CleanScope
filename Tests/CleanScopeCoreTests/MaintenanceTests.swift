import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct MaintenanceTests {
  @Test func adminCommandsMatchGoldenList() {
    #expect(
      MaintenanceCatalog.adminCommand(for: "flush-dns", uid: 501)
        == "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")
    #expect(MaintenanceCatalog.adminCommand(for: "reindex-spotlight", uid: 501) == "/usr/bin/mdutil -E /")
    #expect(
      MaintenanceCatalog.adminCommand(for: "periodic", uid: 501)
        == "/usr/sbin/periodic daily weekly monthly")
    #expect(
      MaintenanceCatalog.adminCommand(for: "repair-home-permissions", uid: 501)
        == "/usr/sbin/diskutil resetUserPermissions / 501")
    #expect(MaintenanceCatalog.adminCommand(for: "speed-up-mail", uid: 501) == nil)
  }

  @Test func everyAdminTaskHasAGoldenCommand() {
    for task in MaintenanceCatalog.all(fileExists: { _ in true }) where task.requiresAdmin {
      #expect(MaintenanceCatalog.adminCommand(for: task.id, uid: 501) != nil, Comment(rawValue: task.id))
    }
  }

  @Test func periodicIsOnlyAvailableWhenInstalled() {
    let missing = MaintenanceCatalog.all(fileExists: { $0 != "/usr/sbin/periodic" })
    #expect(missing.first { $0.id == "periodic" }?.isAvailable == false)
    let present = MaintenanceCatalog.all(fileExists: { _ in true })
    #expect(present.first { $0.id == "periodic" }?.isAvailable == true)
  }

  @Test func adminTaskRunsThroughPrivilegedRunner() async {
    let privileged = StubPrivilegedRunner()
    let context = MaintenanceContext(
      runner: StubProcessRunner(), privileged: privileged, homeDirectory: "/Users/me", uid: 501)
    let task = MaintenanceCatalog.all(fileExists: { _ in true }).first { $0.id == "flush-dns" }!
    let outcome = await task.run(context: context)
    #expect(privileged.recorded == [MaintenanceCatalog.adminCommand(for: "flush-dns", uid: 501)!])
    #expect(outcome.isSuccess)
  }

  @Test func purgeableTaskThinsOneGibibyteAtUrgencyThree() async {
    let runner = StubProcessRunner()
    let context = MaintenanceContext(
      runner: runner, privileged: StubPrivilegedRunner(), homeDirectory: "/Users/me", uid: 501)
    let task = MaintenanceCatalog.all(fileExists: { _ in true }).first { $0.id == "free-purgeable" }!
    _ = await task.run(context: context)
    #expect(runner.recorded.first?.1 == ["thinlocalsnapshots", "/", "1073741824", "3"])
  }

  @Test func mailVacuumRefusesWhileMailRuns() throws {
    let db = try makeDatabase()
    #expect(throws: MailVacuumError.mailStillRunning) {
      try MailVacuum.vacuum(databaseURL: db, isMailRunning: { true }, vacuum: { _ in })
    }
  }

  @Test func mailVacuumRestoresBackupOnFailure() throws {
    let db = try makeDatabase()
    let original = try Data(contentsOf: db)
    #expect(throws: MailVacuumError.self) {
      try MailVacuum.vacuum(
        databaseURL: db, isMailRunning: { false },
        vacuum: { url in
          try Data("corrupted".utf8).write(to: url)
          throw MailVacuumError.vacuumFailed("simulated")
        })
    }
    #expect(try Data(contentsOf: db) == original)
  }

  @Test func mailVacuumRunsSQLiteVacuum() throws {
    let db = try makeDatabase()
    try MailVacuum.vacuum(databaseURL: db, isMailRunning: { false })
    #expect(FileManager.default.fileExists(atPath: db.path))
  }

  @Test func runStoreRemembersLastRun() throws {
    let defaults = UserDefaults(suiteName: "CleanScopeMaintenance-\(UUID().uuidString)")!
    let store = MaintenanceRunStore(defaults: defaults)
    let run = MaintenanceRun(
      taskID: "flush-dns", date: Date(timeIntervalSince1970: 1_000),
      outcome: .completed("Done"))
    try store.record(run)
    #expect(try store.load()["flush-dns"] == run)
  }

  private func makeDatabase() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(UUID().uuidString)/Envelope Index")
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try SQLiteDatabase.execute("CREATE TABLE t(x); INSERT INTO t VALUES (1);", at: url)
    return url
  }
}
