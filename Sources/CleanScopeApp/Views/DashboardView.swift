import CleanScopeCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard")
              .font(.largeTitle.bold())
            Text(model.permissionSummary.message)
              .foregroundStyle(
                model.permissionSummary.isLikelyComplete ? Color.secondary : Color.orange)
            if !model.permissionSummary.setupSteps.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(model.permissionSummary.setupSteps.enumerated()), id: \.offset) {
                  index, step in
                  Text("\(index + 1). \(step)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.top, 4)
            }
          }
          Spacer()
          Button {
            Task {
              await model.startScan(
                mode: model.settings.scanDeveloperFolders ? .developer : .limited)
            }
          } label: {
            Label(model.isScanning ? "Scanning" : "Rescan", systemImage: "arrow.clockwise")
          }
          .disabled(model.isScanning)
        }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
          metric("Disk Used", bytes: model.session?.diskUsedBytes ?? 0)
          metric("Available", bytes: model.session?.diskAvailableBytes ?? 0)
          metric("Potential Cleanup", bytes: model.session?.summary.totalCleanableBytes ?? 0)
          metric("Protected", bytes: model.session?.summary.protectedBytes ?? 0)
        }

        HStack {
          Text("Largest Items")
            .font(.title2.bold())
          Spacer()
          if model.isScanning {
            ProgressView()
              .controlSize(.small)
          }
        }
        ResultsTable(
          results: Array(model.streamedResults.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(10))
        )
        .frame(minHeight: 320)
      }
      .padding(24)
    }
  }

  private func metric(_ title: String, bytes: Int64) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(ByteCount.string(bytes))
        .font(.title2.weight(.semibold))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
  }
}
