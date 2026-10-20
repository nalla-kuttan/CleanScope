import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct AlertTests {
  let gb: Int64 = 1_000_000_000
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  private func inputs(available: Int64, total: Int64 = 1_000_000_000_000) -> AlertInputs {
    AlertInputs(disk: DiskSnapshot(totalBytes: total, availableBytes: available))
  }

  // MARK: Snooze

  @Test func untilTomorrowEndsAtNextLocalMidnight() {
    let lateEvening = calendar.date(
      from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 30))!
    let record = SnoozeOption.untilTomorrow.record(
      kind: .lowDiskSpace, discriminator: "home", now: lateEvening, calendar: calendar)
    let midnight = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
    #expect(record.isActive(at: midnight.addingTimeInterval(-1)))
    #expect(!record.isActive(at: midnight))
  }

  @Test func untilTomorrowAcrossDSTChange() {
    // 2026-11-01 is the US fall-back day; the next midnight is 25 hours after the previous one.
    let morning = calendar.date(
      from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30))!
    let record = SnoozeOption.untilTomorrow.record(
      kind: .trashSize, discriminator: "home", now: morning, calendar: calendar)
    let nextMidnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
    #expect(record.isActive(at: nextMidnight.addingTimeInterval(-1)))
    #expect(!record.isActive(at: nextMidnight))
    #expect(record.interval == nextMidnight.timeIntervalSince(morning))
  }

  @Test func fixedSnoozesAndForever() {
    let day = SnoozeOption.day.record(kind: .restart, discriminator: "home", now: now, calendar: calendar)
    #expect(day.interval == 86_400)
    #expect(SnoozeOption.threeDays.record(kind: .restart, discriminator: "h", now: now, calendar: calendar).interval == 259_200)
    #expect(SnoozeOption.week.record(kind: .restart, discriminator: "h", now: now, calendar: calendar).interval == 604_800)
    let forever = SnoozeOption.forever.record(kind: .restart, discriminator: "home", now: now, calendar: calendar)
    #expect(forever.interval == nil)
    #expect(forever.isActive(at: now.addingTimeInterval(100 * 365 * 86_400)))
  }

  @Test func storeAddsReplacesAndResets() throws {
    let defaults = UserDefaults(suiteName: "CleanScopeAlertTests-\(UUID().uuidString)")!
    let store = AlertIgnoreStore(defaults: defaults)
    try store.add(SnoozeOption.day.record(kind: .lowDiskSpace, discriminator: "home", now: now, calendar: calendar))
    try store.add(SnoozeOption.week.record(kind: .lowDiskSpace, discriminator: "home", now: now, calendar: calendar))
    #expect(try store.load().count == 1)
    #expect(try store.load().first?.interval == 604_800)
    try store.reset()
    #expect(try store.load().isEmpty)
  }

  // MARK: Low disk

  @Test func lowDiskFiresOnceAndUsesHysteresis() {
    var state = AlertState()
    let thresholds = AlertThresholds()  // max(10 GB, 5% of 1 TB = 50 GB) = 50 GB trigger
    func step(_ available: Int64) -> [AlertPayload] {
      let output = AlertEvaluator.evaluate(
        inputs: inputs(available: available), thresholds: thresholds, ignores: [], now: now,
        previous: state)
      state = output.next
      return output.alerts
    }
    #expect(step(60 * gb).isEmpty)
    let fired = step(49 * gb)
    #expect(fired.map(\.kind) == [.lowDiskSpace])
    #expect(fired.first?.title == "Your Mac is getting full")
    #expect(fired.first?.body == "49 GB available. A scan can show what's using space.")
    #expect(step(48 * gb).isEmpty)  // no repeat while it holds
    #expect(step(51 * gb).isEmpty)  // within hysteresis band, still active
    #expect(step(45 * gb).isEmpty)
    #expect(step(53 * gb).isEmpty)  // clears above trigger + 2 GB
    #expect(step(40 * gb).map(\.kind) == [.lowDiskSpace])  // new crossing fires again
  }

  @Test func lowDiskTriggerUsesTenGigabyteFloor() {
    let output = AlertEvaluator.evaluate(
      inputs: inputs(available: 9 * gb, total: 100 * gb), thresholds: AlertThresholds(),
      ignores: [], now: now, previous: AlertState())
    #expect(output.alerts.map(\.kind) == [.lowDiskSpace])
  }

  @Test func snoozedKindIsSuppressed() {
    let ignore = SnoozeOption.day.record(
      kind: .lowDiskSpace, discriminator: "home", now: now, calendar: calendar)
    let output = AlertEvaluator.evaluate(
      inputs: inputs(available: 1 * gb), thresholds: AlertThresholds(), ignores: [ignore],
      now: now, previous: AlertState())
    #expect(output.alerts.isEmpty)
    let later = AlertEvaluator.evaluate(
      inputs: inputs(available: 1 * gb), thresholds: AlertThresholds(), ignores: [ignore],
      now: now.addingTimeInterval(90_000), previous: output.next)
    #expect(later.alerts.map(\.kind) == [.lowDiskSpace])
  }

  @Test func disabledKindNeverFires() {
    var input = inputs(available: 1 * gb)
    input.enabled = []
    #expect(
      AlertEvaluator.evaluate(
        inputs: input, thresholds: AlertThresholds(), ignores: [], now: now,
        previous: AlertState()
      ).alerts.isEmpty)
  }

  // MARK: Other kinds

  @Test func otherAlertKinds() {
    var input = inputs(available: 500 * gb)
    input.trashBytes = 6 * gb
    input.externalVolumes = [
      VolumeStatus(uuid: "U1", name: "Backup", totalBytes: 100 * gb, availableBytes: 9 * gb),
      VolumeStatus(uuid: "U2", name: "Photos", totalBytes: 100 * gb, availableBytes: 50 * gb),
    ]
    input.uptime = 15 * 86_400
    input.bluetooth = [
      BluetoothBattery(name: "Magic Mouse", percent: 12),
      BluetoothBattery(name: "Keyboard", percent: 80),
    ]
    input.memoryPressureLevel = 2
    input.pressureSince = now.addingTimeInterval(-121)

    let alerts = AlertEvaluator.evaluate(
      inputs: input, thresholds: AlertThresholds(), ignores: [], now: now,
      previous: AlertState()
    ).alerts
    let keys = Set(alerts.map(\.key))
    #expect(
      keys == [
        "trashSize|home", "externalDriveLow|U1", "restart|home", "bluetoothBattery|Magic Mouse",
        "memoryPressure|home",
      ])
    #expect(alerts.first { $0.kind == .trashSize }?.title == "Trash is holding 6 GB")
    #expect(alerts.first { $0.kind == .externalDriveLow }?.title == "Backup is almost full")
    #expect(alerts.first { $0.kind == .restart }?.title == "It's been 15 days since your last restart")
  }

  @Test func shortMemoryPressureDoesNotFire() {
    var input = inputs(available: 500 * gb)
    input.memoryPressureLevel = 4
    input.pressureSince = now.addingTimeInterval(-60)
    #expect(
      AlertEvaluator.evaluate(
        inputs: input, thresholds: AlertThresholds(), ignores: [], now: now,
        previous: AlertState()
      ).alerts.isEmpty)
  }
}
