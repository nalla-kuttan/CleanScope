import AppKit
import CleanScopeCore
import SwiftUI

/// The single gate for animation. Views read this instead of `accessibilityReduceMotion`.
@MainActor
final class MotionPolicy: ObservableObject {
  @Published private(set) var decision: MotionDecision

  var allowsAmbientMotion: Bool { decision.allowsAmbientMotion }
  var allowsTransitions: Bool { decision.allowsTransitions }

  private var windowVisible = true
  private var appActive = true
  private weak var window: NSWindow?
  private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

  /// `--reduce-motion` forces Reduce Motion on, read like `DebugSnapshot`'s flags (debug builds only).
  private static var forcesReduceMotion: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--reduce-motion")
    #else
      false
    #endif
  }

  init() {
    decision = MotionDecision(
      reduceMotion: true, lowPower: false, windowVisible: true, appActive: true)
    appActive = NSApp?.isActive ?? true
    refresh()

    observe(
      NSWorkspace.shared.notificationCenter,
      NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
    observe(.default, .NSProcessInfoPowerStateDidChange)
    observe(.default, NSApplication.didBecomeActiveNotification) { $0.appActive = true }
    observe(.default, NSApplication.didResignActiveNotification) { $0.appActive = false }
  }

  deinit {
    for entry in observers { entry.center.removeObserver(entry.token) }
  }

  /// `base` while transitions are allowed, otherwise `nil` (no animation).
  func animation(_ base: Animation = .easeOut(duration: 0.2)) -> Animation? {
    allowsTransitions ? base : nil
  }

  /// Tracks the window's occlusion so ambient motion pauses when it is hidden or covered.
  func attach(to window: NSWindow) {
    guard self.window !== window else { return }
    self.window = window
    observe(.default, NSWindow.didChangeOcclusionStateNotification, object: window) { policy in
      policy.windowVisible = window.occlusionState.contains(.visible)
    }
    windowVisible = window.occlusionState.contains(.visible)
    refresh()
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil,
    update: ((MotionPolicy) -> Void)? = nil
  ) {
    let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        update?(self)
        self.refresh()
      }
    }
    observers.append((center, token))
  }

  private func refresh() {
    let next = MotionDecision(
      reduceMotion: Self.forcesReduceMotion
        || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
      windowVisible: windowVisible,
      appActive: appActive)
    if next != decision { decision = next }
  }
}
