import AppKit
import CleanScopeCore
import SwiftUI

struct ResultsView: View {
  @EnvironmentObject private var model: AppModel
  var title: String
  var filter: (ScanResult) -> Bool
  var subtitle: String? = nil
  var emptyTitle = "Nothing here right now"
  var emptyMessage = "Run a scan or adjust your scan locations in Settings."
  @State private var selectedResult: ScanResult?
  @State private var showsReview = false
  @State private var rangeAnchorID: String?
  @State private var searchQuery = ""
  @State private var sortField: SortField = .size

  enum SortField: String, CaseIterable { case name, size, category, date }

  private var filtered: [ScanResult] {
    let base = model.streamedResults.filter(filter)
    let searched = searchQuery.isEmpty ? base : base.filter {
      $0.name.localizedCaseInsensitiveContains(searchQuery) ||
      $0.path.localizedCaseInsensitiveContains(searchQuery)
    }
    switch sortField {
    case .name: return searched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    case .size: return searched.sorted { $0.sizeBytes > $1.sizeBytes }
    case .category: return searched.sorted { $0.category.rawValue < $1.category.rawValue }
    case .date: return searched.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }
  }

  private var totalBytes: Int64 { filtered.reduce(0) { $0 + $1.sizeBytes } }

  private var selectionState: VisibleSelectionState {
    ResultSelection.state(visible: filtered, selectedIDs: model.selection)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(BrandTheme.bark)
          if let subtitle {
            Text(subtitle).font(.system(.subheadline, design: .rounded)).foregroundStyle(BrandTheme.warmGray)
          }
          Text("\(filtered.count) items · \(ByteCount.string(totalBytes))")
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(BrandTheme.warmGray)
        }
        Spacer()

        if model.selectionSummary.itemCount > 0 {
          HStack(spacing: 10) {
            Text("\(model.selectionSummary.itemCount) selected · " + ByteCount.string(model.selectionSummary.totalBytes))
              .font(.system(.subheadline, design: .rounded).weight(.medium))
              .foregroundStyle(BrandTheme.warmGray)
              .monospacedDigit()
            Button("Clear") { model.clearSelection(); rangeAnchorID = nil }
            reviewButton
          }
        } else {
          reviewButton.disabled(true)
        }
      }

      let baseFiltered = model.streamedResults.filter(filter)
      if baseFiltered.isEmpty {
        EmptyStateView(title: emptyTitle, systemImage: "checkmark.seal", message: emptyMessage)
      } else {
        // Search + Sort bar
        HStack(spacing: 12) {
          searchField
          Spacer()
          sortPills
        }

        if filtered.isEmpty {
          EmptyStateView(title: "No matching results", systemImage: "magnifyingglass", message: "Try a different keyword.")
        } else {
          // Bulk select
          HStack(spacing: 6) {
            SelectionCheckbox(
              state: checkboxState(selectionState),
              isEnabled: !ResultSelection.eligible(filtered).isEmpty,
              accessibilityLabel: selectionState == .all ? "Deselect all" : "Select all"
            ) { _ in toggleAllVisible() }
            Text(selectionState == .all ? "Deselect all" : "Select all visible")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(BrandTheme.warmGray)
          }
          .padding(.leading, 4)

          // Card list
          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(filtered) { result in
                ResultCardRow(result: result, onToggle: { usesRange in select(result, usingRange: usesRange) }) {
                  selectedResult = result
                }
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
    .padding(24)
    .background(BrandTheme.cream)
    .sheet(item: $selectedResult) { result in
      ItemDetailView(result: currentResult(for: result))
    }
    .sheet(isPresented: $showsReview) {
      CleanupReviewSheet(items: model.selectedResults()) {
        Task { await model.cleanupSelected() }
      }
    }
    .onChange(of: filtered.map(\.id)) { visibleIDs in
      if let rangeAnchorID, !visibleIDs.contains(rangeAnchorID) { self.rangeAnchorID = nil }
    }
  }

  // MARK: - Sub-views

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").foregroundStyle(BrandTheme.warmGray)
      TextField("Search…", text: $searchQuery)
        .textFieldStyle(.plain)
        .font(.system(.subheadline, design: .rounded))
        .frame(width: 180)
      if !searchQuery.isEmpty {
        Button { searchQuery = "" } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(BrandTheme.warmGray)
        }.buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Capsule().fill(BrandTheme.clay))
    .overlay(Capsule().stroke(BrandTheme.hairline))
  }

  private var sortPills: some View {
    HStack(spacing: 6) {
      Text("Sort:").font(.system(.caption, design: .rounded)).foregroundStyle(BrandTheme.warmGray)
      ForEach(SortField.allCases, id: \.self) { field in
        Button {
          sortField = field
          BrandTheme.triggerHaptic()
        } label: {
          Text(field.rawValue.capitalized)
            .font(.system(.caption, design: .rounded).weight(sortField == field ? .bold : .regular))
            .foregroundStyle(sortField == field ? .white : BrandTheme.warmGray)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(sortField == field ? BrandTheme.sage : BrandTheme.clay))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var reviewButton: some View {
    Button { showsReview = true } label: {
      Label("Review Cleanup", systemImage: "checklist")
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
    }
    .buttonStyle(.borderedProminent)
    .tint(BrandTheme.sage)
  }

  // MARK: - Helpers

  private func currentResult(for result: ScanResult) -> ScanResult {
    model.streamedResults.first(where: { $0.id == result.id }) ?? result
  }

  private func toggleAllVisible() { model.setSelection(selectionState != .all, for: filtered) }

  private func select(_ result: ScanResult, usingRange: Bool) {
    let shouldSelect = !model.selection.contains(result.id)
    if usingRange, let rangeAnchorID {
      let ids = Set(ResultSelection.eligibleIDs(in: filtered, from: rangeAnchorID, through: result.id))
      let rangeItems = filtered.filter { ids.contains($0.id) }
      if rangeItems.isEmpty { model.setSelection(shouldSelect, for: result) }
      else { model.setSelection(shouldSelect, for: rangeItems) }
    } else {
      model.setSelection(shouldSelect, for: result)
    }
    rangeAnchorID = result.id
  }

  private func checkboxState(_ state: VisibleSelectionState) -> SelectionCheckbox.State {
    switch state { case .none: return .off; case .some: return .mixed; case .all: return .on }
  }
}

// MARK: - ResultsTable (kept for DashboardView Quick Wins compatibility)

struct ResultsTable: View {
  @EnvironmentObject private var model: AppModel
  var results: [ScanResult]
  var sortOrder: Binding<[KeyPathComparator<ScanResult>]> = .constant([])
  var selectedResult: Binding<ScanResult?> = .constant(nil)
  var showsBulkSelection = true
  var onSelect: ((ScanResult, Bool) -> Void)?
  var onToggleAll: (() -> Void)?

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 6) {
        ForEach(results) { result in
          ResultCardRow(result: result, onToggle: { usesRange in
            if let onSelect { onSelect(result, usesRange) }
            else { model.toggleSelection(result) }
          }) {
            selectedResult.wrappedValue = result
          }
        }
      }
      .padding(.vertical, 2)
    }
  }
}

// MARK: - Result Card Row

struct ResultCardRow: View {
  @EnvironmentObject private var model: AppModel
  let result: ScanResult
  var onToggle: (_ usesRangeSelection: Bool) -> Void
  var onDetail: () -> Void
  @State private var isHovered = false
  @State private var confirmsPermanent = false

  var body: some View {
    HStack(spacing: 10) {
      // Selection checkbox
      SelectionCheckbox(
        state: model.selection.contains(result.id) ? .on : .off,
        isEnabled: result.canDelete && !result.isExcluded,
        accessibilityLabel: model.selection.contains(result.id) ? "Deselect \(result.name)" : "Select \(result.name)"
      ) { usesRange in onToggle(usesRange) }

      // Icon badge
      Image(systemName: result.itemType == .folder ? "folder.fill" : "doc.fill")
        .font(.system(size: 13))
        .foregroundStyle(result.category.tintColor)
        .frame(width: 28, height: 28)
        .background(result.category.tintColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      // Name + path
      VStack(alignment: .leading, spacing: 1) {
        Button(action: onDetail) {
          Text(result.name)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(result.isExcluded ? BrandTheme.warmGray : BrandTheme.bark)
            .lineLimit(1)
        }.buttonStyle(.plain)

        HStack(spacing: 4) {
          if result.isCloudOnly {
            Label("Cloud only", systemImage: "icloud")
              .labelStyle(.titleAndIcon)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundStyle(BrandTheme.finderBlue)
              .help(CloudOnlyCopy.note)
          }
          Text(result.path)
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(BrandTheme.warmGray)
            .lineLimit(1)
            .help(result.path)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 4)

      // Metadata
      Text(ByteCount.string(result.isCloudOnly ? result.cloudOnlyBytes : result.sizeBytes))
        .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.medium))
        .foregroundStyle(BrandTheme.bark)
        .frame(width: 75, alignment: .trailing)

      SafetyLabel(category: result.category)
        .frame(width: 130, alignment: .leading)

      Text(result.lastModified?.formatted(date: .abbreviated, time: .omitted) ?? "—")
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(BrandTheme.warmGray)
        .frame(width: 80, alignment: .leading)

      // Context menu
      Menu {
        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.normalizedPath)]) }
          label: { Label("Open in Finder", systemImage: "folder") }
        Button { model.exclude(result) } label: { Label("Exclude", systemImage: "eye.slash") }
          .disabled(result.isExcluded)
        if result.canDelete {
          Divider()
          Button(role: .destructive) {
            if model.settings.deleteImmediately {
              confirmsPermanent = true
            } else {
              Task { await model.cleanup(result) }
            }
          } label: {
            Label(
              model.settings.deleteImmediately ? "Delete Permanently…" : "Move to Trash",
              systemImage: "trash")
          }
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(BrandTheme.warmGray)
          .frame(width: 22, height: 22)
      }
      .menuStyle(.borderlessButton)
      .frame(width: 26)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(model.selection.contains(result.id) ? BrandTheme.sage.opacity(0.10) : BrandTheme.clay)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(
          model.selection.contains(result.id) ? BrandTheme.sage.opacity(0.35) :
          (isHovered ? BrandTheme.sage.opacity(0.18) : BrandTheme.hairline),
          lineWidth: 1
        )
    )
    .shadow(color: isHovered ? BrandTheme.sage.opacity(0.08) : .clear, radius: 4, y: 2)
    .scaleEffect(isHovered ? 1.003 : 1.0)
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .onHover { isHovered = $0 }
    .alert(
      "Delete \(result.name) (\(ByteCount.string(result.sizeBytes))) permanently?",
      isPresented: $confirmsPermanent
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Permanently", role: .destructive) { Task { await model.cleanup(result) } }
    } message: {
      Text("This can't be undone.")
    }
    // Selected left accent bar
    .overlay(alignment: .leading) {
      if model.selection.contains(result.id) {
        RoundedRectangle(cornerRadius: 2)
          .fill(BrandTheme.sage)
          .frame(width: 3, height: 22)
          .padding(.leading, 3)
      }
    }
  }

}

// MARK: - Safety Label

struct SafetyLabel: View {
  var category: SafetyCategory

  var body: some View {
    Label(category.label, systemImage: category.symbolName)
      .font(.system(.caption, design: .rounded).weight(.semibold))
      .foregroundStyle(category.tintColor)
      .lineLimit(1)
      .accessibilityLabel(category.label)
  }
}

enum CloudOnlyCopy {
  static let note = "Stored in the cloud only. Removing it here deletes it from the cloud."
}
