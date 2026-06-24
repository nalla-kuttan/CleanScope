import CleanScopeCore
import SwiftUI

struct DashboardView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedResult: ScanResult?

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
      VStack(alignment: .leading, spacing: 18) {
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
            symbol: "sparkles",
            tint: BrandTheme.freshLeaf
          )
          StorageMetricView(
            label: "Needs review",
            value: "\(reviewCount)",
            symbol: "questionmark.circle",
            tint: BrandTheme.sunToken
          )
        }

        PermissionBannerView(summary: model.permissionSummary)

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Quick Wins")
                .font(.title2.bold())
              Text("High-confidence items that can move safely to Trash.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
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
                ? "Safe, high-confidence results will appear here as they are found."
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
    .background(BrandTheme.clearPaper)
    .sheet(item: $selectedResult) { result in
      ItemDetailView(result: result)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      BrandMarkView(size: 54, field: true, isDecorative: true)
      VStack(alignment: .leading, spacing: 3) {
        Text("Your Mac has room to grow.")
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(BrandTheme.deepInk)
        Text(scanStatus)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()

      if model.isScanning {
        Button {
          model.cancelScan()
        } label: {
          Label("Cancel", systemImage: "xmark.circle")
        }
      } else {
        Button {
          Task {
            await model.startScan(
              mode: model.settings.scanDeveloperFolders ? .developer : .limited)
          }
        } label: {
          Label(model.session == nil ? "Start Scan" : "Rescan", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.scopeForest)
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
