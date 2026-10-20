import CleanScopeCore
import SwiftUI

struct CleanupReportView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Cleanup History")
              .font(.system(size: 28, weight: .bold))
              .foregroundStyle(BrandTheme.deepInk)
            Text("A transparent record of what moved and what stayed.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            Task {
              await model.startScan(
                mode: model.settings.scanDeveloperFolders ? .developer : .limited)
            }
          } label: {
            Label("Rescan", systemImage: "arrow.clockwise")
          }
          .buttonStyle(.borderedProminent)
          .tint(BrandTheme.scopeForest)
          .disabled(model.isScanning)
        }

        if let cleanup = model.cleanupSession {
          CleanupCelebrationView(
            recoveredBytes: cleanup.recoveredBytes,
            reduceMotion: reduceMotion
          )

          if let reminder = CleanupSummaryCopy.trashReminder(for: cleanup) {
            Label(reminder, systemImage: "trash")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 12) {
            StorageMetricView(
              label: "Available before",
              value: ByteCount.string(cleanup.diskSpaceBeforeBytes),
              symbol: "internaldrive",
              tint: BrandTheme.finderBlue
            )
            StorageMetricView(
              label: "Available after",
              value: ByteCount.string(cleanup.diskSpaceAfterBytes ?? cleanup.diskSpaceBeforeBytes),
              symbol: "checkmark.circle",
              tint: BrandTheme.freshLeaf
            )
          }

          VStack(spacing: 10) {
            reportSection(
              "Removed", symbol: "trash.fill", tint: BrandTheme.freshLeaf,
              items: cleanup.deletedItems)
            reportSection(
              "Skipped", symbol: "forward.fill", tint: BrandTheme.sunToken,
              items: cleanup.skippedItems)
            reportSection(
              "Permission blocked", symbol: "lock.fill", tint: BrandTheme.finderBlue,
              items: cleanup.blockedItems)
            reportSection(
              "Failed", symbol: "xmark.octagon.fill", tint: BrandTheme.actionCoral,
              items: cleanup.failedItems)
          }
        } else {
          EmptyStateView(
            title: "No cleanup report yet",
            systemImage: "doc.text.magnifyingglass",
            message: "After you review and move an item to Trash, the outcome will appear here.",
            usesBrandMark: true,
            commandLabel: "Review Safe Cleanup"
          ) {
            model.destination = .safeCleanup
          }
          .frame(minHeight: 420)
        }
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.clearPaper)
  }

  private func reportSection(
    _ title: String,
    symbol: String,
    tint: Color,
    items: [CleanupItemResult]
  ) -> some View {
    DisclosureGroup {
      if items.isEmpty {
        Text("None")
          .foregroundStyle(.secondary)
          .padding(.top, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: 2) {
              Text(item.path)
                .lineLimit(1)
                .help(item.path)
              Text(item.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(.top, 8)
      }
    } label: {
      HStack {
        Label(title, systemImage: symbol)
          .foregroundStyle(tint)
        Spacer()
        Text("\(items.count)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(BrandTheme.secondarySurface)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
  }
}
