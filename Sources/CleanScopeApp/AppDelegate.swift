import AppKit
import CleanScopeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Keeps CleanScope running after its window closes while the menu bar extra is shown.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    let settings = (try? SettingsStore().load()) ?? .default
    return !settings.showMenuBarExtra
  }
}
