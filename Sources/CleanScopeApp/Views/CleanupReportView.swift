import CleanScopeCore
import SwiftUI

struct CleanupReportView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let cleanup = model.cleanupSession {
          CleanupCelebrationView(
            recoveredBytes: cleanup.recoveredBytes,
            movedCount: cleanup.deletedItems.count
          )

          if let reminder = CleanupSummaryCopy.trashReminder(for: cleanup) {
            Label(reminder, systemImage: "trash")
              .font(.subheadline)
              .foregroundStyle(BrandTheme.textSecondary)
          }

          availability(cleanup)

          VStack(spacing: 0) {
            reportSection(
              "Removed", symbol: "trash.fill", tint: BrandTheme.safe,
              items: cleanup.deletedItems)
            Divider()
            reportSection(
              "Skipped", symbol: "forward.fill", tint: BrandTheme.review,
              items: cleanup.skippedItems)
            Divider()
            reportSection(
              "Blocked by permissions", symbol: "lock.fill", tint: BrandTheme.info,
              items: cleanup.blockedItems)
            Divider()
            reportSection(
              "Failed", symbol: "xmark.octagon.fill", tint: BrandTheme.destructive,
              items: cleanup.failedItems)
          }
          .background(
            RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
              .fill(BrandTheme.surfaceRaised)
          )
        } else {
          EmptyStateView(
            title: "No cleanup yet",
            systemImage: "clock.arrow.circlepath",
            message:
              "After you review items and move them to Trash, this page shows what moved and what stayed.",
            icon: .cleanup,
            usesBrandMark: true,
            commandLabel: "Browse Ready to Delete"
          ) {
            model.destination = .readyToDelete
          }
          .frame(minHeight: 420)
        }
      }
      .padding(24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Last Cleanup")
    .navigationSubtitle(
      model.cleanupSession.map { $0.startedAt.formatted(date: .abbreviated, time: .shortened) } ?? "")
  }

  private func availability(_ cleanup: CleanupSession) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "internaldrive")
        .foregroundStyle(BrandTheme.textSecondary)
        .accessibilityHidden(true)
      Text("Available space")
        .foregroundStyle(BrandTheme.textSecondary)
      Text(ByteCount.string(cleanup.diskSpaceBeforeBytes))
        .monospacedDigit()
        .foregroundStyle(BrandTheme.textPrimary)
      Image(systemName: "arrow.right")
        .font(.caption)
        .foregroundStyle(BrandTheme.textSecondary)
        .accessibilityLabel("to")
      Text(cleanup.diskSpaceAfterBytes.map(ByteCount.string) ?? "—")
        .monospacedDigit()
        .foregroundStyle(BrandTheme.textPrimary)
    }
    .accessibilityElement(children: .combine)
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
          .foregroundStyle(BrandTheme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 6)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: 2) {
              Text(item.path)
                .foregroundStyle(BrandTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.path)
                .textSelection(.enabled)
              Text(item.message)
                .font(.caption)
                .foregroundStyle(BrandTheme.textSecondary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
      }
    } label: {
      HStack {
        Label(title, systemImage: symbol)
          .foregroundStyle(tint)
        Spacer()
        Text(items.count.formatted())
          .monospacedDigit()
          .foregroundStyle(BrandTheme.textSecondary)
      }
    }
    .padding(12)
  }
}
