import CleanScopeCore
import Foundation
import UserNotifications

/// Posts CleanScope's alerts as macOS notifications and routes their actions back to the app.
@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
  enum Action: Equatable {
    case scan
    case openTrash
    case scanDrive(volumePath: String)
    case open(AppModel.Destination)
    case forceQuit(pid: Int32)
    case snooze(AlertKind, discriminator: String, SnoozeOption)
  }

  @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
  var onAction: ((Action) -> Void)?

  /// UserNotifications needs a real app bundle; the bare test binary has none.
  private let isAvailable = Bundle.main.bundleIdentifier != nil
  private var center: UNUserNotificationCenter? {
    isAvailable ? UNUserNotificationCenter.current() : nil
  }

  override init() {
    super.init()
    guard let center else { return }
    center.delegate = self
    center.setNotificationCategories(Self.categories)
    Task { await refreshAuthorization() }
  }

  func refreshAuthorization() async {
    guard let center else { return }
    authorization = await center.notificationSettings().authorizationStatus
  }

  /// Called when the user turns an alert on; never at launch.
  func requestAuthorizationIfNeeded() async {
    guard let center else { return }
    await refreshAuthorization()
    guard authorization == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
    await refreshAuthorization()
  }

  func post(_ alert: AlertPayload, userInfo extra: [String: String] = [:]) {
    guard let center, authorization == .authorized || authorization == .provisional else { return }
    let content = UNMutableNotificationContent()
    content.title = alert.title
    content.body = alert.body
    content.categoryIdentifier = alert.kind.rawValue
    var info: [String: String] = [
      "kind": alert.kind.rawValue, "discriminator": alert.discriminator,
    ]
    info.merge(extra) { _, new in new }
    content.userInfo = info
    let request = UNNotificationRequest(identifier: alert.key, content: content, trigger: nil)
    center.add(request)
  }

  // MARK: Categories

  private static func snoozeActions() -> [UNNotificationAction] {
    SnoozeOption.allCases.map {
      UNNotificationAction(identifier: "snooze.\($0.rawValue)", title: "Snooze \($0.title.lowercased())")
    }
  }

  private static var categories: Set<UNNotificationCategory> {
    func category(_ kind: AlertKind, _ primary: [UNNotificationAction]) -> UNNotificationCategory {
      UNNotificationCategory(
        identifier: kind.rawValue, actions: primary + snoozeActions(), intentIdentifiers: [])
    }
    return [
      category(.lowDiskSpace, [UNNotificationAction(identifier: "scan", title: "Scan now")]),
      category(.trashSize, [UNNotificationAction(identifier: "openTrash", title: "Open Trash")]),
      category(
        .externalDriveLow, [UNNotificationAction(identifier: "scanDrive", title: "Scan drive")]),
      category(
        .memoryPressure, [UNNotificationAction(identifier: "openMemory", title: "Show Memory")]),
      category(.restart, []),
      category(.bluetoothBattery, []),
      category(
        .hungApp,
        [
          UNNotificationAction(
            identifier: "forceQuit", title: "Force Quit", options: [.destructive]),
          UNNotificationAction(identifier: "wait", title: "Wait"),
        ]),
      category(
        .malwareDetected,
        [UNNotificationAction(identifier: "openProtection", title: "Review in CleanScope")]),
    ]
  }

  // MARK: Delegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let info = response.notification.request.content.userInfo
    let identifier = response.actionIdentifier
    let kind = (info["kind"] as? String).flatMap(AlertKind.init(rawValue:))
    let discriminator = info["discriminator"] as? String ?? homeAlertDiscriminator
    let volumePath = info["volumePath"] as? String
    let pid = (info["pid"] as? String).flatMap { Int32($0) }

    let action: Action?
    if identifier.hasPrefix("snooze."), let kind,
      let option = SnoozeOption(rawValue: String(identifier.dropFirst("snooze.".count)))
    {
      action = .snooze(kind, discriminator: discriminator, option)
    } else {
      switch identifier {
      case "scan": action = .scan
      case "openTrash": action = .openTrash
      case "scanDrive": action = volumePath.map { .scanDrive(volumePath: $0) }
      case "openMemory": action = .open(AppModel.Destination(rawValue: "Memory") ?? .dashboard)
      case "openProtection":
        action = .open(AppModel.Destination(rawValue: "Protection") ?? .dashboard)
      case "forceQuit": action = pid.map { .forceQuit(pid: $0) }
      case UNNotificationDefaultActionIdentifier:
        action =
          kind == .malwareDetected
          ? .open(AppModel.Destination(rawValue: "Protection") ?? .dashboard) : .open(.dashboard)
      default: action = nil
      }
    }
    guard let action else { return }
    await MainActor.run { self.onAction?(action) }
  }
}
