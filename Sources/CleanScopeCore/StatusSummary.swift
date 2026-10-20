import Foundation

public struct StatusInputs: Sendable {
  public var disk: DiskSnapshot?
  public var trashBytes: Int64?
  public var threatsFound: Int?
  public var lastProtectionScan: Date?
  /// Battery health fraction, or nil on Macs without a battery.
  public var batteryHealth: Double?
  public var memoryPressure: Int?

  public init(
    disk: DiskSnapshot?, trashBytes: Int64?, threatsFound: Int?, lastProtectionScan: Date?,
    batteryHealth: Double?, memoryPressure: Int?
  ) {
    self.disk = disk
    self.trashBytes = trashBytes
    self.threatsFound = threatsFound
    self.lastProtectionScan = lastProtectionScan
    self.batteryHealth = batteryHealth
    self.memoryPressure = memoryPressure
  }
}

public struct StatusCheck: Identifiable, Equatable, Sendable {
  public enum Target: String, Sendable {
    case storage, trash, protection, battery, memory
  }

  public var id: String { title }
  public var title: String
  public var isGood: Bool
  public var reason: String
  public var weight: Int
  public var target: Target
}

/// Five named checks and a weighted score with a visible breakdown. Checks without data (for
/// example Battery on a desktop Mac) are left out, and the score is scaled to the rest.
public struct StatusSummary: Equatable, Sendable {
  public var checks: [StatusCheck]
  public var score: Int

  public static let weights = (disk: 35, protection: 25, trash: 10, battery: 15, memory: 15)

  public static func evaluate(
    _ inputs: StatusInputs, thresholds: AlertThresholds = AlertThresholds(), now: Date = Date()
  ) -> StatusSummary {
    var checks: [StatusCheck] = []

    if let disk = inputs.disk, disk.totalBytes > 0 {
      let trigger = max(
        thresholds.lowDiskBytes, Int64(Double(disk.totalBytes) * thresholds.lowDiskFraction))
      checks.append(
        StatusCheck(
          title: "Disk space", isGood: disk.availableBytes >= trigger,
          reason: "\(ByteCount.string(disk.availableBytes)) available.",
          weight: weights.disk, target: .storage))
    }

    if let trash = inputs.trashBytes {
      let good = trash <= thresholds.trashBytes
      checks.append(
        StatusCheck(
          title: "Trash", isGood: good,
          reason: good
            ? "Trash is holding \(ByteCount.string(trash))."
            : "Trash is holding \(ByteCount.string(trash)). Space is freed when it's emptied.",
          weight: weights.trash, target: .trash))
    }

    let protection: (Bool, String)
    if let threats = inputs.threatsFound, threats > 0 {
      protection = (false, "\(threats) item\(threats == 1 ? "" : "s") need\(threats == 1 ? "s" : "") your review.")
    } else if let last = inputs.lastProtectionScan {
      let days = Int(now.timeIntervalSince(last) / 86_400)
      protection =
        days > 30
        ? (false, "Last protection scan was \(days) days ago.")
        : (true, "No known threats found.")
    } else {
      protection = (false, "No protection scan yet.")
    }
    checks.append(
      StatusCheck(
        title: "Protection", isGood: protection.0, reason: protection.1,
        weight: weights.protection, target: .protection))

    if let health = inputs.batteryHealth {
      let percent = Int((health * 100).rounded())
      checks.append(
        StatusCheck(
          title: "Battery", isGood: health >= 0.70,
          reason: health >= 0.70
            ? "Battery holds \(percent)% of its original charge."
            : "Battery holds \(percent)% of its original charge. It may need service.",
          weight: weights.battery, target: .battery))
    }

    if let pressure = inputs.memoryPressure {
      checks.append(
        StatusCheck(
          title: "Memory", isGood: pressure < 2,
          reason: pressure < 2 ? "Memory pressure is normal." : "Memory pressure is elevated.",
          weight: weights.memory, target: .memory))
    }

    let order = ["Disk space", "Trash", "Protection", "Battery", "Memory"]
    checks.sort { order.firstIndex(of: $0.title)! < order.firstIndex(of: $1.title)! }
    let total = checks.reduce(0) { $0 + $1.weight }
    let good = checks.filter(\.isGood).reduce(0) { $0 + $1.weight }
    let score = total == 0 ? 100 : Int((Double(good) / Double(total) * 100).rounded())
    return StatusSummary(checks: checks, score: score)
  }
}
