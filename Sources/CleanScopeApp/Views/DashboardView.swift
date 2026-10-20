import AppKit
import CleanScopeCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var model: AppModel
  @State private var detail: ScanResult?
  @State private var review: ReviewRequest?

  private var quickWins: [ScanResult] {
    Array(
      ResultPresentation.outermost(model.results(for: .readyToDelete))
        .sorted { $0.sizeBytes > $1.sizeBytes }
        .prefix(6)
    )
  }

  var body: some View {
    let wins = quickWins
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header

        GrowthSummaryView(
          summary: model.summary,
          safeCount: model.safeCount,
          reviewCount: model.reviewCount,
          disk: model.disk,
          isScanning: model.isScanning,
          hasScanned: model.hasScanned
        )

        if let permission = model.permissionSummary, !model.isScanning {
          PermissionBannerView(summary: permission)
        }

        quickWinsSection(wins)
      }
      .padding(24)
      .frame(maxWidth: 900, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Dashboard")
    .sheet(item: $detail) { result in
      ItemDetailView(result: model.currentResult(for: result))
    }
    .sheet(item: $review) { request in
      CleanupReviewSheet(items: request.items) { reviewed in
        Task { await model.cleanup(reviewed) }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(
        StoragePresentation.headline(
          hasScanned: model.hasScanned, isScanning: model.isScanning,
          safeBytes: model.summary.safeToDeleteBytes)
      )
      .font(.system(size: 26, weight: .bold))
      .foregroundStyle(BrandTheme.textPrimary)
      .accessibilityAddTraits(.isHeader)

      Text(subheadline)
        .foregroundStyle(BrandTheme.textSecondary)
    }
  }

  private var subheadline: String {
    if model.isScanning {
      return "\(CountPhrase.make(model.summary.totalResults, "item")) found so far."
    }
    guard model.hasScanned else {
      return "CleanScope checks known cleanup locations. Nothing is removed until you review it."
    }
    if let line = StoragePresentation.reviewLine(count: model.reviewCount) { return line }
    return StoragePresentation.reclaimCopy(bytes: model.summary.safeToDeleteBytes)
  }

  @ViewBuilder
  private func quickWinsSection(_ wins: [ScanResult]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Quick wins")
            .font(.title3.weight(.semibold))
            .foregroundStyle(BrandTheme.textPrimary)
            .accessibilityAddTraits(.isHeader)
          Text("The largest high-confidence caches. Each can move safely to Trash.")
            .font(.callout)
            .foregroundStyle(BrandTheme.textSecondary)
        }
        Spacer()
        if !wins.isEmpty && !model.isScanning {
          Button("Review Quick Wins…") { review = ReviewRequest(items: wins) }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.accent)
        }
      }

      if wins.isEmpty {
        quickWinsEmpty
          .frame(minHeight: 200)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(wins.enumerated()), id: \.element.id) { index, result in
            if index > 0 { Divider().padding(.leading, 44) }
            QuickWinRow(result: result) { detail = result }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
            .fill(BrandTheme.surfaceRaised)
        )

        let total = model.counts[.readyToDelete] ?? 0
        if total > wins.count {
          Button("Show all \(CountPhrase.make(total, "item")) in Ready to Delete") {
            model.destination = .readyToDelete
          }
          .buttonStyle(.link)
        }
      }
    }
  }

  @ViewBuilder
  private var quickWinsEmpty: some View {
    if model.isScanning {
      EmptyStateView(
        title: "Looking for quick wins",
        systemImage: "magnifyingglass",
        message: "Safe, high-confidence caches will appear here as they are found."
      )
    } else if model.hasScanned {
      EmptyStateView(
        title: "No quick wins this time",
        systemImage: "leaf",
        message: "No high-confidence caches turned up. Browse Large Files or Downloads to review items yourself."
      )
    } else {
      EmptyStateView(
        title: "No scan yet",
        systemImage: "magnifyingglass",
        message: "Run a scan to find caches and generated files your apps can rebuild.",
        commandLabel: "Start Scan"
      ) {
        Task { await model.startScan() }
      }
    }
  }
}

struct ReviewRequest: Identifiable {
  let id = UUID()
  var items: [ScanResult]
}

private struct QuickWinRow: View {
  var result: ScanResult
  var onOpen: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: onOpen) {
      HStack(spacing: 12) {
        Image(nsImage: FileIcon.image(for: result))
          .resizable()
          .frame(width: 22, height: 22)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(result.name)
            .foregroundStyle(BrandTheme.textPrimary)
            .lineLimit(1)
          Text(result.path)
            .font(.caption)
            .foregroundStyle(BrandTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 12)
        Text(ByteCount.string(result.sizeBytes))
          .font(.system(.body, design: .rounded).weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(BrandTheme.textPrimary)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(BrandTheme.textSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
      .background(isHovered ? BrandTheme.hairline.opacity(0.35) : .clear)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(result.path)
    .accessibilityLabel("\(result.name), \(ByteCount.string(result.sizeBytes))")
    .accessibilityHint("Shows details")
  }
}
