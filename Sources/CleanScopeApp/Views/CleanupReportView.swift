import CleanScopeCore
import SwiftUI

struct CleanupReportView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Cleanup History")
        .font(.largeTitle.bold())
      if let cleanup = model.cleanupSession {
        Text("Recovered \(ByteCount.string(cleanup.recoveredBytes))")
          .font(.title2.weight(.semibold))
        List {
          reportSection("Deleted", items: cleanup.deletedItems)
          reportSection("Skipped", items: cleanup.skippedItems)
          reportSection("Permission-blocked", items: cleanup.blockedItems)
          reportSection("Failed", items: cleanup.failedItems)
        }
      } else {
        EmptyStateView(
          title: "No cleanup report yet",
          systemImage: "doc.text.magnifyingglass",
          message: "Reviewed cleanup activity will appear here."
        )
      }
    }
    .padding(24)
  }

  private func reportSection(_ title: String, items: [CleanupItemResult]) -> some View {
    Section(title) {
      if items.isEmpty {
        Text("None")
          .foregroundStyle(.secondary)
      } else {
        ForEach(items) { item in
          VStack(alignment: .leading, spacing: 2) {
            Text(item.path)
            Text(item.message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
