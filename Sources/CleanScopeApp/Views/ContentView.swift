import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    NavigationSplitView {
      SidebarView()
    } detail: {
      switch model.destination ?? .dashboard {
      case .dashboard:
        DashboardView()
      case .safeCleanup:
        ResultsView(title: "Safe Cleanup", filter: { $0.category == .safeToDelete })
      case .largeFiles:
        ResultsView(
          title: "Large Files", filter: { $0.sizeBytes >= model.settings.largeFileThresholdBytes })
      case .hiddenFolders:
        ResultsView(title: "Hidden Folders", filter: { $0.isHidden })
      case .developerFiles:
        ResultsView(title: "Developer Files", filter: { $0.ownerTool != nil })
      case .appSupport:
        ResultsView(
          title: "App Support",
          filter: {
            $0.normalizedPath.localizedCaseInsensitiveContains("/Library/Application Support/")
          })
      case .downloads:
        ResultsView(
          title: "Downloads",
          filter: {
            $0.normalizedPath.localizedCaseInsensitiveContains("/Downloads/")
          })
      case .trash:
        ResultsView(
          title: "Trash",
          filter: {
            $0.normalizedPath.localizedCaseInsensitiveContains("/.Trash/")
          })
      case .cleanupHistory:
        CleanupReportView()
      case .settings:
        SettingsView()
      }
    }
  }
}
