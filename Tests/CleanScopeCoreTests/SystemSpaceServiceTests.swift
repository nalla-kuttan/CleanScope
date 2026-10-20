import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct SystemSpaceServiceTests {
  @Test func parsesNoSnapshots() {
    #expect(SystemSpaceService.parseSnapshots("Snapshots for volume group containing disk /:\n").isEmpty)
  }

  @Test func parsesSnapshotsAndIgnoresOSUpdateLines() {
    let output = """
      Snapshots for volume group containing disk /:
      com.apple.os.update-5203530F8BB20B9DABC5CE76A0FFE87CCC885EE69B8A
      com.apple.TimeMachine.2026-10-01-123456.local
      com.apple.TimeMachine.2026-10-02-080000.local
      """
    let dates = SystemSpaceService.parseSnapshots(output, timeZone: TimeZone(identifier: "UTC")!)
    #expect(dates.count == 2)
    var components = DateComponents()
    components.timeZone = TimeZone(identifier: "UTC")
    components.year = 2026
    components.month = 10
    components.day = 1
    components.hour = 12
    components.minute = 34
    components.second = 56
    #expect(dates.first == Calendar(identifier: .gregorian).date(from: components))
  }

  @Test func purgeableIsClampedAtZero() {
    #expect(SystemSpaceService.purgeableBytes(important: 100, available: 40) == 60)
    #expect(SystemSpaceService.purgeableBytes(important: 10, available: 40) == 0)
  }

  @Test func thinRunsTmutilWithLowestUrgency() async throws {
    let runner = StubProcessRunner()
    try await SystemSpaceService(runner: runner).thin(requestedBytes: 10_000_000_000)
    #expect(runner.recorded.first?.0 == "/usr/bin/tmutil")
    #expect(runner.recorded.first?.1 == ["thinlocalsnapshots", "/", "10000000000", "1"])
  }

  @Test func thinThrowsOnFailure() async {
    let runner = StubProcessRunner(
      output: ProcessOutput(status: 1, stdout: "", stderr: "not permitted"))
    await #expect(throws: SystemSpaceError.self) {
      try await SystemSpaceService(runner: runner).thin(requestedBytes: 1)
    }
  }

  @Test func processRunnerCapturesOutputAndTimesOut() async throws {
    let output = try await ProcessRunner().run("/bin/echo", ["hello"], timeout: 5)
    #expect(output.status == 0)
    #expect(output.stdout == "hello\n")
    await #expect(throws: ProcessRunnerError.self) {
      try await ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.2)
    }
  }
}
