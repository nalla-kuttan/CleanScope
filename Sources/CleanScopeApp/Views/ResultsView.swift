import AppKit
import CleanScopeCore
import SwiftUI

struct ResultsView: View {
  @EnvironmentObject private var model: AppModel
  var destination: AppModel.Destination

  @State private var detail: ScanResult?
  @State private var review: ReviewRequest?
  @State private var rangeAnchorID: String?
  @State private var searchQuery = ""
  @State private var highlighted = Set<ScanResult.ID>()
  @State private var sortOrder = [KeyPathComparator(\ScanResult.sizeBytes, order: .reverse)]

  var body: some View {
    // Derived once per render and shared by every subview below.
    let base = model.results(for: destination)
    let rows = visibleRows(from: base)
    let selected = model.selectedResults()
    let visibleIDs = Set(rows.map(\.id))
    let selectedHere = selected.filter { visibleIDs.contains($0.id) }
    let selectionState = ResultSelection.state(visible: rows, selectedIDs: model.selection)

    VStack(alignment: .leading, spacing: 0) {
      if base.isEmpty {
        emptyState
      } else {
        header(rows: rows, selected: selected, selectedHere: selectedHere, state: selectionState)
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
        Divider()
        if rows.isEmpty {
          EmptyStateView(
            title: "No matches for “\(searchQuery)”",
            systemImage: "magnifyingglass",
            message: "Try a different name or part of the path."
          )
        } else {
          table(rows)
        }
      }
    }
    .navigationTitle(destination.title)
    .navigationSubtitle(subtitle(base))
    .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search names and paths")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          review = ReviewRequest(items: selected)
        } label: {
          Label("Review Cleanup…", systemImage: "checklist")
        }
        .disabled(selected.isEmpty)
        .help(
          selected.isEmpty
            ? "Select items to review them for cleanup"
            : model.settings.deleteImmediately
              ? "Review \(CountPhrase.make(selected.count, "selected item")) before deleting them permanently"
              : "Review \(CountPhrase.make(selected.count, "selected item")) before moving them to Trash")
      }
    }
    .sheet(item: $detail) { result in
      ItemDetailView(result: model.currentResult(for: result))
    }
    .sheet(item: $review) { request in
      CleanupReviewSheet(items: request.items) { reviewed in
        Task { await model.cleanup(reviewed) }
      }
    }
    #if DEBUG
      .onReceive(model.$debugDetail) { if let item = $0 { detail = item } else { detail = nil } }
    #endif
    .onChange(of: rows.map(\.id)) { _, ids in
      if let rangeAnchorID, !ids.contains(rangeAnchorID) { self.rangeAnchorID = nil }
    }
  }

  // MARK: - Header

  private func header(
    rows: [ScanResult], selected: [ScanResult], selectedHere: [ScanResult],
    state: VisibleSelectionState
  ) -> some View {
    HStack(alignment: .center, spacing: 12) {
      if let icon = destination.icon {
        ModuleIcon(key: icon, size: 64)
      }
      SelectionCheckbox(
        state: checkboxState(state),
        isEnabled: !ResultSelection.eligible(rows).isEmpty,
        accessibilityLabel: state == .all ? "Deselect all visible" : "Select all visible",
        unavailableReason: "Nothing here can be moved to Trash from CleanScope."
      ) { _ in model.setSelection(state != .all, for: rows) }

      VStack(alignment: .leading, spacing: 2) {
        Text(selectionText(selected: selected, selectedHere: selectedHere))
          .foregroundStyle(BrandTheme.textPrimary)
          .monospacedDigit()
        if let subtitle = destination.subtitle {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(BrandTheme.textSecondary)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 12)

      if !selected.isEmpty {
        Button("Clear Selection") {
          model.clearSelection()
          rangeAnchorID = nil
        }
      }
    }
  }

  private func selectionText(selected: [ScanResult], selectedHere: [ScanResult]) -> String {
    guard !selected.isEmpty else { return "Select items to review for cleanup" }
    let bytes = ByteCount.string(ResultPresentation.totalBytes(selected))
    let elsewhere = selected.count - selectedHere.count
    if elsewhere > 0 {
      return "\(CountPhrase.make(selected.count, "item")) selected · \(bytes) (\(elsewhere.formatted()) in other sections)"
    }
    return "\(CountPhrase.make(selected.count, "item")) selected · \(bytes)"
  }

  // MARK: - Table

  private func table(_ rows: [ScanResult]) -> some View {
    Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
      TableColumn("") { (result: ScanResult) in
        SelectionCheckbox(
          state: model.selection.contains(result.id) ? .on : .off,
          isEnabled: result.canDelete && !result.isExcluded,
          accessibilityLabel: "Select \(result.name) for cleanup",
          unavailableReason: result.unavailableReason
        ) { usesRange in select(result, in: rows, usingRange: usesRange) }
      }
      .width(28)

      TableColumn("Name", value: \ScanResult.name) { (result: ScanResult) in
        NameCell(result: result)
      }
      .width(min: 140, ideal: 360)

      TableColumn("Size", value: \ScanResult.sizeBytes) { (result: ScanResult) in
        Text(ByteCount.string(result.isCloudOnly ? result.cloudOnlyBytes : result.sizeBytes))
          .font(.system(.body, design: .rounded).weight(.medium))
          .monospacedDigit()
          .foregroundStyle(BrandTheme.textPrimary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 70, ideal: 84, max: 110)

      TableColumn("Safety", value: \ScanResult.category.sortRank) { (result: ScanResult) in
        SafetyLabel(category: result.category)
      }
      .width(min: 132, ideal: 160, max: 200)

      TableColumn("Modified", sortUsing: KeyPathComparator(\ScanResult.lastModified)) {
        (result: ScanResult) in
        Text(result.lastModified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
          .foregroundStyle(BrandTheme.textSecondary)
          .monospacedDigit()
      }
      .width(min: 96, ideal: 104, max: 130)
    }
    .contextMenu(forSelectionType: ScanResult.ID.self) { ids in
      contextMenu(for: rows.filter { ids.contains($0.id) })
    } primaryAction: { ids in
      if let first = rows.first(where: { ids.contains($0.id) }) { detail = first }
    }
  }

  @ViewBuilder
  private func contextMenu(for items: [ScanResult]) -> some View {
    let eligible = ResultSelection.eligible(items)
    if items.count == 1, let item = items.first {
      Button("Show Details") { detail = item }
    }
    if !items.isEmpty {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting(
          items.map { URL(fileURLWithPath: $0.normalizedPath) })
      }
    }
    if !eligible.isEmpty {
      Divider()
      if eligible.allSatisfy({ model.selection.contains($0.id) }) {
        Button("Deselect for Cleanup") { model.setSelection(false, for: eligible) }
      } else {
        Button("Select for Cleanup") { model.setSelection(true, for: eligible) }
      }
    }
    if items.count == 1, let item = items.first, !item.isExcluded {
      Button("Exclude from Results") { model.exclude(item) }
    }
    if !eligible.isEmpty {
      Divider()
      Button(
        model.settings.deleteImmediately
          ? "Delete \(CountPhrase.make(eligible.count, "Item")) Permanently…"
          : "Move \(CountPhrase.make(eligible.count, "Item")) to Trash…"
      ) {
        review = ReviewRequest(items: eligible)
      }
    }
  }

  // MARK: - Empty

  @ViewBuilder
  private var emptyState: some View {
    if model.isScanning {
      EmptyStateView(
        title: "Scanning…",
        systemImage: "magnifyingglass",
        message: "Matching items will appear here as they are found.",
        icon: destination.icon
      )
    } else if model.hasScanned {
      EmptyStateView(
        title: destination.emptyTitle,
        systemImage: destination.systemImage,
        message: destination.emptyMessage,
        icon: destination.icon
      )
    } else {
      EmptyStateView(
        title: "No scan yet",
        systemImage: destination.systemImage,
        message: "Run a scan to see what’s in \(destination.title).",
        icon: destination.icon,
        commandLabel: "Start Scan"
      ) {
        Task { await model.startScan() }
      }
    }
  }

  // MARK: - Helpers

  private func visibleRows(from base: [ScanResult]) -> [ScanResult] {
    let query = searchQuery.trimmingCharacters(in: .whitespaces)
    let searched =
      query.isEmpty
      ? base
      : base.filter {
        $0.name.localizedCaseInsensitiveContains(query)
          || $0.path.localizedCaseInsensitiveContains(query)
      }
    return searched.sorted(using: sortOrder)
  }

  private func subtitle(_ base: [ScanResult]) -> String {
    guard !base.isEmpty else { return "" }
    return "\(CountPhrase.make(base.count, "item")) · \(ByteCount.string(ResultPresentation.totalBytes(base)))"
  }

  private func select(_ result: ScanResult, in rows: [ScanResult], usingRange: Bool) {
    let shouldSelect = !model.selection.contains(result.id)
    if usingRange, let rangeAnchorID {
      let ids = Set(ResultSelection.eligibleIDs(in: rows, from: rangeAnchorID, through: result.id))
      let rangeItems = rows.filter { ids.contains($0.id) }
      if rangeItems.isEmpty {
        model.setSelection(shouldSelect, for: result)
      } else {
        model.setSelection(shouldSelect, for: rangeItems)
      }
    } else {
      model.setSelection(shouldSelect, for: result)
    }
    rangeAnchorID = result.id
  }

  private func checkboxState(_ state: VisibleSelectionState) -> SelectionCheckbox.State {
    switch state {
    case .none: return .off
    case .some: return .mixed
    case .all: return .on
    }
  }
}

private struct NameCell: View {
  var result: ScanResult

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: FileIcon.image(for: result))
        .resizable()
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(result.name)
          .foregroundStyle(result.isExcluded ? BrandTheme.textSecondary : BrandTheme.textPrimary)
          .lineLimit(1)
        HStack(spacing: 4) {
          if result.isCloudOnly {
            Label("Cloud only", systemImage: "icloud")
              .labelStyle(.titleAndIcon)
              .font(.caption.weight(.semibold))
              .foregroundStyle(BrandTheme.info)
              .help(CloudOnlyCopy.note)
          }
          Text(result.isExcluded ? "Excluded · \(result.path)" : result.path)
            .font(.caption)
            .foregroundStyle(BrandTheme.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .help(result.path)
  }
}

enum CloudOnlyCopy {
  static let note = "Stored in the cloud only. Removing it here deletes it from the cloud."
}
