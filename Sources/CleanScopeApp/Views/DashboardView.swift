import CleanScopeCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedResult: ScanResult?
  @State private var showsReview = false

  private var cleanableBytes: Int64 {
    ScanSummary(results: model.streamedResults).totalCleanableBytes
  }

  private var generatedCount: Int {
    model.streamedResults.filter { $0.category == .safeToDelete }.count
  }

  private var reviewCount: Int {
    model.streamedResults.filter {
      $0.category == .probablyUnused || $0.category == .deleteIfAppUnused
    }.count
  }

  private var quickWins: [ScanResult] {
    Array(
      model.streamedResults
        .filter { $0.category == .safeToDelete && $0.confidence == .high && !$0.isExcluded }
        .sorted { $0.sizeBytes > $1.sizeBytes }
        .prefix(6)
    )
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        GrowthSummaryView(
          cleanableBytes: cleanableBytes,
          resultCount: model.streamedResults.count,
          isScanning: model.isScanning,
          reduceMotion: reduceMotion
        )

        HStack(spacing: 12) {
          StorageMetricView(
            label: "Available",
            value: ByteCount.string(model.session?.diskAvailableBytes ?? 0),
            symbol: "internaldrive",
            tint: BrandTheme.finderBlue
          )
          StorageMetricView(
            label: "Safe / generated",
            value: "\(generatedCount)",
            symbol: "leaf.fill",
            tint: BrandTheme.moss
          )
          StorageMetricView(
            label: "Needs review",
            value: "\(reviewCount)",
            symbol: "questionmark.circle",
            tint: BrandTheme.amber
          )
        }

        SystemSpaceCard()

        PermissionBannerView(summary: model.permissionSummary)

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Quick Wins")
                .font(.system(.title2, design: .rounded).bold())
                .foregroundStyle(BrandTheme.bark)
              Text("High-confidence items that can move safely to Trash.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(BrandTheme.warmGray)
            }
            Spacer()
            if !quickWins.isEmpty && !model.isScanning {
              Button {
                showsReview = true
              } label: {
                Label("Clean All Quick Wins", systemImage: "leaf.fill")
                  .font(.system(.subheadline, design: .rounded).weight(.semibold))
              }
              .buttonStyle(.bordered)
              .tint(BrandTheme.sage)
            }
            if model.isScanning {
              ProgressView()
                .controlSize(.small)
                .help("Scanning")
            }
          }

          if quickWins.isEmpty {
            EmptyStateView(
              title: model.isScanning ? "Looking for quick wins" : "No quick wins yet",
              systemImage: model.isScanning ? "magnifyingglass" : "checkmark.seal",
              message: model.isScanning
                ? "Safe results will appear here as they are found."
                : "Run a scan to find generated files and caches."
            )
            .frame(minHeight: 180)
          } else {
            ResultsTable(
              results: quickWins,
              selectedResult: $selectedResult,
              showsBulkSelection: false
            )
            .frame(minHeight: 220)
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 1180, alignment: .leading)
    }
    .background(BrandTheme.cream)
    .task { await model.refreshSystemSpace() }
    .sheet(item: $selectedResult) { result in
      ItemDetailView(result: result)
    }
    .sheet(isPresented: $showsReview) {
      CleanupReviewSheet(items: quickWins) {
        Task {
          model.setSelection(true, for: quickWins)
          await model.cleanupSelected()
        }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      BrandMarkView(size: 50, field: true, isDecorative: true)
      VStack(alignment: .leading, spacing: 3) {
        Text("Your greenhouse is growing.")
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.bark)
        Text(scanStatus)
          .font(.system(.subheadline, design: .rounded))
          .foregroundStyle(BrandTheme.warmGray)
      }
      Spacer()

      if model.isScanning {
        Button { model.cancelScan() } label: {
          Label("Cancel", systemImage: "xmark.circle")
            .font(.system(.subheadline, design: .rounded))
        }
      } else {
        Button {
          Task {
            await model.startScan(
              mode: model.settings.scanDeveloperFolders ? .developer : .limited)
          }
        } label: {
          Label(model.session == nil ? "Start Scan" : "Rescan", systemImage: "leaf.fill")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.sage)
      }
    }
  }

  private var scanStatus: String {
    if model.isScanning {
      return "\(model.streamedResults.count) results found so far"
    }
    guard let completedAt = model.session?.completedAt else {
      return "Start with a careful scan of known cleanup locations."
    }
    return
      "Last scan \(completedAt.formatted(date: .abbreviated, time: .shortened)) · \(model.streamedResults.count) results"
  }
}
