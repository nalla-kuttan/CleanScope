import Darwin
import Foundation
import IOKit
import IOKit.ps

// MARK: - CPU

public struct CoreTicks: Equatable, Sendable {
  public var user: UInt64
  public var system: UInt64
  public var idle: UInt64
  public var nice: UInt64

  public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
    self.user = user
    self.system = system
    self.idle = idle
    self.nice = nice
  }
}

public enum CPULoad {
  /// Per-core tick counters from `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
  public static func sample() -> [CoreTicks] {
    var count: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    guard
      host_processor_info(
        mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
      let info
    else { return [] }
    defer {
      vm_deallocate(
        mach_task_self_, vm_address_t(bitPattern: info),
        vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
    }
    let states = Int(CPU_STATE_MAX)
    return (0..<Int(count)).map { core in
      func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * states + Int(state)])) }
      return CoreTicks(
        user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM), idle: tick(CPU_STATE_IDLE),
        nice: tick(CPU_STATE_NICE))
    }
  }

  /// Busy fraction (0…1) per core and overall, from two samples.
  public static func usage(previous: [CoreTicks], current: [CoreTicks]) -> (
    total: Double, perCore: [Double]
  ) {
    guard previous.count == current.count, !current.isEmpty else { return (0, []) }
    var busyTotal: UInt64 = 0
    var allTotal: UInt64 = 0
    let perCore = zip(previous, current).map { old, new -> Double in
      let busy =
        (new.user &- old.user) &+ (new.system &- old.system) &+ (new.nice &- old.nice)
      let all = busy &+ (new.idle &- old.idle)
      busyTotal &+= busy
      allTotal &+= all
      return all == 0 ? 0 : Double(busy) / Double(all)
    }
    return (allTotal == 0 ? 0 : Double(busyTotal) / Double(allTotal), perCore)
  }
}

// MARK: - Network

public struct InterfaceCounters: Equatable, Sendable {
  public var received: UInt64
  public var sent: UInt64

  public init(received: UInt64, sent: UInt64) {
    self.received = received
    self.sent = sent
  }
}

public enum NetworkThroughput {
  /// Byte counters summed over every interface except loopback.
  public static func sample() -> InterfaceCounters {
    var counters = InterfaceCounters(received: 0, sent: 0)
    var addresses: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addresses) == 0, let first = addresses else { return counters }
    defer { freeifaddrs(addresses) }
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = pointer?.pointee {
      defer { pointer = entry.ifa_next }
      guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
        let data = entry.ifa_data
      else { continue }
      let name = String(cString: entry.ifa_name)
      guard !name.hasPrefix("lo") else { continue }
      let stats = data.assumingMemoryBound(to: if_data.self).pointee
      counters.received += UInt64(stats.ifi_ibytes)
      counters.sent += UInt64(stats.ifi_obytes)
    }
    return counters
  }

  /// Bytes per second between two samples. A counter that went backwards counts as 0.
  public static func rate(previous: InterfaceCounters, current: InterfaceCounters, interval: Double)
    -> (receivedPerSecond: Double, sentPerSecond: Double)
  {
    guard interval > 0 else { return (0, 0) }
    let received = current.received >= previous.received ? current.received - previous.received : 0
    let sent = current.sent >= previous.sent ? current.sent - previous.sent : 0
    return (Double(received) / interval, Double(sent) / interval)
  }
}

// MARK: - Battery

public struct BatteryCharge: Equatable, Sendable {
  public var percent: Int
  public var isCharging: Bool
  /// Minutes to empty or to full, when macOS has an estimate.
  public var minutesRemaining: Int?

  public static func read() -> BatteryCharge? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
      else { continue }
      let charging = description[kIOPSIsChargingKey] as? Bool ?? false
      let minutes =
        (charging ? description[kIOPSTimeToFullChargeKey] : description[kIOPSTimeToEmptyKey])
        as? Int
      return BatteryCharge(
        percent: current * 100 / max, isCharging: charging,
        minutesRemaining: (minutes ?? -1) >= 0 ? minutes : nil)
    }
    return nil
  }
}

public struct BatteryHealth: Equatable, Sendable {
  public var cycleCount: Int?
  public var designCycleCount: Int?
  public var healthFraction: Double
  /// Degrees Celsius, when reported.
  public var temperature: Double?

  public var isCritical: Bool { healthFraction < 0.70 }

  /// Reads `AppleSmartBattery`. Apple Silicon Macs report `NominalChargeCapacity` instead of
  /// `AppleRawMaxCapacity`, so either is used against `DesignCapacity`. Recent macOS versions
  /// keep the capacities in a nested `BatteryData` dictionary.
  public static func from(registry topLevel: [String: Any]) -> BatteryHealth? {
    var registry = topLevel
    if let nested = topLevel["BatteryData"] as? [String: Any] {
      registry.merge(nested) { top, _ in top }
    }
    guard let design = registry["DesignCapacity"] as? Int, design > 0,
      let full = (registry["AppleRawMaxCapacity"] as? Int)
        ?? (registry["NominalChargeCapacity"] as? Int)
    else { return nil }
    let temperature = (registry["Temperature"] as? Int).map { Double($0) / 100 }
    return BatteryHealth(
      cycleCount: registry["CycleCount"] as? Int,
      designCycleCount: registry["DesignCycleCount9C"] as? Int,
      healthFraction: Double(full) / Double(design),
      temperature: temperature)
  }

  public static func read() -> BatteryHealth? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let dictionary = properties?.takeRetainedValue() as? [String: Any]
    else { return nil }
    return from(registry: dictionary)
  }
}

public enum BluetoothBatteries {
  /// Connected accessories that report `BatteryPercent` (keyboards, mice, trackpads). Some
  /// headphones do not report it this way.
  public static func read() -> [BluetoothBattery] {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator)
        == KERN_SUCCESS
    else { return [] }
    defer { IOObjectRelease(iterator) }
    var devices: [BluetoothBattery] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      defer {
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
      }
      guard
        let percent = IORegistryEntryCreateCFProperty(
          service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
      else { continue }
      let name =
        IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? String ?? "Accessory"
      devices.append(BluetoothBattery(name: name, percent: percent))
    }
    return devices
  }
}

// MARK: - Uptime

public enum Uptime {
  public static func bootTime() -> Date? {
    var time = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return nil }
    return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
  }

  public static func since(bootTime: Date, now: Date = Date()) -> TimeInterval {
    max(0, now.timeIntervalSince(bootTime))
  }
}

// MARK: - Hung apps

/// Marks an app hung after two unanswered Accessibility queries in a row (about 10 seconds
/// with a 5-second poll).
public struct HungAppDetector: Sendable {
  private var misses: [Int32: Int] = [:]

  public init() {}

  /// Records one poll and returns true when the app has just become hung.
  public mutating func record(pid: Int32, responded: Bool) -> Bool {
    guard !responded else {
      misses[pid] = nil
      return false
    }
    let count = (misses[pid] ?? 0) + 1
    misses[pid] = count
    return count == 2
  }

  public func isHung(_ pid: Int32) -> Bool { (misses[pid] ?? 0) >= 2 }

  /// Drops apps that have quit.
  public mutating func forget(except running: Set<Int32>) {
    misses = misses.filter { running.contains($0.key) }
  }
}
