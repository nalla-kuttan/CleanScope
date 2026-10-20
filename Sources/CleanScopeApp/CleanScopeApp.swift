import CleanScopeCore
import SwiftUI

@main
struct CleanScopeApp: App {
  @StateObject private var model = AppModel()
  private let previewColorScheme: ColorScheme? =
    ProcessInfo.processInfo.arguments.contains("--dark-preview") ? .dark : nil

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .preferredColorScheme(previewColorScheme)
        .frame(minWidth: 1040, minHeight: 680)
        .task { await model.applyLaunchArguments(ProcessInfo.processInfo.arguments) }
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
        .preferredColorScheme(previewColorScheme)
        .frame(width: 520)
    }
  }
}
