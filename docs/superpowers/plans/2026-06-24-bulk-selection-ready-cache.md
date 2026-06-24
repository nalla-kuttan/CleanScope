# Bulk Selection and Ready-to-Delete Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe select-all and Shift-click range selection to results tables, plus a dedicated Ready to Delete destination containing only high-confidence, currently deletable cache files.

**Architecture:** Put cache qualification and bulk-selection calculations in pure `CleanScopeCore` presentation helpers so they are deterministic and testable. Keep the shared selection set and mutation commands in `AppModel`, while `ResultsView` owns the transient range anchor because it depends on the current filtered and sorted rows. Reuse the existing results table and cleanup review flow; no automatic selection or deletion path is added.

**Tech Stack:** Swift 5 language mode, SwiftUI, AppKit modifier flags, Foundation, Swift Testing, SwiftPM, macOS 13+.

---

## File Structure

- `Sources/CleanScopeCore/Presentation.swift`: add the ready-cache predicate, eligible-item filtering, visible bulk-selection state, and range calculation.
- `Tests/CleanScopeCoreTests/PresentationTests.swift`: test cache inclusion/exclusion, tri-state selection, and eligible range behavior.
- `Sources/CleanScopeApp/AppModel.swift`: expose guarded selection mutations, valid selected results, clear selection, and selection summary.
- `Sources/CleanScopeApp/Views/SelectionCheckbox.swift`: reusable native-looking checkbox button that reports Shift activation and supports accessibility.
- `Sources/CleanScopeApp/Views/ResultsView.swift`: add explanatory copy, selection summary, select-all control, range anchor behavior, and cache-specific empty state support.
- `Sources/CleanScopeApp/Views/ContentView.swift`: route the new Ready to Delete destination to the shared results screen with the core cache predicate.
- `Sources/CleanScopeApp/Views/SidebarView.swift`: receives the new destination automatically through `Destination.allCases`; no structural change is expected.
- `Sources/CleanScopeApp/Views/DashboardView.swift`: adapt the Quick Wins table call site to the updated reusable table API.
- `VERIFY.md`: record the manual selection, review, accessibility, appearance, and layout checks.

---

### Task 1: Pure Cache and Selection Presentation Logic

**Files:**
- Modify: `Sources/CleanScopeCore/Presentation.swift`
- Modify: `Tests/CleanScopeCoreTests/PresentationTests.swift`

- [ ] **Step 1: Write failing cache-predicate tests**

Append these tests to `PresentationTests`:

```swift
@Test func readyCacheIncludesOnlyHighConfidenceDeletableCacheData() {
  let included = [
    resultFixture(path: "/Users/me/Library/Caches/com.example.app"),
    resultFixture(path: "/Users/me/.npm/_cacache"),
    resultFixture(path: "/Users/me/.cache/pip/http"),
  ]

  for item in included {
    #expect(ResultPresentation.isReadyToDeleteCache(item), Comment(rawValue: item.path))
  }
}

@Test func readyCacheExcludesNonCacheOrUnavailableItems() {
  var protected = resultFixture(path: "/Users/me/Library/Caches/protected")
  protected.isProtected = true
  protected.canDelete = false

  var excluded = resultFixture(path: "/Users/me/Library/Caches/excluded")
  excluded.isExcluded = true
  excluded.canDelete = false

  let rejected = [
    resultFixture(path: "/Users/me/Library/Logs/app.log"),
    resultFixture(path: "/Users/me/.Trash/archive.zip"),
    resultFixture(path: "/Users/me/project/.next"),
    resultFixture(path: "/Users/me/Library/Caches/medium", confidence: .medium),
    protected,
    excluded,
  ]

  for item in rejected {
    #expect(!ResultPresentation.isReadyToDeleteCache(item), Comment(rawValue: item.path))
  }
}
```

- [ ] **Step 2: Write failing bulk-selection tests**

Add:

```swift
@Test func visibleSelectionStateTracksNoneSomeAndAllEligibleRows() {
  let rows = [
    resultFixture(path: "/tmp/a"),
    resultFixture(path: "/tmp/b"),
    resultFixture(path: "/tmp/c", category: .doNotBulkDelete),
  ]

  #expect(ResultSelection.state(visible: rows, selectedIDs: []) == .none)
  #expect(ResultSelection.state(visible: rows, selectedIDs: [rows[0].id]) == .some)
  #expect(
    ResultSelection.state(visible: rows, selectedIDs: [rows[0].id, rows[1].id]) == .all)
}

@Test func rangeReturnsOnlyEligibleRowsInVisibleOrder() {
  let rows = [
    resultFixture(path: "/tmp/a"),
    resultFixture(path: "/tmp/b", category: .doNotBulkDelete),
    resultFixture(path: "/tmp/c"),
    resultFixture(path: "/tmp/d"),
  ]

  #expect(
    ResultSelection.eligibleIDs(in: rows, from: rows[0].id, through: rows[3].id)
      == [rows[0].id, rows[2].id, rows[3].id])
  #expect(ResultSelection.eligibleIDs(in: rows, from: "missing", through: rows[3].id).isEmpty)
}

@Test func updatingSelectionChangesOnlyEligibleSuppliedRows() {
  let a = resultFixture(path: "/tmp/a")
  let b = resultFixture(path: "/tmp/b")
  let blocked = resultFixture(path: "/tmp/blocked", category: .doNotBulkDelete)

  let selected = ResultSelection.updating(
    [],
    with: [a, blocked],
    isSelected: true
  )
  #expect(selected == [a.id])

  let deselected = ResultSelection.updating(
    [a.id, b.id],
    with: [a],
    isSelected: false
  )
  #expect(deselected == [b.id])
}

private func resultFixture(
  path: String,
  category: SafetyCategory = .safeToDelete,
  confidence: Confidence = .high
) -> ScanResult {
  var result = ScanResult.fixture(path: path, sizeBytes: 100, category: category)
  result.confidence = confidence
  return result
}
```

- [ ] **Step 3: Run the tests to verify RED**

Run:

```bash
./script/swiftpm.sh test --filter PresentationTests
```

Expected: FAIL because `ResultPresentation`, `ResultSelection`, and `VisibleSelectionState` do not exist.

- [ ] **Step 4: Implement the cache predicate and selection helpers**

Add to `Presentation.swift`:

```swift
public enum ResultPresentation {
  public static func isReadyToDeleteCache(_ result: ScanResult) -> Bool {
    guard
      result.category == .safeToDelete,
      result.confidence == .high,
      result.canDelete,
      !result.isExcluded
    else { return false }

    let path = result.normalizedPath.lowercased()
    let components = Set(
      URL(fileURLWithPath: result.normalizedPath).pathComponents.map { $0.lowercased() })

    return path.contains("/library/caches/")
      || path.contains("/.cache/")
      || components.contains(".npm")
      || components.contains(".yarn")
      || components.contains(".pnpm-store")
      || path.contains("/library/caches/pip")
  }
}

public enum VisibleSelectionState: Equatable, Sendable {
  case none
  case some
  case all
}

public enum ResultSelection {
  public static func eligible(_ results: [ScanResult]) -> [ScanResult] {
    results.filter { $0.canDelete && !$0.isExcluded }
  }

  public static func state(
    visible results: [ScanResult],
    selectedIDs: Set<String>
  ) -> VisibleSelectionState {
    let ids = Set(eligible(results).map(\.id))
    guard !ids.isEmpty else { return .none }
    let selectedVisible = ids.intersection(selectedIDs)
    if selectedVisible.isEmpty { return .none }
    return selectedVisible == ids ? .all : .some
  }

  public static func eligibleIDs(
    in results: [ScanResult],
    from anchorID: String,
    through targetID: String
  ) -> [String] {
    guard
      let anchor = results.firstIndex(where: { $0.id == anchorID }),
      let target = results.firstIndex(where: { $0.id == targetID })
    else { return [] }

    let bounds = min(anchor, target)...max(anchor, target)
    return results[bounds]
      .filter { $0.canDelete && !$0.isExcluded }
      .map(\.id)
  }

  public static func updating(
    _ selection: Set<String>,
    with results: [ScanResult],
    isSelected: Bool
  ) -> Set<String> {
    let ids = Set(eligible(results).map(\.id))
    if isSelected {
      return selection.union(ids)
    }
    return selection.subtracting(ids)
  }
}
```

- [ ] **Step 5: Run the focused tests to verify GREEN**

Run:

```bash
./script/swiftpm.sh test --filter PresentationTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanScopeCore/Presentation.swift Tests/CleanScopeCoreTests/PresentationTests.swift
git commit -m "feat: add cache and bulk selection presentation logic"
```

---

### Task 2: Guarded Selection Commands in AppModel

**Files:**
- Modify: `Sources/CleanScopeApp/AppModel.swift`

- [ ] **Step 1: Replace toggle-only mutation with explicit guarded commands**

Keep `toggleSelection(_:)` for existing call sites, but implement it through these new methods:

```swift
func setSelection(_ isSelected: Bool, for result: ScanResult) {
  guard result.canDelete, !result.isExcluded else {
    selection.remove(result.id)
    return
  }

  if isSelected {
    selection.insert(result.id)
  } else {
    selection.remove(result.id)
  }
}

func setSelection(_ isSelected: Bool, for results: [ScanResult]) {
  selection = ResultSelection.updating(selection, with: results, isSelected: isSelected)
}

func toggleSelection(_ result: ScanResult) {
  setSelection(!selection.contains(result.id), for: result)
}

func clearSelection() {
  selection.removeAll()
}
```

- [ ] **Step 2: Restrict review payloads to currently valid items**

Replace `selectedResults()` with:

```swift
func selectedResults() -> [ScanResult] {
  streamedResults.filter {
    selection.contains($0.id) && $0.canDelete && !$0.isExcluded
  }
}

var selectionSummary: SelectionSummary {
  SelectionSummary(items: selectedResults())
}
```

This keeps stale IDs from entering the cleanup review if an item becomes protected or excluded after selection.

- [ ] **Step 3: Build the app**

Run:

```bash
./script/swiftpm.sh build
```

Expected: PASS with no call-site changes required yet.

- [ ] **Step 4: Run the full core suite**

Run:

```bash
./script/swiftpm.sh test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanScopeApp/AppModel.swift
git commit -m "feat: add guarded bulk selection commands"
```

---

### Task 3: Accessible Checkbox and Range Selection

**Files:**
- Create: `Sources/CleanScopeApp/Views/SelectionCheckbox.swift`
- Modify: `Sources/CleanScopeApp/Views/ResultsView.swift`
- Modify: `Sources/CleanScopeApp/Views/DashboardView.swift`

- [ ] **Step 1: Create the reusable checkbox control**

Create `SelectionCheckbox.swift`:

```swift
import AppKit
import SwiftUI

struct SelectionCheckbox: View {
  enum State {
    case off
    case mixed
    case on
  }

  var state: State
  var isEnabled = true
  var accessibilityLabel: String
  var action: (_ usesRangeSelection: Bool) -> Void

  var body: some View {
    Button {
      action(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isEnabled ? tint : Color.secondary)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue)
    .accessibilityAddTraits(state == .on ? .isSelected : [])
  }

  private var symbol: String {
    switch state {
    case .off: return "square"
    case .mixed: return "minus.square.fill"
    case .on: return "checkmark.square.fill"
    }
  }

  private var tint: Color {
    state == .off ? .secondary : BrandTheme.scopeForest
  }

  private var accessibilityValue: String {
    switch state {
    case .off: return "Not selected"
    case .mixed: return "Partially selected"
    case .on: return "Selected"
    }
  }
}
```

- [ ] **Step 2: Add range-anchor state and selection handlers to ResultsView**

Add:

```swift
@State private var rangeAnchorID: String?

private var selectionState: VisibleSelectionState {
  ResultSelection.state(visible: filtered, selectedIDs: model.selection)
}

private func toggleAllVisible() {
  model.setSelection(selectionState != .all, for: filtered)
}

private func select(_ result: ScanResult, usingRange: Bool) {
  let shouldSelect = !model.selection.contains(result.id)

  if usingRange, let rangeAnchorID {
    let ids = Set(
      ResultSelection.eligibleIDs(
        in: filtered,
        from: rangeAnchorID,
        through: result.id
      ))
    let rangeItems = filtered.filter { ids.contains($0.id) }
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
```

Reset an invalid anchor when the visible IDs change:

```swift
.onChange(of: filtered.map(\.id)) { visibleIDs in
  if let rangeAnchorID, !visibleIDs.contains(rangeAnchorID) {
    self.rangeAnchorID = nil
  }
}
```

- [ ] **Step 3: Make ResultsTable receive selection behavior explicitly**

Change the reusable table signature to:

```swift
struct ResultsTable: View {
  @EnvironmentObject private var model: AppModel
  var results: [ScanResult]
  var selectedResult: Binding<ScanResult?> = .constant(nil)
  var showsBulkSelection = true
  var onSelect: ((ScanResult, Bool) -> Void)?
  var onToggleAll: (() -> Void)?
}
```

Derive the header state inside the table:

```swift
private var visibleSelectionState: VisibleSelectionState {
  ResultSelection.state(visible: results, selectedIDs: model.selection)
}
```

Replace the first-column `Toggle` with `SelectionCheckbox`. Use a header control only when `showsBulkSelection` is true:

```swift
TableColumn {
  if showsBulkSelection {
    SelectionCheckbox(
      state: checkboxState(visibleSelectionState),
      isEnabled: !ResultSelection.eligible(results).isEmpty,
      accessibilityLabel: visibleSelectionState == .all
        ? "Deselect all eligible visible items"
        : "Select all eligible visible items"
    ) { _ in
      onToggleAll?()
    }
  }
} content: { result in
  SelectionCheckbox(
    state: model.selection.contains(result.id) ? .on : .off,
    isEnabled: result.canDelete && !result.isExcluded,
    accessibilityLabel: "Select \(result.name)"
  ) { usesRangeSelection in
    if let onSelect {
      onSelect(result, usesRangeSelection)
    } else {
      model.toggleSelection(result)
    }
  }
}
.width(36)
```

Add a private conversion helper:

```swift
private func checkboxState(_ state: VisibleSelectionState) -> SelectionCheckbox.State {
  switch state {
  case .none: return .off
  case .some: return .mixed
  case .all: return .on
  }
}
```

- [ ] **Step 4: Wire ResultsView and preserve Dashboard behavior**

In `ResultsView`, initialize:

```swift
ResultsTable(
  results: filtered,
  selectedResult: $selectedResult,
  onSelect: select,
  onToggleAll: toggleAllVisible
)
```

In `DashboardView`, keep row selection available but hide the select-all header because Quick Wins is a compact preview:

```swift
ResultsTable(
  results: quickWins,
  selectedResult: $selectedResult,
  showsBulkSelection: false
)
```

- [ ] **Step 5: Build and run tests**

Run:

```bash
./script/swiftpm.sh build
./script/swiftpm.sh test
```

Expected: both commands PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanScopeApp/Views/SelectionCheckbox.swift Sources/CleanScopeApp/Views/ResultsView.swift Sources/CleanScopeApp/Views/DashboardView.swift
git commit -m "feat: add select all and shift range selection"
```

---

### Task 4: Selection Summary and Ready-to-Delete Destination

**Files:**
- Modify: `Sources/CleanScopeApp/AppModel.swift`
- Modify: `Sources/CleanScopeApp/Views/ResultsView.swift`
- Modify: `Sources/CleanScopeApp/Views/ContentView.swift`

- [ ] **Step 1: Add the navigation destination**

Add `readyToDelete = "Ready to Delete"` directly after `safeCleanup` in `AppModel.Destination`, and return `externaldrive.badge.checkmark` from `systemImage`:

```swift
case readyToDelete = "Ready to Delete"
```

```swift
case .readyToDelete: return "externaldrive.badge.checkmark"
```

- [ ] **Step 2: Route the destination with cache-specific copy**

Extend `ResultsView` with:

```swift
var subtitle: String? = nil
var emptyTitle = "Nothing here right now"
var emptyMessage = "Run a scan or adjust your scan locations in Settings."
```

Render `subtitle` below the title when supplied, and pass the configurable empty copy into `EmptyStateView`.

Add the `ContentView` route:

```swift
case .readyToDelete:
  ResultsView(
    title: "Ready to Delete",
    filter: ResultPresentation.isReadyToDeleteCache,
    subtitle: "High-confidence cache files that apps can recreate.",
    emptyTitle: "No cache files are ready",
    emptyMessage: "Run a scan to look for high-confidence cache files that can safely move to Trash."
  )
```

- [ ] **Step 3: Add the global selection summary to the results header**

When `model.selectionSummary.itemCount > 0`, replace the lone review button area with:

```swift
HStack(spacing: 10) {
  Text(
    "\(model.selectionSummary.itemCount) selected · "
      + ByteCount.string(model.selectionSummary.totalBytes)
  )
  .font(.subheadline.weight(.medium))
  .foregroundStyle(.secondary)
  .monospacedDigit()

  Button("Clear") {
    model.clearSelection()
    rangeAnchorID = nil
  }

  Button {
    showsReview = true
  } label: {
    Label("Review Cleanup", systemImage: "checklist")
  }
  .buttonStyle(.borderedProminent)
  .tint(BrandTheme.scopeForest)
}
```

When no valid items are selected, retain the existing disabled `Review Cleanup` button. Base its disabled state on `model.selectionSummary.itemCount == 0`, not raw stale IDs.

- [ ] **Step 4: Build and run the app verification bundle**

Run:

```bash
./script/swiftpm.sh build
./script/swiftpm.sh test
./script/build_and_run.sh --verify
```

Expected: all commands PASS, and the app bundle is produced.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanScopeApp/AppModel.swift Sources/CleanScopeApp/Views/ResultsView.swift Sources/CleanScopeApp/Views/ContentView.swift
git commit -m "feat: add ready-to-delete cache section"
```

---

### Task 5: Runtime QA and Verification Record

**Files:**
- Modify: `VERIFY.md`

- [ ] **Step 1: Launch and verify the main interaction path**

Run:

```bash
./script/build_and_run.sh
```

Verify:

1. Run or load a scan containing at least three eligible rows and one ineligible row.
2. Open `Ready to Delete`; confirm only high-confidence deletable cache paths appear.
3. Click the header checkbox; confirm every eligible visible row becomes selected and the ineligible row does not.
4. Click it again; confirm only visible eligible rows are deselected.
5. Select one row, then Shift-click a later row; confirm the inclusive eligible range follows the target row’s new selected state.
6. Navigate to another results section; confirm selection persists and the summary describes the global review payload.
7. Click `Clear`; confirm every selection disappears.
8. Select cache rows, open `Review Cleanup`, and confirm the review sheet receives exactly those valid rows.

- [ ] **Step 2: Verify accessibility, appearance, and narrow layouts**

Check:

- keyboard focus reaches row and header checkboxes
- Space activates a focused checkbox
- VoiceOver labels distinguish individual selection from select-all
- mixed select-all state is announced as partially selected
- disabled/protected/excluded rows cannot be selected
- light and dark appearances preserve checkbox contrast
- the selection summary remains readable at the minimum supported window width
- long file names do not overlap the checkbox or summary

- [ ] **Step 3: Record verification**

Append a dated section to `VERIFY.md`:

```markdown
## 2026-06-24 — Bulk selection and ready cache

- `./script/swiftpm.sh test`: passed
- `./script/swiftpm.sh build`: passed
- `./script/build_and_run.sh --verify`: passed
- Ready-to-Delete cache predicate: verified with Library, package-manager, excluded, protected, log, Trash, and generated-folder examples
- Select all visible: verified for none, mixed, and all states
- Shift-click range selection: verified in both selection and deselection directions
- Cleanup review payload: verified against valid selected rows
- Accessibility, light/dark appearance, and narrow-window checks: passed
```

- [ ] **Step 4: Run final automated verification**

Run:

```bash
git diff --check
./script/swiftpm.sh test
./script/swiftpm.sh build
./script/build_and_run.sh --verify
git status --short
```

Expected: no whitespace errors; all build and test commands PASS; only the intended verification documentation is uncommitted.

- [ ] **Step 5: Commit**

```bash
git add VERIFY.md
git commit -m "test: verify bulk cache selection"
```
