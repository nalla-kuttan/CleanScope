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
  /// The attached window's occlusion observer, kept apart so re-attaching replaces it.
  private var occlusionToken: NSObjectProtocol?

  /// `--reduce-motion` forces Reduce Motion on, read like `DebugSnapshot`'s flags (debug builds only).
  private static var forcesReduceMotion: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("--reduce-motion")
    #else
      false
    #endif
  }

  /// A snapshot run is launched from a shell: its window never becomes active and may not report
  /// itself visible, which would pause ambient motion in every capture. Debug builds treat the
  /// window as visible and the app as active.
  private static var isSnapshotRun: Bool {
    #if DEBUG
      DebugSnapshot.isActive
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
    if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
  }

  /// `base` while transitions are allowed, otherwise `nil` (no animation).
  func animation(_ base: Animation = .easeOut(duration: 0.2)) -> Animation? {
    allowsTransitions ? base : nil
  }

  /// Tracks the window's occlusion so ambient motion pauses when it is hidden or covered. A new
  /// window (the main window closed and reopened) replaces the previous one's observer, so a
  /// stale window can no longer pause motion; neither the policy nor the observer keeps the
  /// window alive.
  func attach(to window: NSWindow) {
    guard self.window !== window else { return }
    if let occlusionToken { NotificationCenter.default.removeObserver(occlusionToken) }
    self.window = window
    occlusionToken = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
    ) { [weak self, weak window] _ in
      MainActor.assumeIsolated {
        guard let self, let window, self.window === window else { return }
        self.windowVisible = window.occlusionState.contains(.visible)
        self.refresh()
      }
    }
    windowVisible = window.occlusionState.contains(.visible)
    refresh()
  }

  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name,
    update: ((MotionPolicy) -> Void)? = nil
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
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
      windowVisible: windowVisible || Self.isSnapshotRun,
      appActive: appActive || Self.isSnapshotRun)
    if next != decision { decision = next }
  }
}
