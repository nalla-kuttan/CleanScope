import CleanScopeCore
import SwiftUI

@main
struct CleanScopeApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .frame(minWidth: 1040, minHeight: 680)
    }
    .commands {
      CommandGroup(after: .appInfo) {
        Button("Start Limited Scan") {
          Task { await model.startScan(mode: .limited) }
        }
        .keyboardShortcut("r", modifiers: [.command])

        Button("Cancel Scan") {
          model.cancelScan()
        }
        .disabled(!model.isScanning)
        .keyboardShortcut(".", modifiers: [.command])
      }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
        .frame(width: 520)
    }
  }
}
