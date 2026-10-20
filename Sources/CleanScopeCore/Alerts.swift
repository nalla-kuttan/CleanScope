import Foundation

public enum AlertKind: String, Codable, CaseIterable, Sendable {
  case lowDiskSpace
  case trashSize
  case externalDriveLow
  case memoryPressure
  case restart
  case bluetoothBattery
  case hungApp
  case malwareDetected
}

/// Discriminator for alerts that are not tied to a volume or device.
public let homeAlertDiscriminator = "home"

public struct VolumeStatus: Equatable, Sendable {
  public var uuid: String
  public var name: String
  public var totalBytes: Int64
  public var availableBytes: Int64
  public var url: URL?

  public init(uuid: String, name: String, totalBytes: Int64, availableBytes: Int64, url: URL? = nil)
  {
    self.uuid = uuid
    self.name = name
    self.totalBytes = totalBytes
    self.availableBytes = availableBytes
    self.url = url
  }
}

public struct BluetoothBattery: Equatable, Sendable {
  public var name: String
  public var percent: Int

  public init(name: String, percent: Int) {
    self.name = name
    self.percent = percent
  }
}

public struct AlertThresholds: Equatable, Sendable {
  public var lowDiskBytes: Int64 = 10_000_000_000
  public var lowDiskFraction: Double = 0.05
  public var lowDiskClearMarginBytes: Int64 = 2_000_000_000
  public var trashBytes: Int64 = 5_000_000_000
  public var externalFreeFraction: Double = 0.10
  public var restartUptime: TimeInterval = 14 * 86_400
  public var bluetoothPercent: Int = 15
  public var memoryPressureDuration: TimeInterval = 120

  public init() {}

  public init(settings: Settings) {
    lowDiskBytes = settings.lowDiskThresholdBytes
    trashBytes = settings.trashThresholdBytes
  }
}

public struct AlertInputs: Sendable {
  public var disk: DiskSnapshot?
  public var trashBytes: Int64?
  public var externalVolumes: [VolumeStatus] = []
  public var memoryPressureLevel: Int?
  /// When memory pressure first reached level 2 or higher in the current episode.
  public var pressureSince: Date?
  public var uptime: TimeInterval?
  public var bluetooth: [BluetoothBattery] = []
  public var enabled: Set<AlertKind> = Set(AlertKind.allCases)

  public init(disk: DiskSnapshot? = nil) {
    self.disk = disk
  }
}

/// Alerts currently showing, keyed by `kind|discriminator`, so each crossing fires once.
public struct AlertState: Codable, Equatable, Sendable {
  public var active: Set<String> = []
  public init() {}
}

public struct AlertPayload: Equatable, Sendable {
  public var kind: AlertKind
  public var discriminator: String
  public var title: String
  public var body: String
  public var key: String { "\(kind.rawValue)|\(discriminator)" }

  public init(kind: AlertKind, discriminator: String, title: String, body: String) {
    self.kind = kind
    self.discriminator = discriminator
    self.title = title
    self.body = body
  }
}

public enum AlertEvaluator {
  /// Returns the alerts to post now and the state to pass in next time. An alert fires when its
  /// condition starts to hold, never repeats while it keeps holding, and is suppressed while
  /// snoozed (it fires once the snooze ends if the condition still holds).
  public static func evaluate(
    inputs: AlertInputs,
    thresholds: AlertThresholds,
    ignores: [AlertIgnoreRecord],
    now: Date,
    previous: AlertState
  ) -> (alerts: [AlertPayload], next: AlertState) {
    var holding: [AlertPayload] = []

    if inputs.enabled.contains(.lowDiskSpace), let disk = inputs.disk, disk.totalBytes > 0 {
      let trigger = max(
        thresholds.lowDiskBytes, Int64(Double(disk.totalBytes) * thresholds.lowDiskFraction))
      let key = "\(AlertKind.lowDiskSpace.rawValue)|\(homeAlertDiscriminator)"
      let wasActive = previous.active.contains(key)
      let limit = wasActive ? trigger + thresholds.lowDiskClearMarginBytes : trigger
      if disk.availableBytes < limit {
        holding.append(
          AlertPayload(
            kind: .lowDiskSpace, discriminator: homeAlertDiscriminator,
            title: "Your Mac is getting full",
            body: "\(ByteCount.string(disk.availableBytes)) available. A scan can show what's using space."
          ))
      }
    }

    if inputs.enabled.contains(.trashSize), let trash = inputs.trashBytes,
      trash > thresholds.trashBytes
    {
      holding.append(
        AlertPayload(
          kind: .trashSize, discriminator: homeAlertDiscriminator,
          title: "Trash is holding \(ByteCount.string(trash))",
          body: "Space is freed when the Trash is emptied."))
    }

    if inputs.enabled.contains(.externalDriveLow) {
      for volume in inputs.externalVolumes where volume.totalBytes > 0 {
        let fraction = Double(volume.availableBytes) / Double(volume.totalBytes)
        if fraction < thresholds.externalFreeFraction {
          holding.append(
            AlertPayload(
              kind: .externalDriveLow, discriminator: volume.uuid,
              title: "\(volume.name) is almost full",
              body: "\(ByteCount.string(volume.availableBytes)) available."))
        }
      }
    }

    if inputs.enabled.contains(.memoryPressure), let level = inputs.memoryPressureLevel,
      level >= 2, let since = inputs.pressureSince,
      now.timeIntervalSince(since) >= thresholds.memoryPressureDuration
    {
      holding.append(
        AlertPayload(
          kind: .memoryPressure, discriminator: homeAlertDiscriminator,
          title: "Memory is under pressure",
          body: "Apps may feel slower. The Memory view shows what's using it."))
    }

    if inputs.enabled.contains(.restart), let uptime = inputs.uptime,
      uptime > thresholds.restartUptime
    {
      let days = Int(uptime / 86_400)
      holding.append(
        AlertPayload(
          kind: .restart, discriminator: homeAlertDiscriminator,
          title: "It's been \(days) days since your last restart",
          body: "Restarting clears memory and finishes pending updates."))
    }

    if inputs.enabled.contains(.bluetoothBattery) {
      for device in inputs.bluetooth where device.percent < thresholds.bluetoothPercent {
        holding.append(
          AlertPayload(
            kind: .bluetoothBattery, discriminator: device.name,
            title: "\(device.name) battery is low",
            body: "\(device.percent)% left. Time to charge it."))
      }
    }

    var next = AlertState()
    var alerts: [AlertPayload] = []
    for payload in holding {
      let snoozed = ignores.contains {
        $0.kind == payload.kind && $0.discriminator == payload.discriminator && $0.isActive(at: now)
      }
      if snoozed { continue }
      next.active.insert(payload.key)
      if !previous.active.contains(payload.key) {
        alerts.append(payload)
      }
    }
    return (alerts, next)
  }
}
