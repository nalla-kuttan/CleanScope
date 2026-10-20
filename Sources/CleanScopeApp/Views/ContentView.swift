import CleanScopeCore
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    HStack(spacing: 0) {
      SidebarView()

      Rectangle()
        .fill(BrandTheme.hairline)
        .frame(width: 1)
        .frame(maxHeight: .infinity)

      detailPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(BrandTheme.cream)
  }

  @ViewBuilder
  private var detailPane: some View {
    switch model.destination ?? .dashboard {
    case .dashboard:
      DashboardView()
    case .storageMap:
      StorageMapView()
    case .safeCleanup:
      ResultsView(title: "Safe Cleanup", filter: { $0.category == .safeToDelete })
    case .readyToDelete:
      ResultsView(
        title: "Ready to Delete",
        filter: ResultPresentation.isReadyToDeleteCache,
        subtitle: "High-confidence cache files that apps can recreate.",
        emptyTitle: "No cache files are ready",
        emptyMessage:
          "Run a scan to look for high-confidence cache files that can safely move to Trash."
      )
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
