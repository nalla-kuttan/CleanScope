import AppKit
import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List(AppModel.Destination.allCases, selection: $model.destination) { destination in
      Label(destination.rawValue, systemImage: destination.systemImage)
        .tag(destination)
    }
    .listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    .navigationTitle("CleanScope")
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

          Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
          } label: {
            Image(systemName: "gearshape")
          }
          .help("Settings")
        }
        Text(model.permissionSummary.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding()
    }
  }
}
