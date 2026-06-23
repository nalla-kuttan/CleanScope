import AppKit
import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        BrandMarkView(size: 36)
        VStack(alignment: .leading, spacing: 0) {
          Text("CleanScope")
            .font(.headline)
            .foregroundStyle(BrandTheme.deepInk)
          Text("Make room for what’s next.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 8)

      List(AppModel.Destination.allCases, selection: $model.destination) { destination in
        Label(destination.rawValue, systemImage: destination.systemImage)
          .tag(destination)
      }
      .listStyle(.sidebar)
    }
    .tint(BrandTheme.scopeForest)
    .navigationSplitViewColumnWidth(min: 206, ideal: 224, max: 278)
    .safeAreaInset(edge: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Button {
            Task {
              if model.isScanning {
                model.cancelScan()
              } else {
                await model.startScan(
                  mode: model.settings.scanDeveloperFolders ? .developer : .limited)
              }
            }
          } label: {
            Label(
              model.isScanning ? "Cancel Scan" : "Start Scan",
              systemImage: model.isScanning ? "xmark.circle" : "play.fill"
            )
          }
          .buttonStyle(.borderedProminent)
          .tint(model.isScanning ? BrandTheme.actionCoral : BrandTheme.scopeForest)

          Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
          } label: {
            Image(systemName: "gearshape")
          }
          .help("Settings")
        }

        Text(model.isScanning ? "Scanning carefully…" : model.permissionSummary.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .background(.bar)
    }
  }
}
