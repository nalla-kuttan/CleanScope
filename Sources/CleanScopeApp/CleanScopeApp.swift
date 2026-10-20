import CleanScopeCore
import SwiftUI

@main
struct CleanScopeApp: App {
  @StateObject private var model = CleanScopeApp.makeModel()
  private let previewColorScheme: ColorScheme? =
    ProcessInfo.processInfo.arguments.contains("--dark-preview") ? .dark : nil

  private static func makeModel() -> AppModel {
    #if DEBUG
      if DebugSnapshot.startsEmpty {
        let scratch = FileManager.default.temporaryDirectory
          .appendingPathComponent("CleanScopeSnapshot-\(UUID().uuidString)")
        return AppModel(
          repository: ScanRepository(fileURL: scratch.appendingPathComponent("latest.json")),
          exclusionStore: ExclusionStore(fileURL: scratch.appendingPathComponent("exclusions.json")))
      }
    #endif
    return AppModel()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .tint(BrandTheme.accent)
        .preferredColorScheme(previewColorScheme)
        .frame(minWidth: 820, minHeight: 560)
    }
    .commands {
      SidebarCommands()
      CommandGroup(after: .newItem) {
        Button("Start Scan") {
          Task { await model.startScan() }
        }
        .disabled(model.isScanning)
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
        .tint(BrandTheme.accent)
        .preferredColorScheme(previewColorScheme)
        .frame(width: 520, height: 560)
    }
  }
}
