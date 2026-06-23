# CleanScope Space Garden Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved Space Garden redesign, Sprout Lens identity, production app icon, and brandkit across the existing native macOS CleanScope application.

**Architecture:** Preserve all core scan, classification, persistence, and deletion services. Add a small `CleanScopePresentation` layer inside `CleanScopeCore` for deterministic display calculations, reusable SwiftUI brand components inside `CleanScopeApp`, generated brand assets under `Assets/Brand`, and bundle the icon through the existing SwiftPM staging script.

**Tech Stack:** Swift 5 language mode, SwiftUI, Foundation, Swift Testing, CoreGraphics/AppKit asset generation, SwiftPM, macOS 13+.

---

## File Structure

- `Sources/CleanScopeCore/Presentation.swift`: pure display summaries, selected-item totals, contextual copy, and scan growth stages.
- `Tests/CleanScopeCoreTests/PresentationTests.swift`: presentation behavior tests.
- `Sources/CleanScopeApp/Brand/BrandTheme.swift`: adaptive palette and layout constants.
- `Sources/CleanScopeApp/Brand/BrandMarkView.swift`: scalable Sprout Lens SwiftUI mark.
- `Sources/CleanScopeApp/Brand/GrowthSummaryView.swift`: reclaimable-space surface and growth illustration.
- `Sources/CleanScopeApp/Brand/StorageMetricView.swift`: compact dashboard metric.
- `Sources/CleanScopeApp/Brand/PermissionBannerView.swift`: expandable permission guidance.
- `Sources/CleanScopeApp/Brand/CleanupCelebrationView.swift`: reduced-motion-aware completion treatment.
- `Sources/CleanScopeApp/Views/CleanupReviewSheet.swift`: detailed move-to-Trash review.
- `Sources/CleanScopeApp/Views/DashboardView.swift`: branded overview and Quick Wins.
- `Sources/CleanScopeApp/Views/SidebarView.swift`: branded native sidebar.
- `Sources/CleanScopeApp/Views/ResultsView.swift`: summaries, last-modified column, action menu, and review sheet.
- `Sources/CleanScopeApp/Views/ItemDetailView.swift`: structured item inspector.
- `Sources/CleanScopeApp/Views/CleanupReportView.swift`: before/after and completion result.
- `Sources/CleanScopeApp/Views/SettingsView.swift`: compact branded settings header.
- `Sources/CleanScopeApp/Views/EmptyStateView.swift`: friendly branded empty state.
- `Sources/CleanScopeApp/AppModel.swift`: exclusion command and presentation state only.
- `Assets/Brand/*`: vector masters, PNG sizes, and `.icns`.
- `BRANDKIT.md`: production usage guide.
- `script/generate_brand_assets.swift`: deterministic vector/raster asset generator.
- `script/build_and_run.sh`: copies the icon into the app bundle and declares it in `Info.plist`.

---

### Task 1: Presentation Logic

**Files:**
- Create: `Sources/CleanScopeCore/Presentation.swift`
- Create: `Tests/CleanScopeCoreTests/PresentationTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import CleanScopeCore

@Suite struct PresentationTests {
  @Test func reclaimCopyScalesWithRecoveredSpace() {
    #expect(StoragePresentation.reclaimCopy(bytes: 0) == "Your Mac is already breathing easy.")
    #expect(StoragePresentation.reclaimCopy(bytes: 700_000_000).contains("side project"))
    #expect(StoragePresentation.reclaimCopy(bytes: 7_000_000_000).contains("photos"))
  }

  @Test func selectionSummaryCountsBytesAndCategories() {
    let items = [
      ScanResult.fixture(path: "/tmp/a", sizeBytes: 100, category: .safeToDelete),
      ScanResult.fixture(path: "/tmp/b", sizeBytes: 50, category: .probablyUnused),
    ]
    let summary = SelectionSummary(items: items)
    #expect(summary.itemCount == 2)
    #expect(summary.totalBytes == 150)
    #expect(summary.categoryCounts[.safeToDelete] == 1)
  }

  @Test func growthStageIsBounded() {
    #expect(StoragePresentation.growthStage(resultCount: 0, isScanning: false) == 0)
    #expect(StoragePresentation.growthStage(resultCount: 1, isScanning: true) == 1)
    #expect(StoragePresentation.growthStage(resultCount: 50, isScanning: true) == 3)
  }
}
```

- [ ] **Step 2: Verify RED**

Run:

```bash
./script/swiftpm.sh test --filter PresentationTests
```

Expected: FAIL because `StoragePresentation` and `SelectionSummary` do not exist.

- [ ] **Step 3: Implement the pure presentation types**

```swift
import Foundation

public struct SelectionSummary: Equatable, Sendable {
  public let itemCount: Int
  public let totalBytes: Int64
  public let categoryCounts: [SafetyCategory: Int]

  public init(items: [ScanResult]) {
    itemCount = items.count
    totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
    categoryCounts = Dictionary(grouping: items, by: \.category).mapValues(\.count)
  }
}

public enum StoragePresentation {
  public static func reclaimCopy(bytes: Int64) -> String {
    switch bytes {
    case ..<1: return "Your Mac is already breathing easy."
    case ..<1_000_000_000: return "A little more room for your next side project."
    default: return "Enough room for thousands of photos or a few ambitious side projects."
    }
  }

  public static func growthStage(resultCount: Int, isScanning: Bool) -> Int {
    guard isScanning || resultCount > 0 else { return 0 }
    if resultCount < 10 { return 1 }
    if resultCount < 40 { return 2 }
    return 3
  }
}
```

- [ ] **Step 4: Verify GREEN**

Run:

```bash
./script/swiftpm.sh test --filter PresentationTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanScopeCore/Presentation.swift Tests/CleanScopeCoreTests/PresentationTests.swift
git commit -m "feat: add storage presentation summaries"
```

---

### Task 2: Brand Assets And App Icon

**Files:**
- Create: `script/generate_brand_assets.swift`
- Create: `Assets/Brand/CleanScopeMark.svg`
- Create: `Assets/Brand/CleanScopeWordmark.svg`
- Create: `Assets/Brand/CleanScopeLockup.svg`
- Create: `Assets/Brand/AppIcon-*.png`
- Create: `Assets/Brand/CleanScope.icns`
- Create: `BRANDKIT.md`
- Modify: `script/build_and_run.sh`

- [ ] **Step 1: Add a deterministic asset generator**

The Swift script must draw the approved Sprout Lens with CoreGraphics/AppKit:

```swift
let forest = NSColor(calibratedRed: 23/255, green: 111/255, blue: 93/255, alpha: 1)
let leaf = NSColor(calibratedRed: 80/255, green: 183/255, blue: 122/255, alpha: 1)
let mint = NSColor(calibratedRed: 223/255, green: 242/255, blue: 232/255, alpha: 1)
```

For each requested size, draw a macOS rounded-square mint field, a forest lens ring and handle, two leaf paths, and a stem. Write PNG files and use `iconutil` to create `CleanScope.icns`.

- [ ] **Step 2: Add vector masters and brand guide**

The SVG masters must use the same geometry and exact palette from `DESIGN.md`. `BRANDKIT.md` must document identity rationale, clear space equal to one leaf height, 16 px minimum mark size, palette, type, voice, motion, safety usage, and misuse.

- [ ] **Step 3: Generate and inspect assets**

Run:

```bash
swift script/generate_brand_assets.swift
file Assets/Brand/AppIcon-1024.png Assets/Brand/CleanScope.icns
```

Expected: both files exist and report valid image/icon formats.

- [ ] **Step 4: Bundle the icon**

Update `script/build_and_run.sh` to copy `Assets/Brand/CleanScope.icns` to `Contents/Resources/CleanScope.icns`, create the resources directory, and add:

```xml
<key>CFBundleIconFile</key>
<string>CleanScope</string>
```

- [ ] **Step 5: Verify bundle**

Run:

```bash
./script/build_and_run.sh --verify
test -f dist/CleanScope.app/Contents/Resources/CleanScope.icns
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/CleanScope.app/Contents/Info.plist
```

Expected: icon exists and plist value is `CleanScope`.

- [ ] **Step 6: Commit**

```bash
git add Assets BRANDKIT.md script/generate_brand_assets.swift script/build_and_run.sh
git commit -m "feat: add Sprout Lens brand assets"
```

---

### Task 3: Theme And Reusable Brand Components

**Files:**
- Create: `Sources/CleanScopeApp/Brand/BrandTheme.swift`
- Create: `Sources/CleanScopeApp/Brand/BrandMarkView.swift`
- Create: `Sources/CleanScopeApp/Brand/GrowthSummaryView.swift`
- Create: `Sources/CleanScopeApp/Brand/StorageMetricView.swift`
- Create: `Sources/CleanScopeApp/Brand/PermissionBannerView.swift`
- Create: `Sources/CleanScopeApp/Brand/CleanupCelebrationView.swift`

- [ ] **Step 1: Implement semantic adaptive colors**

Use `Color(nsColor:)` with dynamic `NSColor` providers for every token in `DESIGN.md`. Define shared 8 px radius and 180 ms animation duration.

- [ ] **Step 2: Implement the scalable Sprout Lens**

Draw the ring, handle, stem, and two leaves using SwiftUI `Circle`, `Capsule`, and custom leaf `Shape`. Provide `BrandMarkView(size:)` and accessibility label `CleanScope`.

- [ ] **Step 3: Implement dashboard components**

`GrowthSummaryView` accepts `cleanableBytes`, `resultCount`, `isScanning`, and `reduceMotion`. `StorageMetricView` accepts label, bytes/count value, symbol, and tint. `PermissionBannerView` accepts `PermissionSummary` and owns only disclosure state.

- [ ] **Step 4: Implement completion feedback**

`CleanupCelebrationView` accepts recovered bytes and `reduceMotion`; it animates once on appearance and becomes a static crossfade when Reduce Motion is enabled.

- [ ] **Step 5: Build**

Run:

```bash
./script/swiftpm.sh build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanScopeApp/Brand
git commit -m "feat: add Space Garden design components"
```

---

### Task 4: Dashboard And Sidebar

**Files:**
- Modify: `Sources/CleanScopeApp/Views/DashboardView.swift`
- Modify: `Sources/CleanScopeApp/Views/SidebarView.swift`

- [ ] **Step 1: Replace dashboard hierarchy**

Build the first viewport in this order:

1. Sprout Lens, “Your Mac has room to grow,” last scan/result count, rescan/cancel.
2. `GrowthSummaryView`.
3. Three compact metrics: available, safe/generated, review count.
4. Permission banner.
5. Quick Wins table filtered to safe high-confidence results.

- [ ] **Step 2: Brand the native sidebar**

Add a mark-and-wordmark header above the native list. Preserve source-list rows and the bottom scan command. Use `tint(BrandTheme.scopeForest)` without custom card rows.

- [ ] **Step 3: Runtime checkpoint**

Run:

```bash
./script/build_and_run.sh --verify
```

Inspect the default 1040 × 680 window in light and dark mode. Expected: growth summary and Quick Wins heading are visible, sidebar labels fit, no overlap.

- [ ] **Step 4: Commit**

```bash
git add Sources/CleanScopeApp/Views/DashboardView.swift Sources/CleanScopeApp/Views/SidebarView.swift
git commit -m "feat: redesign dashboard and sidebar"
```

---

### Task 5: Results, Review Sheet, And Item Detail

**Files:**
- Create: `Sources/CleanScopeApp/Views/CleanupReviewSheet.swift`
- Modify: `Sources/CleanScopeApp/Views/ResultsView.swift`
- Modify: `Sources/CleanScopeApp/Views/ItemDetailView.swift`
- Modify: `Sources/CleanScopeApp/AppModel.swift`

- [ ] **Step 1: Add exclusion behavior**

Inject `ExclusionStore` into `AppModel`, expose `exclude(_:)`, persist a recursive rule for folders or exact-path rule for files, remove the item from selection, and mark matching streamed results excluded.

- [ ] **Step 2: Add results summary and columns**

Show filtered item count and total bytes. Add Last Modified and an ellipsis action menu with Open in Finder, Exclude, and Move to Trash when allowed. Keep category icon plus text.

- [ ] **Step 3: Add cleanup review sheet**

Use `SelectionSummary` to display item count, bytes, category breakdown, risk copy, Cancel, and the exact destructive command “Move Selected Items to Trash.”

- [ ] **Step 4: Redesign detail**

Use grouped inspector sections for safety, metadata, explanation, and actions. Add Exclude and Move to Trash only when operational.

- [ ] **Step 5: Build and runtime-check**

Run:

```bash
./script/swiftpm.sh test
./script/build_and_run.sh --verify
```

Expected: tests pass; safe rows select; risky rows remain disabled; review sheet has totals; exclusion removes selection.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanScopeApp/AppModel.swift Sources/CleanScopeApp/Views/ResultsView.swift Sources/CleanScopeApp/Views/ItemDetailView.swift Sources/CleanScopeApp/Views/CleanupReviewSheet.swift
git commit -m "feat: improve cleanup review experience"
```

---

### Task 6: Cleanup Report, Settings, And Empty States

**Files:**
- Modify: `Sources/CleanScopeApp/Views/CleanupReportView.swift`
- Modify: `Sources/CleanScopeApp/Views/SettingsView.swift`
- Modify: `Sources/CleanScopeApp/Views/EmptyStateView.swift`

- [ ] **Step 1: Redesign cleanup completion**

Place `CleanupCelebrationView` first, show before/after available bytes, then compact outcome sections with zero-count states, remaining recommendations, and a Rescan command.

- [ ] **Step 2: Add branded settings header**

Use a compact Sprout Lens, product name, and tagline above the native grouped form. Preserve all native toggles and the large-file stepper.

- [ ] **Step 3: Improve empty states**

Allow `EmptyStateView` to use either an SF Symbol or `BrandMarkView`, accept an optional command label/action, and use friendly practical copy per destination.

- [ ] **Step 4: Build and inspect**

Run:

```bash
./script/swiftpm.sh build
./script/build_and_run.sh --verify
```

Expected: report, settings, and empty states render in light and dark mode without clipping.

- [ ] **Step 5: Commit**

```bash
git add Sources/CleanScopeApp/Views/CleanupReportView.swift Sources/CleanScopeApp/Views/SettingsView.swift Sources/CleanScopeApp/Views/EmptyStateView.swift
git commit -m "feat: add branded completion and settings"
```

---

### Task 7: Accessibility And Motion QA

**Files:**
- Modify: affected `Sources/CleanScopeApp/**/*.swift`
- Modify: `VERIFY.md`

- [ ] **Step 1: Audit accessibility labels**

Every brand mark has an accessibility label or is hidden when decorative. Every safety row announces category and selection availability. Icon-only buttons have help text.

- [ ] **Step 2: Verify reduced motion**

Use `@Environment(\.accessibilityReduceMotion)` in growth, selection, and completion components. No destructive confirmation animates.

- [ ] **Step 3: Verify key states**

Update `VERIFY.md` with dashboard empty/scanning/completed, permission-limited, safe selection, review sheet, cleanup report, light/dark, reduced-motion, app icon, minimum window, and expanded window checks.

- [ ] **Step 4: Run full automated verification**

```bash
./script/swiftpm.sh test
./script/swiftpm.sh build
xcrun swift-format lint -r Sources Tests Package.swift
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add Sources VERIFY.md
git commit -m "test: verify Space Garden accessibility"
```

---

### Task 8: Final Runtime And Asset Audit

**Files:**
- Verify all redesign files and assets.

- [ ] **Step 1: Launch final bundle**

```bash
./script/build_and_run.sh --verify
```

Expected: CleanScope launches with the custom Dock icon.

- [ ] **Step 2: Inspect live UI**

Use Computer Use to inspect:

- Default light dashboard.
- Dark dashboard.
- Scanning/cancel state.
- Safe Cleanup with selection.
- Review sheet.
- Settings.
- Cleanup report or fixture-driven completion state.

- [ ] **Step 3: Verify artifacts**

```bash
test -f Assets/Brand/CleanScopeMark.svg
test -f Assets/Brand/CleanScopeLockup.svg
test -f Assets/Brand/AppIcon-1024.png
test -f Assets/Brand/CleanScope.icns
test -f BRANDKIT.md
test -z "$(git status --porcelain)"
```

Expected: all checks pass.

---

## Self-Review

- **Spec coverage:** Tasks cover identity assets, app icon, brandkit, reusable presentation components, dashboard, sidebar, results, cleanup review, item detail, cleanup report, settings, empty states, motion, accessibility, and runtime verification.
- **Safety:** Core classification remains unchanged; no automatic or permanent deletion is introduced.
- **Type consistency:** `SelectionSummary`, `StoragePresentation`, `BrandTheme`, and all component inputs remain consistent across tasks.
- **Placeholder scan:** No deferred implementation language or unspecified code task remains.
