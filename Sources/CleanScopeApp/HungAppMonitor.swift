import AppKit
import ApplicationServices
import CleanScopeCore

/// Finds apps that stop responding, using the Accessibility API: an app that fails to answer
/// two 1-second queries in a row (polled every 5 seconds) is listed as not responding.
@MainActor
final class HungAppMonitor: ObservableObject {
  struct HungApp: Identifiable, Equatable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
  }

  @Published private(set) var hungApps: [HungApp] = []
  @Published private(set) var isTrusted = AXIsProcessTrusted()

  private let notifications: NotificationCoordinator
  private var detector = HungAppDetector()
  private var timer: Timer?
  private var isPolling = false

  init(notifications: NotificationCoordinator) {
    self.notifications = notifications
  }

  /// Asks for Accessibility access (only when the user turns the feature on) and starts polling.
  func setEnabled(_ enabled: Bool, prompt: Bool) {
    timer?.invalidate()
    timer = nil
    hungApps = []
    guard enabled else { return }
    if prompt {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      isTrusted = AXIsProcessTrustedWithOptions(options)
    } else {
      isTrusted = AXIsProcessTrusted()
    }
    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.poll() }
    }
  }

  func forceQuit(_ app: HungApp) {
    NSRunningApplication(processIdentifier: app.pid)?.forceTerminate()
    hungApps.removeAll { $0.pid == app.pid }
  }

  private func poll() async {
    isTrusted = AXIsProcessTrusted()
    guard isTrusted, !isPolling else { return }
    isPolling = true
    defer { isPolling = false }

    let apps = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
      .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "App") }
    let responses = await Task.detached(priority: .utility) {
      apps.map { app -> (Int32, String, Bool) in
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, 1.0)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return (app.pid, app.name, error != .cannotComplete)
      }
    }.value

    detector.forget(except: Set(responses.map(\.0)))
    var hung: [HungApp] = []
    for (pid, name, responded) in responses {
      if detector.record(pid: pid, responded: responded) {
        notifications.post(
          AlertPayload(
            kind: .hungApp, discriminator: String(pid), title: "\(name) is not responding",
            body: "You can wait or force it to quit. Unsaved changes in it may be lost."),
          userInfo: ["pid": String(pid)])
      }
      if detector.isHung(pid) { hung.append(HungApp(pid: pid, name: name)) }
    }
    hungApps = hung
  }
}
