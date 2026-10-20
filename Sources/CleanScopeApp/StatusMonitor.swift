import AppKit
import CleanScopeCore
import Foundation

/// Refreshes free space, Trash size and external drives, and posts alerts when they cross
/// their thresholds. Runs every 5 minutes while the menu bar extra is shown, every 30 minutes
/// otherwise, and immediately when a drive mounts or unmounts.
@MainActor
final class StatusMonitor: ObservableObject {
  @Published private(set) var disk: DiskSnapshot?
  @Published private(set) var trashBytes: Int64?
  @Published private(set) var trashNeedsFullDiskAccess = false
  @Published private(set) var externalVolumes: [VolumeStatus] = []
  @Published private(set) var lastRefresh: Date?

  /// Extra inputs (memory, uptime, Bluetooth) filled in by the system monitors.
  var supplementalInputs: () -> AlertInputs = { AlertInputs() }

  private let notifications: NotificationCoordinator
  private let ignoreStore: AlertIgnoreStore
  private var settings: () -> CleanScopeCore.Settings
  private var alertState = AlertState()
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private var knownVolumeUUIDs: Set<String> = []

  init(
    notifications: NotificationCoordinator,
    ignoreStore: AlertIgnoreStore = AlertIgnoreStore(),
    settings: @escaping () -> CleanScopeCore.Settings
  ) {
    self.notifications = notifications
    self.ignoreStore = ignoreStore
    self.settings = settings
  }

  func start() {
    guard observers.isEmpty else { return }
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
      observers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in self?.refresh() }
        })
    }
    knownVolumeUUIDs = Set(VolumeService.externalVolumes().map(\.uuid))
    reschedule()
    refresh()
  }

  /// Call when the menu bar extra is shown or hidden.
  func reschedule() {
    timer?.invalidate()
    let interval: TimeInterval = settings().showMenuBarExtra ? 300 : 1_800
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func refresh() {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let values = try? home.resourceValues(forKeys: [
      .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ])
    disk = DiskSnapshot(
      totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
      availableBytes: values?.volumeAvailableCapacityForImportantUsage ?? 0)

    do {
      trashBytes = try TrashService.size()
      trashNeedsFullDiskAccess = false
    } catch {
      trashBytes = nil
      trashNeedsFullDiskAccess = true
    }

    externalVolumes = VolumeService.externalVolumes()
    announceNewlyMountedVolumes()
    lastRefresh = Date()
    evaluateAlerts()
  }

  func evaluateAlerts() {
    let current = settings()
    var inputs = supplementalInputs()
    inputs.disk = disk
    inputs.trashBytes = trashBytes
    inputs.externalVolumes = externalVolumes
    var enabled = Set<AlertKind>()
    if current.lowDiskAlertEnabled { enabled.insert(.lowDiskSpace) }
    if current.trashAlertEnabled && !trashNeedsFullDiskAccess { enabled.insert(.trashSize) }
    if current.externalDriveAlertEnabled { enabled.insert(.externalDriveLow) }
    if current.memoryAlertEnabled { enabled.insert(.memoryPressure) }
    if current.restartReminderEnabled { enabled.insert(.restart) }
    if current.bluetoothBatteryAlertEnabled { enabled.insert(.bluetoothBattery) }
    inputs.enabled = enabled

    let output = AlertEvaluator.evaluate(
      inputs: inputs,
      thresholds: AlertThresholds(settings: current),
      ignores: (try? ignoreStore.load()) ?? [],
      now: Date(),
      previous: alertState)
    alertState = output.next
    for alert in output.alerts {
      var extra: [String: String] = [:]
      if alert.kind == .externalDriveLow,
        let url = externalVolumes.first(where: { $0.uuid == alert.discriminator })?.url
      {
        extra["volumePath"] = url.path
      }
      notifications.post(alert, userInfo: extra)
    }
  }

  func snooze(_ kind: AlertKind, discriminator: String, option: SnoozeOption) {
    try? ignoreStore.add(option.record(kind: kind, discriminator: discriminator))
  }

  func resetSnoozes() {
    try? ignoreStore.reset()
    alertState = AlertState()
  }

  private func announceNewlyMountedVolumes() {
    let current = Set(externalVolumes.map(\.uuid))
    defer { knownVolumeUUIDs = current }
    guard settings().externalDriveMountedNotice else { return }
    for volume in externalVolumes where !knownVolumeUUIDs.contains(volume.uuid) {
      var extra: [String: String] = [:]
      if let url = volume.url { extra["volumePath"] = url.path }
      notifications.post(
        AlertPayload(
          kind: .externalDriveLow, discriminator: "mounted-\(volume.uuid)",
          title: "\(volume.name) connected",
          body: "\(ByteCount.string(volume.availableBytes)) available."),
        userInfo: extra)
    }
  }
}
