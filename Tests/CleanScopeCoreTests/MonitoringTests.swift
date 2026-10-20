import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct MonitoringTests {
  @Test func cpuUsageFromTickDifferences() {
    let previous = [CoreTicks(user: 100, system: 50, idle: 850, nice: 0), CoreTicks(user: 0, system: 0, idle: 1_000, nice: 0)]
    let current = [CoreTicks(user: 150, system: 100, idle: 900, nice: 0), CoreTicks(user: 0, system: 0, idle: 1_100, nice: 0)]
    let usage = CPULoad.usage(previous: previous, current: current)
    #expect(usage.perCore == [100.0 / 150.0, 0])
    #expect(abs(usage.total - 100.0 / 250.0) < 0.0001)
  }

  @Test func cpuUsageHandlesMismatchedSamples() {
    #expect(CPULoad.usage(previous: [], current: [CoreTicks(user: 1, system: 1, idle: 1, nice: 0)]).total == 0)
  }

  @Test func networkRateIgnoresCounterResets() {
    let rate = NetworkThroughput.rate(
      previous: InterfaceCounters(received: 1_000, sent: 500),
      current: InterfaceCounters(received: 3_000, sent: 400), interval: 2)
    #expect(rate.receivedPerSecond == 1_000)
    #expect(rate.sentPerSecond == 0)
  }

  @Test func batteryHealthFallsBackToNominalCapacity() throws {
    let health = try #require(
      BatteryHealth.from(registry: [
        "CycleCount": 271, "DesignCycleCount9C": 1_000, "DesignCapacity": 5_103,
        "NominalChargeCapacity": 4_629, "MaxCapacity": 100,
      ]))
    #expect(health.cycleCount == 271)
    #expect(health.designCycleCount == 1_000)
    #expect(abs(health.healthFraction - 4_629.0 / 5_103.0) < 0.0001)
    #expect(!health.isCritical)

    let raw = try #require(
      BatteryHealth.from(registry: ["DesignCapacity": 1_000, "AppleRawMaxCapacity": 650, "NominalChargeCapacity": 900]))
    #expect(raw.healthFraction == 0.65)
    #expect(raw.isCritical)
    #expect(BatteryHealth.from(registry: ["CycleCount": 3]) == nil)

    let nested = try #require(
      BatteryHealth.from(registry: [
        "CycleCount": 271, "DesignCycleCount9C": 1_000,
        "BatteryData": ["DesignCapacity": 5_103, "NominalChargeCapacity": 4_626],
      ]))
    #expect(nested.cycleCount == 271)
    #expect(abs(nested.healthFraction - 4_626.0 / 5_103.0) < 0.0001)
  }

  @Test func uptimeFromBootTime() {
    let boot = Date(timeIntervalSince1970: 1_000)
    #expect(Uptime.since(bootTime: boot, now: Date(timeIntervalSince1970: 87_400)) == 86_400)
    #expect(Uptime.bootTime() != nil)
  }

  @Test func hungAfterTwoConsecutiveFailures() {
    var detector = HungAppDetector()
    var results: [Bool] = []
    results.append(detector.record(pid: 10, responded: false))
    results.append(detector.record(pid: 10, responded: false))
    let hungAfterTwo = detector.isHung(10)
    results.append(detector.record(pid: 10, responded: true))
    results.append(detector.record(pid: 10, responded: false))
    detector.forget(except: [])
    results.append(detector.record(pid: 10, responded: false))
    #expect(results == [false, true, false, false, false])
    #expect(hungAfterTwo)
  }

  @Test func statusSummaryScoresAndExplains() {
    let gb: Int64 = 1_000_000_000
    let healthy = StatusSummary.evaluate(
      StatusInputs(
        disk: DiskSnapshot(totalBytes: 1_000 * gb, availableBytes: 400 * gb), trashBytes: gb,
        threatsFound: 0, lastProtectionScan: Date(), batteryHealth: 0.95, memoryPressure: 1),
      now: Date())
    #expect(healthy.score == 100)
    #expect(healthy.checks.map(\.title) == ["Disk space", "Trash", "Protection", "Battery", "Memory"])
    #expect(healthy.checks.allSatisfy { $0.isGood })

    let strained = StatusSummary.evaluate(
      StatusInputs(
        disk: DiskSnapshot(totalBytes: 1_000 * gb, availableBytes: 20 * gb), trashBytes: 9 * gb,
        threatsFound: 2, lastProtectionScan: Date(), batteryHealth: 0.6, memoryPressure: 2),
      now: Date())
    #expect(strained.score == 0)
    #expect(strained.checks.allSatisfy { !$0.isGood })
    #expect(strained.checks.first { $0.title == "Protection" }?.reason == "2 items need your review.")
    #expect(strained.checks.first { $0.title == "Disk space" }?.reason == "20 GB available.")

    let noBattery = StatusSummary.evaluate(
      StatusInputs(
        disk: DiskSnapshot(totalBytes: 1_000 * gb, availableBytes: 20 * gb), trashBytes: 0,
        threatsFound: 0, lastProtectionScan: Date(), batteryHealth: nil, memoryPressure: 1),
      now: Date())
    #expect(!noBattery.checks.contains { $0.title == "Battery" })
    #expect(noBattery.score == Int((50.0 / 85.0 * 100).rounded()))
  }

  @Test func protectionNeverScannedNeedsAttention() {
    let summary = StatusSummary.evaluate(
      StatusInputs(
        disk: nil, trashBytes: nil, threatsFound: nil, lastProtectionScan: nil,
        batteryHealth: nil, memoryPressure: nil),
      now: Date())
    #expect(summary.checks.map(\.title) == ["Protection"])
    #expect(summary.checks.first?.reason == "No protection scan yet.")
  }
}

@Suite struct SMCDecodingTests {
  @Test func decodesSp78AndFloat() {
    #expect(SMCReader.fourCC("TC0P") == 0x5443_3050)
    #expect(SMCReader.decode(type: SMCReader.fourCC("sp78"), bytes: [0x2D, 0x80]) == 45.5)
    let bits = Float(52.25).bitPattern
    let bytes = [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24)]
    #expect(SMCReader.decode(type: SMCReader.fourCC("flt "), bytes: bytes) == 52.25)
    #expect(SMCReader.decode(type: SMCReader.fourCC("ui8 "), bytes: [1]) == nil)
  }
}
