import AppKit
import CleanScopeCore
import SwiftUI

struct ResultsView: View {
  @EnvironmentObject private var model: AppModel
  var title: String
  var filter: (ScanResult) -> Bool
  @State private var selectedResult: ScanResult?
  @State private var showsReview = false

  private var filtered: [ScanResult] {
    model.streamedResults.filter(filter).sorted { $0.sizeBytes > $1.sizeBytes }
  }

  private var totalBytes: Int64 {
    filtered.reduce(0) { $0 + $1.sizeBytes }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(BrandTheme.deepInk)
          Text("\(filtered.count) items · \(ByteCount.string(totalBytes))")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          showsReview = true
        } label: {
          Label("Review Cleanup", systemImage: "checklist")
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.scopeForest)
        .disabled(model.selection.isEmpty)
      }

      if filtered.isEmpty {
        EmptyStateView(
          title: "Nothing here right now",
          systemImage: "checkmark.seal",
          message: "Run a scan or adjust your scan locations in Settings."
        )
      } else {
        ResultsTable(results: filtered, selectedResult: $selectedResult)
      }
    }
    .padding(24)
    .background(BrandTheme.clearPaper)
    .sheet(item: $selectedResult) { result in
      ItemDetailView(result: currentResult(for: result))
    }
    .sheet(isPresented: $showsReview) {
      CleanupReviewSheet(items: model.selectedResults()) {
        Task { await model.cleanupSelected() }
      }
    }
  }

  private func currentResult(for result: ScanResult) -> ScanResult {
    model.streamedResults.first(where: { $0.id == result.id }) ?? result
  }
}

struct ResultsTable: View {
  @EnvironmentObject private var model: AppModel
  var results: [ScanResult]
  var selectedResult: Binding<ScanResult?> = .constant(nil)

  var body: some View {
    Table(results) {
      TableColumn("") { result in
        Toggle(
          "Select \(result.name)",
          isOn: Binding(
            get: { model.selection.contains(result.id) },
            set: { _ in model.toggleSelection(result) }
          )
        )
        .labelsHidden()
        .disabled(!result.canDelete || result.isExcluded)
        .help(result.canDelete ? "Include in cleanup" : "This item requires manual review")
      }
      .width(36)

      TableColumn("Name") { result in
        Button {
          selectedResult.wrappedValue = result
        } label: {
          HStack(spacing: 6) {
            Image(systemName: result.itemType == .folder ? "folder" : "doc")
              .foregroundStyle(result.isExcluded ? Color.secondary : BrandTheme.finderBlue)
            Text(result.name)
              .foregroundStyle(result.isExcluded ? Color.secondary : BrandTheme.deepInk)
              .lineLimit(1)
          }
        }
        .buttonStyle(.plain)
        .help("View item details")
      }

      TableColumn("Size") { result in
        Text(ByteCount.string(result.sizeBytes))
          .monospacedDigit()
      }
      .width(min: 78, ideal: 94)

      TableColumn("Category") { result in
        SafetyLabel(category: result.category)
      }
      .width(min: 132, ideal: 150)

      TableColumn("Modified") { result in
        Text(result.lastModified?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
          .foregroundStyle(.secondary)
      }
      .width(min: 88, ideal: 106)

      TableColumn("Path") { result in
        Text(result.path)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(result.path)
      }

      TableColumn("") { result in
        Menu {
          Button {
            NSWorkspace.shared.activateFileViewerSelecting([
              URL(fileURLWithPath: result.normalizedPath)
            ])
          } label: {
            Label("Open in Finder", systemImage: "folder")
          }

          Button {
            model.exclude(result)
          } label: {
            Label("Exclude from Future Scans", systemImage: "eye.slash")
          }
          .disabled(result.isExcluded)

          if result.canDelete {
            Divider()
            Button(role: .destructive) {
              Task { await model.cleanup(result) }
            } label: {
              Label("Move to Trash", systemImage: "trash")
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("Item actions")
      }
      .width(34)
    }
  }
}

struct SafetyLabel: View {
  var category: SafetyCategory

  var body: some View {
    Label(label, systemImage: icon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(color)
      .lineLimit(1)
      .accessibilityLabel(label)
  }

  private var label: String {
    switch category {
    case .safeToDelete: return "Safe to delete"
    case .probablyUnused: return "Review recommended"
    case .deleteIfAppUnused: return "App/tool dependent"
    case .doNotBulkDelete: return "Do not bulk delete"
    }
  }

  private var icon: String {
    switch category {
    case .safeToDelete: return "checkmark.circle.fill"
    case .probablyUnused: return "questionmark.circle.fill"
    case .deleteIfAppUnused: return "exclamationmark.triangle.fill"
    case .doNotBulkDelete: return "hand.raised.fill"
    }
  }

  private var color: Color {
    switch category {
    case .safeToDelete: return BrandTheme.freshLeaf
    case .probablyUnused: return BrandTheme.sunToken
    case .deleteIfAppUnused: return BrandTheme.actionCoral
    case .doNotBulkDelete: return .secondary
    }
  }
}
