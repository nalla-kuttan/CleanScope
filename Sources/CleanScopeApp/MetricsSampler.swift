import CleanScopeCore
import Foundation

/// Samples CPU, memory, battery, network and disk every 2 seconds while the menu bar extra is
/// open, keeping 60 seconds of history for sparklines. Sampling stops when the menu closes.
@MainActor
final class MetricsSampler: ObservableObject {
  struct Series {
    var values: [Double] = []
    mutating func append(_ value: Double, limit: Int = 30) {
      values.append(value)
      if values.count > limit { values.removeFirst(values.count - limit) }
    }
  }

  @Published private(set) var cpu = Series()
  @Published private(set) var memory = Series()
  @Published private(set) var networkIn = Series()
  @Published private(set) var networkOut = Series()
  @Published private(set) var cpuTotal: Double?
  @Published private(set) var memorySnapshot: MemorySnapshot?
  @Published private(set) var battery: BatteryCharge?
  @Published private(set) var batteryHealth: BatteryHealth?
  @Published private(set) var network: (received: Double, sent: Double)?
  @Published private(set) var temperature: Double?

  var includesTemperature = false
  private var timer: Timer?
  private var previousTicks: [CoreTicks] = []
  private var previousCounters: InterfaceCounters?
  private var previousSampleDate: Date?

  func start() {
    guard timer == nil else { return }
    batteryHealth = BatteryHealth.read()
    sample()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.sample() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func sample() {
    let now = Date()
    let ticks = CPULoad.sample()
    if !previousTicks.isEmpty {
      let usage = CPULoad.usage(previous: previousTicks, current: ticks).total
      cpuTotal = usage
      cpu.append(usage)
    }
    previousTicks = ticks

    let snapshot = MemoryService.snapshot()
    memorySnapshot = snapshot
    if snapshot.totalBytes > 0 {
      memory.append(Double(snapshot.usedBytes) / Double(snapshot.totalBytes))
    }

    battery = BatteryCharge.read()

    let counters = NetworkThroughput.sample()
    if let previous = previousCounters, let last = previousSampleDate {
      let rate = NetworkThroughput.rate(
        previous: previous, current: counters, interval: now.timeIntervalSince(last))
      network = (rate.receivedPerSecond, rate.sentPerSecond)
      networkIn.append(rate.receivedPerSecond)
      networkOut.append(rate.sentPerSecond)
    }
    previousCounters = counters
    previousSampleDate = now

    temperature = includesTemperature ? SMCReader.cpuTemperature() : nil
  }
}
