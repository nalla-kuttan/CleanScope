import CleanScopeCore
import SwiftUI

struct ResultsView: View {
  @EnvironmentObject private var model: AppModel
  var title: String
  var filter: (ScanResult) -> Bool
  @State private var selectedResult: ScanResult?
  @State private var showsConfirmation = false

  private var filtered: [ScanResult] {
    model.streamedResults.filter(filter).sorted { $0.sizeBytes > $1.sizeBytes }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title)
          .font(.largeTitle.bold())
        Spacer()
        Button {
          showsConfirmation = true
        } label: {
          Label("Move to Trash", systemImage: "trash")
        }
        .disabled(model.selection.isEmpty)
      }

      if filtered.isEmpty {
        EmptyStateView(
          title: "No items found",
          systemImage: "checkmark.seal",
          message: "Run a scan or adjust Settings."
        )
      } else {
        ResultsTable(results: filtered, selectedResult: $selectedResult)
      }
    }
    .padding(24)
    .sheet(item: $selectedResult) { result in
      ItemDetailView(result: result)
    }
    .confirmationDialog(
      "Move selected items to Trash?",
      isPresented: $showsConfirmation,
      titleVisibility: .visible
    ) {
      Button("Move Selected Items to Trash", role: .destructive) {
        Task { await model.cleanupSelected() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Items outside Safe to Delete may be skipped or require manual review. CleanScope moves files to Trash by default."
      )
    }
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
          "",
          isOn: Binding(
            get: { model.selection.contains(result.id) },
            set: { _ in model.toggleSelection(result) }
          )
        )
        .labelsHidden()
        .disabled(!result.canDelete)
      }
      .width(36)

      TableColumn("Name") { result in
        Button(result.name) {
          selectedResult.wrappedValue = result
        }
        .buttonStyle(.plain)
        .help("View item details")
      }

      TableColumn("Size") { result in
        Text(ByteCount.string(result.sizeBytes))
      }
      .width(min: 80, ideal: 100)

      TableColumn("Category") { result in
        SafetyLabel(category: result.category)
      }
      .width(min: 130, ideal: 150)

      TableColumn("Confidence") { result in
        Text(result.confidence.rawValue.capitalized)
      }
      .width(min: 80, ideal: 90)

      TableColumn("Path") { result in
        Text(result.path)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(result.path)
      }
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
    case .safeToDelete: return .green
    case .probablyUnused: return .yellow
    case .deleteIfAppUnused: return .orange
    case .doNotBulkDelete: return .secondary
    }
  }
}
