# Living Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give CleanScope a data-driven animated interface: a Field Lens Storage Map, terrarium moments, a 3D module icon family and six motion studies, on top of the merged audit fixes.

**Architecture:** All layout and threshold logic lives in `CleanScopeCore` as pure, tested functions (palette, treemap colouring, terrarium layers, sprout stage, weather). `CleanScopeApp` only draws, gated by one `MotionPolicy`. 3D icons are pre-rendered by a SceneKit script into committed PNGs; the terrarium is a live SceneKit scene shown in two places only.

**Tech Stack:** Swift 6 toolchain (Swift 5 language mode), SwiftUI on macOS 14+, SceneKit, Metal (`.layerEffect` shader), Swift Testing, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-10-20-living-interface-design.md`

## Global Constraints

- Minimum platform: `.macOS(.v14)`; `MeshGradient` only behind `if #available(macOS 15, *)`.
- Real numbers drive motion; nothing animates toward an invented value. Sample data only in debug snapshot mode.
- `CleanupReviewSheet`, item detail and confirmations have no ambient motion.
- Every animated surface has a Reduce Motion version; views read motion permission only through `MotionPolicy`.
- 3D scenes and particles stop when off-screen, when the window is occluded or minimised, and in Low Power Mode.
- No sound, confetti, points, streaks, levels, countdowns, red alarms or "critical" copy. Disk weather never uses the destructive colour.
- Text over any new fill or gradient is ≥ 4.5:1 in light and dark.
- The sidebar, tables and dialogs keep SF Symbols; 3D icons never appear there.
- Byte totals use `ResultPresentation.totalBytes` (nested folders counted once).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Verification commands: `./script/swiftpm.sh test`, `./script/swiftpm.sh build`, `./script/build_and_run.sh --verify`, and the snapshot run `dist/CleanScope.app/Contents/MacOS/CleanScopeApp --snapshot-dir <dir> [--dark-preview] [--snapshot-empty] [--reduce-motion]`.

## Review Focus

1. **Scan cancelled midway (⌘.)** — progress stops, the sweep band and scan theatre settle on what was found, the hero leaves "Scanning". Test: Task 6 `cancellingStopsProgressCallbacks`; Task 12 snapshot of a cancelled scan.
2. **Bulk selection of thousands of items** ("Select all visible" on Ready to Delete) — the basket counts instantly and plays at most one chip flight, never thousands. Test: Task 15 `bulkSelectionPlaysOneFlight`.
3. **Never scanned / zero bytes / disk total unknown (0)** — terrarium, weather and sprout show neutral states with no NaN, division by zero or negative heights. Tests: Task 13 `zeroBytesGivesMinimumHeights`, Task 19 `unknownDiskTotalIsPlentyOfRoom`, Task 18 `noCleanupLogFallsBackToFirstLaunch`.
4. **Text on new fills and gradients in dark mode** — tile labels on category fills and hero copy on both weather ends stay readable. Tests: Task 10 `tileLabelsMeetContrastOnEveryFill`, Task 19 `weatherTextMeetsContrastAtBothEnds`.
5. **Window minimised or app hidden during a scan** — terrarium and particles stop drawing and resume on return. Test: Task 3 `occludedWindowStopsAmbientMotion`, plus the Task 14 Instruments check.

---

## Phase 0 · Foundation

### Task 1: Merge `fix/audit-findings` into the gap-features branch

**Files:**
- Modify (conflicts): `Sources/CleanScopeApp/AppModel.swift`, `CleanScopeApp.swift`, `Views/{CleanupReportView,CleanupReviewSheet,ContentView,DashboardView,ItemDetailView,ResultsView,SettingsView,SidebarView}.swift`, `Sources/CleanScopeCore/Models.swift`, `VERIFY.md`
- Restore: `Sources/CleanScopeApp/Brand/StorageMetricView.swift` (deleted by the audit, still used by `MemoryView`, `ProtectionView`, `SystemSpaceCard`)

**Interfaces:**
- Produces: merged `AppModel` with audit APIs (`cleanup(_ items: [ScanResult]) async`, `results(for:)`, `currentResult(for:)`, `counts`, `summary`, `MotionPolicy` slot added in Task 3) **and** gap-features APIs (`statusMonitor`, `settingBinding`, `startScan(paths:mode:settings:)`, `scanDrive(at:)`, `emptyTrash()`, `activeRules`).

- [ ] **Step 1:** In the main checkout delete the untracked `docs/audits/` folder (an identical copy is on the audit branch), then `git merge fix/audit-findings`.
- [ ] **Step 2:** Resolve each conflict with the spec's conflict policy (spec §0.1). Rules that decide the hard cases:
  - `AppModel.Destination`: audit's enum shape (`title`, `systemImage`, `subtitle`, `emptyTitle`, `isResultList`, `includes(_:largeFileThreshold:)`) with gap-features' extra cases `storageMap, leftovers, maintenance, loginItems, backgroundItems, memory, protection, privacy`; drop `.settings`; rename `.cleanupHistory` → `.lastCleanup`.
  - `startScan`: keep gap-features' `startScan(paths:mode:settings:)` signature and leftover/preselection logic, but stream through the audit's batched `enqueue(_:)` and apply `ExclusionRule.applying`.
  - `cleanup`: audit's `cleanup(_ items:)` using `ResultSelection.cleanupPlan`; keep any gap-features permanent-delete option as a parameter passed through to `DeletionService`.
  - `Models.swift`: union of both; `ScanSummary` keeps the audit's outermost byte counting.
  - Remove `BrandTheme.triggerHaptic()` calls.
- [ ] **Step 3:** Restore `StorageMetricView` with `git checkout HEAD -- Sources/CleanScopeApp/Brand/StorageMetricView.swift` (during the merge `HEAD` is the gap-features side), re-tokened (`BrandTheme.surfaceRaised`, `.textPrimary`, `.textSecondary`, `.hairline`, `BrandTheme.radius`).
- [ ] **Step 4:** Run `./script/swiftpm.sh test`. Expected: all suites pass, including the audit's `cleanupPlan*`, `outermost*`, `ExclusionRuleTests` and gap-features' suites.
- [ ] **Step 5:** Commit the merge: `git commit` (default merge message plus the co-author line).

### Task 2: Re-token gap-features views and wire the new sidebar sections

**Files:**
- Modify: `Views/{LaunchItemsView,MacStatusCard,MaintenanceView,MemoryView,MenuBarContentView,PrivacyView,ProtectionView,StorageMapView,SystemSpaceCard}.swift`, `AppModel.swift` (`Destination.sections`), `ContentView.swift` (detail switch), `DebugSnapshot.swift`

**Interfaces:**
- Produces: `AppModel.Destination.sections: [(title: String, destinations: [Destination])]` =
  Overview `[.dashboard, .storageMap, .readyToDelete, .safeCleanup]`, Browse `[.largeFiles, .hiddenFolders, .developerFiles, .appSupport, .downloads, .trash, .leftovers]`, Performance `[.maintenance, .loginItems, .backgroundItems, .memory]`, Protection `[.protection, .privacy]`, Activity `[.lastCleanup]`.

- [ ] **Step 1:** Replace old token names: `cream→surface`, `clay→surfaceRaised`, `bark/deepInk→textPrimary`, `warmGray→textSecondary`, `sage/scopeForest→accent` (fills) or `accentText` (text), `moss/freshLeaf→safe`, `amber/sunToken→review`, `terracotta/actionCoral→destructive`, `finderBlue→info`, `openMint→surfaceRaised`.
- [ ] **Step 2:** Run `grep -rnE "BrandTheme\.(cream|clay|bark|deepInk|warmGray|sage|scopeForest|moss|freshLeaf|amber|sunToken|terracotta|actionCoral|finderBlue|openMint|clearPaper|secondarySurface)" Sources`. Expected: no output.
- [ ] **Step 3:** `./script/swiftpm.sh build` with no warnings; `./script/build_and_run.sh --verify`; snapshot run light and dark. Expected: one PNG per destination (19 destinations), none blank, sidebar row count from the view-tree dump = 5 headers + 19 rows.
- [ ] **Step 4:** Commit `refactor: move gap-features views onto role tokens and sidebar sections`.

### Task 3: macOS 14 floor and `MotionPolicy`

**Files:**
- Modify: `Package.swift` (`.macOS(.v14)`), `script/build_and_run.sh` (`MIN_SYSTEM_VERSION="14.0"`), `Brand/BrandTheme.swift` (`animation(_:)` takes the policy)
- Create: `Sources/CleanScopeCore/MotionDecision.swift`, `Sources/CleanScopeApp/MotionPolicy.swift`
- Test: `Tests/CleanScopeCoreTests/MotionDecisionTests.swift`

**Interfaces:**
- Produces (Core): `public struct MotionDecision: Equatable { public var allowsAmbientMotion: Bool; public var allowsTransitions: Bool; public init(reduceMotion: Bool, lowPower: Bool, windowVisible: Bool, appActive: Bool) }`
- Produces (App): `@MainActor final class MotionPolicy: ObservableObject { @Published private(set) var decision: MotionDecision; var allowsAmbientMotion: Bool; var allowsTransitions: Bool; func animation(_ base: Animation = .easeOut(duration: 0.2)) -> Animation?; func attach(to window: NSWindow) }` — owned by `AppModel` as `let motion: MotionPolicy` and injected with `.environmentObject`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func reduceMotionStopsEverything() {
  let d = MotionDecision(reduceMotion: true, lowPower: false, windowVisible: true, appActive: true)
  #expect(!d.allowsAmbientMotion); #expect(!d.allowsTransitions)
}
@Test func lowPowerStopsAmbientButKeepsTransitions() {
  let d = MotionDecision(reduceMotion: false, lowPower: true, windowVisible: true, appActive: true)
  #expect(!d.allowsAmbientMotion); #expect(d.allowsTransitions)
}
@Test func occludedWindowStopsAmbientMotion() {
  let d = MotionDecision(reduceMotion: false, lowPower: false, windowVisible: false, appActive: true)
  #expect(!d.allowsAmbientMotion); #expect(d.allowsTransitions)
}
@Test func normalConditionsAllowBoth() {
  let d = MotionDecision(reduceMotion: false, lowPower: false, windowVisible: true, appActive: true)
  #expect(d.allowsAmbientMotion); #expect(d.allowsTransitions)
}
```

- [ ] **Step 2:** Run `./script/swiftpm.sh test`. Expected: FAIL, `cannot find 'MotionDecision'`.
- [ ] **Step 3:** Implement `MotionDecision` (ambient = !reduceMotion && !lowPower && windowVisible && appActive; transitions = !reduceMotion). Implement `MotionPolicy` observing `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, `.NSProcessInfoPowerStateDidChange`, `NSWindow.didChangeOcclusionStateNotification`, `NSApplication.didBecomeActive/ResignActiveNotification`. Debug flag `--reduce-motion` forces `reduceMotion = true`. `BrandTheme.animation(_:)` becomes `motion.animation()`; replace every `BrandTheme.animation(reduceMotion)` call and every direct `accessibilityReduceMotion` read in views.
- [ ] **Step 4:** Run tests and build. Expected: PASS, no warnings; `grep -rn "accessibilityReduceMotion" Sources/CleanScopeApp/Views` returns nothing.
- [ ] **Step 5:** Commit `feat: raise floor to macOS 14 and centralise motion in MotionPolicy`.

### Task 4: App resource bundle

**Files:**
- Modify: `Package.swift` (`resources: [.process("Resources")]` on `CleanScopeApp`), `script/build_and_run.sh` (copy `CleanScope_CleanScopeApp.bundle` into `$APP_RESOURCES`)
- Create: `Sources/CleanScopeApp/Resources/.keep`, `Sources/CleanScopeApp/Brand/Bundle+CleanScope.swift`

**Interfaces:**
- Produces: `extension Bundle { static let cleanScope: Bundle }` — `Bundle.main.resourceURL/CleanScope_CleanScopeApp.bundle` if present, else `Bundle.module`.

- [ ] **Step 1:** Add the resource rule, accessor and copy step.
- [ ] **Step 2:** `./script/build_and_run.sh --verify`, then `ls dist/CleanScope.app/Contents/Resources`. Expected: `CleanScope_CleanScopeApp.bundle` listed and the app launches.
- [ ] **Step 3:** Commit `build: ship an app resource bundle`.

### Task 5: Cleanup log

**Files:**
- Create: `Sources/CleanScopeCore/CleanupLogStore.swift`
- Modify: `Sources/CleanScopeApp/AppModel.swift` (`cleanup(_:)` appends; publish `cleanupLog`)
- Test: `Tests/CleanScopeCoreTests/StoreTests.swift`

**Interfaces:**
- Produces: `public struct CleanupLogEntry: Codable, Equatable, Sendable { public var completedAt: Date; public var recoveredBytes: Int64 }`; `public struct CleanupLogStore: Sendable { public init(fileURL: URL? = nil); public func load() throws -> [CleanupLogEntry]; public func append(_ entry: CleanupLogEntry) throws }` (newest first, capped at 50; default file `Application Support/CleanScope/cleanup-log.json`). `AppModel.cleanupLog: [CleanupLogEntry]`, `AppModel.firstLaunchDate: Date` (stored in `UserDefaults` key `firstLaunchDate` on first run).

- [ ] **Step 1: Write the failing tests** `cleanupLogRoundTripsNewestFirst` (append three dated entries, `load()` returns them newest first) and `cleanupLogKeepsFifty` (append 55, `load().count == 50`, oldest five gone).
- [ ] **Step 2:** Run tests. Expected: FAIL, `cannot find 'CleanupLogStore'`.
- [ ] **Step 3:** Implement the store (atomic JSON write, same pattern as `ExclusionStore`). Append in `AppModel.cleanup(_:)` after a session with `deletedItems` non-empty; surface write errors through `report(_:_:)`.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: keep a log of confirmed cleanups`.

### Task 6: Scan progress

**Files:**
- Modify: `Sources/CleanScopeCore/ScannerService.swift` (`scan`, `scanRoots`), `Sources/CleanScopeApp/AppModel.swift`
- Test: `Tests/CleanScopeCoreTests/ScannerServiceTests.swift`

**Interfaces:**
- Produces: `ScannerService.scan(paths:mode:settings:onProgress:onResult:)` with `onProgress: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in }`; `total` = number of `WorkItem`s (top-level children across roots, plus one per root with no children); called once per finished item. `AppModel.scanProgress: Double` (0…1, reset to 0 at scan start, 1 at completion) and `AppModel.latestStreamedCategory: SafetyCategory?` (category of the last result in each flushed batch).

- [ ] **Step 1: Write the failing tests**
  - `progressReachesCompletionOnce`: scan a temp tree with 3 roots × 4 children (total 12); collect callbacks; `#expect(calls.last?.0 == 12 && calls.last?.1 == 12)`, `#expect(calls.filter { $0.0 == $0.1 }.count == 1)`, completed values strictly increasing.
  - `cancellingStopsProgressCallbacks`: cancel from inside the first `onProgress` callback; `#expect(calls.count < total)` and no call after `scan` returns.
- [ ] **Step 2:** Run tests. Expected: FAIL (extra argument `onProgress`).
- [ ] **Step 3:** Count work items before dispatch; increment and report as each `group.next()` returns; skip reporting once `cancellationState.isCancelled`. Wire `AppModel`: `scanProgress = Double(completed) / Double(max(total, 1))` on the main actor.
- [ ] **Step 4:** Add the debug flag `--snapshot-scan-progress <0…1>` to `DebugSnapshot`: it sets `isScanning = true`, `scanProgress` to the value and streams that fraction of the saved scan's results, so later tasks can snapshot mid-scan states.
- [ ] **Step 5:** Run tests. Expected: PASS, existing scanner tests unchanged.
- [ ] **Step 6:** Commit `feat: report scan progress`.

---

## Phase 1 · 3D Icon Family

### Task 7: Icon renderer and committed assets

**Files:**
- Create: `script/render_icons.swift`, `Sources/CleanScopeCore/ModuleIconKey.swift`, `Sources/CleanScopeApp/Resources/Icons/*.png`
- Test: `Tests/CleanScopeCoreTests/ModuleIconAssetTests.swift`

**Interfaces:**
- Produces: `public enum ModuleIconKey: String, CaseIterable, Sendable { case scan, cleanup, map, large, dev, downloads, leftovers, maintenance, memory, login, protection, privacy }`; files `Icons/<key>@1x.png` (64 px), `@2x` (128), `@3x` (192), `Icons/<key>-hover-00…17.png` (128 px).

- [ ] **Step 1: Write the failing test** `everyIconHasStillsAndHoverFrames`: for each `ModuleIconKey`, using `URL(fileURLWithPath: #filePath)` → `../../Sources/CleanScopeApp/Resources/Icons`, `#expect` the three stills and 18 hover frames exist, and each still's pixel width equals 64/128/192 (`CGImageSourceCreateWithURL` → `kCGImagePropertyPixelWidth`).
- [ ] **Step 2:** Run tests. Expected: FAIL (files missing).
- [ ] **Step 3:** Write the renderer. Geometry, palette and per-icon hover actions are those of the concept board (`ICONS` object in the artifact, reproduced in spec Phase 1 table): SceneKit `SCNShape` for extrusions with chamfer 0.05, `SCNTorus`, `SCNCapsule`, `SCNBox(chamferRadius:)`, `SCNCylinder`, `SCNCone`. Material `physicallyBased`, roughness 0.42, clearcoat 0.55. Camera FOV 26°, position (0, 0.55, 5.7) looking at (0, −0.05, 0). Key light warm directional from (−2.5, 4, 3.5) plus a studio `lightingEnvironment` image generated procedurally. Contact shadow: a plane with a radial-gradient texture at y = −1.08 scaled (1, 0.45). Render with `SCNRenderer.snapshot(atTime:with:antialiasingMode: .multisampling4X)`; hover frames sample the action at 18 evenly spaced times over 0.6 s. Fixed seeds, no time-dependent input.
- [ ] **Step 4:** `swift script/render_icons.swift`, run it twice, `shasum Sources/CleanScopeApp/Resources/Icons/*.png` identical both times; run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: render the 3D module icon family`.

### Task 8: `ModuleIcon` view and placements

**Files:**
- Create: `Sources/CleanScopeApp/Brand/ModuleIcon.swift`
- Modify: `Views/EmptyStateView.swift` (optional `icon: ModuleIconKey?`), module destination headers (`ResultsView`, `StorageMapView`, `MaintenanceView`, `LaunchItemsView`, `MemoryView`, `ProtectionView`, `PrivacyView`, `CleanupReportView`), `DashboardView.swift` (modules row), `MenuBarContentView.swift` (header), `AppModel.Destination` (`var icon: ModuleIconKey?`)

**Interfaces:**
- Consumes: `ModuleIconKey`, `Bundle.cleanScope`, `MotionPolicy`.
- Produces: `struct ModuleIcon: View { var key: ModuleIconKey; var size: CGFloat = 64 }`; `AppModel.Destination.icon` mapping per spec table (dashboard→scan, readyToDelete/safeCleanup→cleanup, storageMap→map, largeFiles→large, developerFiles→dev, downloads→downloads, leftovers→leftovers, maintenance→maintenance, memory→memory, loginItems/backgroundItems→login, protection→protection, privacy→privacy; others nil).

- [ ] **Step 1:** Implement `ModuleIcon`: still image picked by display scale; on hover with `allowsTransitions`, play the 18 frames once at 30 fps (`TimelineView(.animation)` keyed to hover start) and tilt ≤10° toward the pointer via `onContinuousHover` + `rotation3DEffect`; `accessibilityHidden(true)`.
- [ ] **Step 2:** Place it per spec: 64 pt in module headers and empty states, 40 pt in a Dashboard "Modules" row (icon, title, count from `model.counts`), 32 pt (`scan`) in the menu bar popover header. Confirm `grep -n "ModuleIcon" Views/SidebarView.swift Views/ResultsView.swift` shows no use inside `Table` or sidebar rows.
- [ ] **Step 3:** Snapshot run light, dark and `--reduce-motion`. Expected: icons crisp at each size, no hover artefacts in stills.
- [ ] **Step 4:** Commit `feat: place module icons in headers, empty states, dashboard and menu bar`.

---

## Phase 2 · Field Lens Storage Map

### Task 9: Map colouring and free-space tile

**Files:**
- Create: `Sources/CleanScopeCore/StorageMapPresentation.swift`
- Modify: `Tests/CleanScopeCoreTests/TreemapLayoutTests.swift`
- Test: `Tests/CleanScopeCoreTests/StorageMapPresentationTests.swift`

**Interfaces:**
- Consumes: existing `TreemapLayout.squarify(items:in:)`, `ScanNode`.
- Produces: `public enum MapTone: Equatable, Sendable { case category(SafetyCategory), unclassified, free }`; `public enum StorageMapPresentation { public static func tone(for node: ScanNode, results: [String: ScanResult]) -> MapTone; public static func items(for node: ScanNode, isVolumeRoot: Bool, freeBytes: Int64) -> [(id: String, size: Int64)] }` — the free-space item id is `"__free__"`.

- [ ] **Step 1: Write the failing tests**
  - `nodeWithResultUsesItsCategory`.
  - `folderWithoutResultUsesDominantCategoryByBytes`: children 300 B safe, 200 B review → `.category(.safeToDelete)`.
  - `folderWithNoClassifiedDescendantsIsUnclassified`.
  - `freeTileOnlyAtVolumeRoot`: `items(... isVolumeRoot: true, freeBytes: 500)` contains `("__free__", 500)`; with `false` it does not; `freeBytes: 0` adds nothing.
  - In `TreemapLayoutTests`: `worstAspectRatioIsAtMostThree` for the existing fixture, `zeroSizeItemsAreDropped`.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement (dominant category = max summed bytes over descendant nodes with results; ties → more cautious category). Fix `TreemapLayout` only if the two new layout tests fail.
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: colour the storage map by safety and add a free-space tile`.

### Task 10: Fill palette and Canvas map with lift, keyboard and VoiceOver

**Files:**
- Create: `Sources/CleanScopeCore/BrandPalette.swift`, `Sources/CleanScopeApp/Views/StorageMap/MapCanvas.swift`
- Modify: `Brand/BrandTheme.swift` (build colours from `BrandPalette`), `Views/StorageMapView.swift` (replace the `ZStack` of tile views with `MapCanvas`, keep breadcrumb, list toggle, drill-in, tile menu)
- Test: `Tests/CleanScopeCoreTests/BrandPaletteTests.swift`

**Interfaces:**
- Produces (Core): `public struct PaletteColor: Sendable { public let light: UInt32; public let dark: UInt32 }`; `public enum BrandPalette` with every existing role token plus fills `safeFill (0x86B892/0x4F8A5D)`, `reviewFill (0xE4BC6A/0xB98A35)`, `appFill (0xDE9682/0xB8644F)`, `keepFill (0xC3B8AC/0x625A53)`, `systemFill (0x9C9085/0x4A423C)`, `freeFill (0xD4ECDD/0x27443A)`, `unclassifiedFill (0xD9D2C9/0x3A3531)`; `public static func contrast(_ a: UInt32, _ b: UInt32) -> Double`; `public static func labelColor(onFill fill: PaletteColor) -> PaletteColor` (returns `textPrimary` or `surface`, whichever passes 4.5:1 in each appearance).
- Produces (App): `struct MapCanvas: View { var tiles: [MapTile]; var selection: Set<String>; @Binding var focusedID: String?; var onToggle: (String) -> Void; var onDrill: (String) -> Void }` with `struct MapTile: Identifiable { let id: String; let name: String; let bytes: Int64; let tone: MapTone; let rect: CGRect; let isSelectable: Bool }`.

- [ ] **Step 1: Write the failing tests**
  - `tileLabelsMeetContrastOnEveryFill`: for each fill, `contrast(labelColor(onFill:).light, fill.light) >= 4.5` and the same for `.dark`.
  - `roleTextTokensMeetContrastOnSurfaces`: the audit's text tokens vs `surface` and `surfaceRaised`, both appearances, ≥ 4.5.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement `BrandPalette` and switch `BrandTheme` to read from it (no value changes for existing tokens). Implement `MapCanvas`: tiles drawn in one `Canvas` (rounded rect radius 6, 2 pt gap, label name + size when rect ≥ 70 × 34 using `labelColor`); selected tiles drawn 4 pt higher with shadow (radius 14, y 6) and a check badge; hover/click via `onContinuousHover` + `SpatialTapGesture`; `.focusable()` with `onKeyPress` for arrows (reading order), space (`onToggle`), return (`onDrill`), `⌘[` handled by the existing `goUp()`; `.accessibilityRepresentation` lists tiles as buttons labelled "Name, size, safety label, selected/not selected". The base layer re-renders only when `tiles`, `selection`, size or colour scheme change (`Canvas` inside `.drawingGroup()` keyed by those inputs).
- [ ] **Step 4:** Run tests; snapshot Storage Map light/dark; build a 3,000-tile debug fixture (`--snapshot-dir … --map-fixture 3000`) and profile with Instruments Time Profiler while moving the pointer for 10 s. Expected: tests PASS; ≤ 1% dropped frames on an M1.
- [ ] **Step 5:** Commit `feat: draw the storage map in a canvas with selection lift and keyboard access`.

### Task 11: The lens

**Files:**
- Create: `Sources/CleanScopeApp/Views/StorageMap/Lens.swift`, `Sources/CleanScopeApp/Resources/Lens.metal`
- Modify: `Views/StorageMap/MapCanvas.swift`

**Interfaces:**
- Consumes: `MapCanvas` content and `focusedID`.
- Produces: `struct LensOverlay: View { var center: CGPoint; var radius: CGFloat; var zoom: CGFloat = 2.6; var tile: MapTile? }`; shader `[[ stitchable ]] half4 lens(float2 position, SwiftUI::Layer layer, float2 center, float radius, float zoom)`.

- [ ] **Step 1:** Implement: radius `min(78, max(46, width * 0.075))`; the map canvas is duplicated under a circular mask, scaled by `zoom` around `center`, with `.layerEffect(ShaderLibrary.bundle(.cleanScope).lens(...), maxSampleOffset: CGSize(width: radius, height: radius))` adding edge refraction and a rim highlight; 7 pt `accent` ring plus handle at 45°; label bubble above (or below when within 50 pt of the top) showing name · size and safety label in its text colour. Centre follows the pointer; with keyboard focus it centres on the focused tile; when neither, it rests on the largest selectable tile (no roaming). Clamp the centre so the ring stays inside the map.
- [ ] **Step 2:** Snapshot with `--snapshot-dir` in light/dark and `--reduce-motion` (lens jumps without easing). Expected: magnified content aligned under the ring centre, bubble never clipped.
- [ ] **Step 3:** Re-run the Task 10 Instruments check with the lens on. Expected: ≤ 1% dropped frames.
- [ ] **Step 4:** Commit `feat: add the Sprout Lens magnifier to the storage map`.

### Task 12: Scan sweep and collapse after cleanup

**Files:**
- Modify: `Views/StorageMapView.swift`, `Views/StorageMap/MapCanvas.swift`

**Interfaces:**
- Consumes: `AppModel.scanProgress`, `AppModel.isScanning`, `AppModel.cleanup(_:)`, `MotionPolicy`.
- Produces: `MapCanvas` gains `var revealFraction: Double` (tiles whose centre x > fraction × width draw as outlines) and `var collapsing: Set<String>` with `var collapseProgress: Double`.

- [ ] **Step 1:** While `isScanning`, `revealFraction = scanProgress` and a light band (`accentText` at 35% → clear, 90 pt wide) is drawn at the reveal edge when `allowsAmbientMotion`. When the scan ends or is cancelled, `revealFraction = 1` and the band disappears.
- [ ] **Step 2:** "Review Cleanup…" toolbar action on the map opens `CleanupReviewSheet` with `model.selectedResults()`; after confirmation, animate `collapseProgress` 0→1 over 0.7 s for trashed tile ids, then re-layout with the enlarged free tile. Reduce Motion: skip straight to the new layout.
- [ ] **Step 3:** Snapshot: mid-scan (`--snapshot-scan-progress 0.4`, from Task 6), a cancelled scan, and after a simulated cleanup in snapshot sample mode. Expected: cancelled scan shows all found tiles and no band.
- [ ] **Step 4:** Commit `feat: sweep the storage map with scan progress and collapse trashed tiles`.

---

## Phase 3 · Terrarium Moments

### Task 13: Terrarium layout

**Files:**
- Create: `Sources/CleanScopeCore/TerrariumLayout.swift`
- Test: `Tests/CleanScopeCoreTests/TerrariumLayoutTests.swift`

**Interfaces:**
- Produces: `public struct TerrariumLayer: Equatable, Sendable { public enum Kind: CaseIterable, Sendable { case system, personal, appData, review, safe }; public var kind: Kind; public var bytes: Int64; public var height: Double }`; `public enum TerrariumLayout { public static func layerHeights(for summary: ScanSummary, diskUsedBytes: Int64) -> [TerrariumLayer]; public static func growthStage(cleanupsInLast30Days: Int) -> Int }`. Mapping: personal = `doNotBulkDeleteBytes`, appData = `deleteIfAppUnusedBytes`, review = `probablyUnusedBytes`, safe = `safeToDeleteBytes`, system = `max(diskUsedBytes − sum of the others, 0)`. Height = `(0.12 + sqrt(GB) * 0.06) * 0.55` with GB = bytes / 1e9.

- [ ] **Step 1: Write the failing tests**
  - `layersAreOrderedBottomToTop`: kinds == `[.system, .personal, .appData, .review, .safe]`.
  - `heightsGrowWithBytes`: doubling a layer's bytes increases its height; heights never decrease.
  - `zeroBytesGivesMinimumHeights`: empty summary, `diskUsedBytes: 0` → every height == 0.066, no NaN.
  - `systemLayerNeverNegative`: categories larger than `diskUsedBytes` → system bytes 0.
  - `growthStageBounds`: 0→1, 1→2, 3→3, 99→3.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement (growth stage: 0 cleanups → 1, 1–2 → 2, ≥3 → 3).
- [ ] **Step 4:** Run tests. Expected: PASS.
- [ ] **Step 5:** Commit `feat: map storage categories to terrarium layers`.

### Task 14: Terrarium scene and placements

**Files:**
- Create: `Sources/CleanScopeApp/Brand/IconGeometry.swift`, `Sources/CleanScopeApp/Views/Terrarium/TerrariumScene.swift`, `Sources/CleanScopeApp/Views/Terrarium/TerrariumView.swift`
- Modify: `script/render_icons.swift` (use `IconGeometry`), `Views/DashboardView.swift` (hero right side, 360 × 240), `Views/CleanupReportView.swift` (above outcomes), `Views/MenuBarContentView.swift` (thumbnail)

**Interfaces:**
- Consumes: `TerrariumLayout`, `MotionPolicy`, `AppModel.latestStreamedCategory`, `AppModel.isScanning`, `AppModel.cleanupLog`.
- Produces: `final class TerrariumScene { init(); func apply(layers: [TerrariumLayer], growthStage: Int, animated: Bool); func setScanning(_ on: Bool, glowing: TerrariumLayer.Kind?); func compost(duration: TimeInterval) ; let scene: SCNScene }`; `struct TerrariumView: NSViewRepresentable { var layers: [TerrariumLayer]; var growthStage: Int; var mode: Mode }` with `enum Mode { case dashboard, afterCleanup }`; `AppModel.terrariumSnapshot: NSImage?` (refreshed after each scan and cleanup, 120 × 80 pt).

- [ ] **Step 1:** Move the SceneKit builders (leaf, lens, sprout, extrusion helper, palette) from `script/render_icons.swift` into `Sources/CleanScopeApp/Brand/IconGeometry.swift` (imports only SceneKit/AppKit). Give the script an `@main struct RenderIcons` and build it with `swiftc -O Sources/CleanScopeApp/Brand/IconGeometry.swift script/render_icons.swift -o .build/render_icons && .build/render_icons`; put that command in the script's header comment, replacing the old `swift script/render_icons.swift` line. Re-render and confirm the PNG checksums are unchanged.
- [ ] **Step 2:** Build the scene per spec Phase 3 (plinth, gold rim, dome with `transparency 0.12` + `fresnelExponent 1.8` + `lightingModel .physicallyBased`, five `SCNCylinder` layers radius 1.8 stacked from `layerHeights`, 170 leaves via one `SCNNode` with `SCNGeometry` instances placed by a seeded generator, sprout, parked lens). Camera (0, 2.1, 10.4) looking at (0, −0.55, 0), FOV 30°.
- [ ] **Step 3:** Behaviour: idle rotation 0.12 rad/s and pointer tilt ±0.3 rad only while `allowsAmbientMotion`; scanning → lens orbit (3 s/turn) and faint emission (0.35) on the layer matching `latestStreamedCategory`; `.afterCleanup` → `compost(duration: 1.6)` once on appear (leaves scale to 0 and sink 0.08, safe layer animates to its new height, sprout gains a stage). Pause rule: `SCNView.isPlaying = false` and `rendersContinuously = false` when `allowsAmbientMotion` is false or the view's window is occluded; Reduce Motion renders one frame. One accessibility element labelled "Storage terrarium: X safe to reclaim, Y worth a closer look, Z app data, W personal files, V macOS and apps."
- [ ] **Step 4:** Snapshot Dashboard and Last Cleanup in light/dark/`--reduce-motion`. Instruments: Dashboard idle < 10% of one core; with the window occluded (another app fullscreen over it) GPU activity in Metal System Trace drops to zero. If the dome reads flat, apply the spec's fallback (pre-rendered transparent dome PNG via `render_icons.swift`).
- [ ] **Step 5:** Commit `feat: add the storage terrarium to the dashboard and last cleanup`.

---

## Phase 4 · Motion Studies

### Task 15: Harvest basket

**Files:**
- Create: `Sources/CleanScopeCore/BasketPresentation.swift`, `Sources/CleanScopeApp/Views/HarvestBasket.swift`
- Modify: `Views/ResultsView.swift` (toolbar item replaces the header's selection sentence; keep "Clear Selection"), `Views/StorageMapView.swift` (same toolbar item)
- Test: `Tests/CleanScopeCoreTests/PresentationTests.swift`

**Interfaces:**
- Produces: `public enum BasketPresentation { public static func flights(newlySelected: [ScanResult]) -> [ScanResult] }` (returns the item for a single new selection; returns `[first]` for 2…∞ so bulk selects play one flight); `struct HarvestBasket: View` (glyph, `CountPhrase.make(n, "item")`, `ByteCount.string(ResultPresentation.totalBytes(selected))`, opens `CleanupReviewSheet`).

- [ ] **Step 1: Write the failing tests** `singleSelectionPlaysOneFlight` and `bulkSelectionPlaysOneFlight` (2,709 items in → 1 out), `deselectionPlaysNoFlight` (empty in → empty out).
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement; the chip flies from the row's or tile's frame (captured with an anchor preference) to the toolbar basket over 0.55 s using `matchedGeometryEffect` in a window-level overlay; basket scales 1→1.04→1 once on arrival. No flight when `!allowsTransitions`.
- [ ] **Step 4:** Run tests; snapshot with one and with all items selected. Expected: PASS; basket total equals the review sheet total.
- [ ] **Step 5:** Commit `feat: add the harvest basket`.

### Task 16: Hero states and rolling result

**Files:**
- Create: `Sources/CleanScopeApp/Views/DashboardHero.swift`
- Modify: `Views/DashboardView.swift`, `Views/CleanupReportView.swift`, `Sources/CleanScopeCore/Presentation.swift`
- Test: `Tests/CleanScopeCoreTests/PresentationTests.swift`

**Interfaces:**
- Produces: `public enum HeroState: Equatable, Sendable { case idle, scanning, results, cleaned }`; `public static func StoragePresentation.heroState(hasScanned: Bool, isScanning: Bool, cleanedThisSession: Bool) -> HeroState`; `struct DashboardHero: View` (headline from existing `StoragePresentation.headline`, cleaned → "Moved safely to Trash.", sprout stage idle 0 / scanning 1 / results 2 / cleaned 3, progress bar bound to `scanProgress`).

- [ ] **Step 1: Write the failing test** `heroStatePriority`: scanning beats cleaned beats results beats idle.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement `heroState`; `DashboardHero` animates between states with `PhaseAnimator` (headline blur 4 → 0 and opacity, 0.25 s; sprout `BrandMarkView(growthStage:)` with spring response 0.4, damping 0.7); Reduce Motion crossfade only. Recovered bytes in `DashboardHero` (cleaned) and `CleanupCelebrationView` use `.contentTransition(.numericText(value:))`, triggered once per `cleanupSession.id`.
- [ ] **Step 4:** Run tests; snapshot all four states.
- [ ] **Step 5:** Commit `feat: morph the dashboard hero through scan states and roll recovered space`.

### Task 17: Scan theatre

**Files:**
- Create: `Sources/CleanScopeCore/ScanTheatreModel.swift`, `Sources/CleanScopeApp/Views/ScanTheatre.swift`
- Modify: `Sources/CleanScopeApp/AppModel.swift` (publish each flushed batch as `lastBatch: [ScanResult]` and `currentScanPath: String?`), `Views/DashboardView.swift` (below hero while scanning)
- Test: `Tests/CleanScopeCoreTests/ScanTheatreModelTests.swift`

**Interfaces:**
- Produces: `public enum TheatreJar: CaseIterable, Sendable { case safe, review, appData, keep }`; `public struct ScanTheatreModel: Equatable, Sendable { public private(set) var counts: [TheatreJar: Int]; public mutating func absorb(_ batch: [ScanResult]) -> [TheatreJar] /* particles to spawn, capped at 40 */; public func fill(_ jar: TheatreJar) -> Double /* count / max count, 0 when all zero */ }`.

- [ ] **Step 1: Write the failing tests** `absorbCountsEveryResult` (counts include all, not just the 40 particles), `particlesAreCappedAtForty`, `fillIsRelativeToLargestJar`, `emptyModelFillsZero`.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement the model (`doNotBulkDelete` → keep, `deleteIfAppUnused` → appData). View: mono path line (`currentScanPath`), four jars with fill and counts; particles in one `TimelineView(.animation)` + `Canvas`, each 7 pt dot travelling 0.62 s on a quadratic arc from the path line to its jar, coloured by fill token. No particles when `!allowsAmbientMotion`.
- [ ] **Step 4:** Run tests; snapshot mid-scan with `--snapshot-scan-progress 0.4`.
- [ ] **Step 5:** Commit `feat: show the scan theatre while scanning`.

### Task 18: Menu bar sprout

**Files:**
- Create: `Sources/CleanScopeCore/MenuBarPresentation.swift`, `Sources/CleanScopeApp/Brand/SproutTemplateImage.swift`
- Modify: `Sources/CleanScopeApp/CleanScopeApp.swift` (`MenuBarExtra` label), `Views/MenuBarContentView.swift` (header: `terrariumSnapshot` + "Review Quick Wins…")
- Test: `Tests/CleanScopeCoreTests/MenuBarPresentationTests.swift`

**Interfaces:**
- Produces: `public enum MenuBarPresentation { public static func sproutStage(daysSinceCleanup: Int, safeBytes: Int64) -> Int; public static func sizeLabel(daysSinceCleanup: Int, safeBytes: Int64) -> String?; public static func daysSinceCleanup(log: [CleanupLogEntry], firstLaunch: Date, now: Date) -> Int }`; `enum SproutTemplateImage { static func image(stage: Int) -> NSImage }` (18 × 18 pt, `isTemplate = true`, drawn with `NSBezierPath`: lens ring + handle; stage 1 adds stem and one leaf, stage 2 both leaves).

- [ ] **Step 1: Write the failing tests**
  - `stageZeroWhenRecentOrSmall`: (4 days, 5 GB) → 0; (20 days, 249_999_999) → 0.
  - `stageTwoNeedsTimeAndSize`: (12 days, 1_000_000_000) → 2; (11 days, 5 GB) → 1; (30 days, 999_999_999) → 1.
  - `sizeLabelThresholds`: (14 days, 500_000_000) → "500 MB"; (13 days, 5 GB) → nil; (20 days, 499_999_999) → nil.
  - `noCleanupLogFallsBackToFirstLaunch`: empty log, first launch 9 days ago → 9.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement (stage 0 if days < 5 or bytes < 250 MB; stage 2 if days ≥ 12 and bytes ≥ 1 GB; else 1; label `ByteCount.string` when days ≥ 14 and bytes ≥ 500 MB). Replace the `leaf.circle` label with the template image and optional label; keep its accessibility label, extended with "1.2 GB of caches ready" when shown.
- [ ] **Step 4:** Run tests; launch the app and check the menu bar in light and dark menu bars.
- [ ] **Step 5:** Commit `feat: grow the menu bar sprout with cache age`.

### Task 19: Disk weather

**Files:**
- Create: `Sources/CleanScopeCore/DiskWeather.swift`, `Sources/CleanScopeApp/Views/DiskWeatherBackground.swift`
- Modify: `Views/DashboardView.swift` (background + hero sub-line), `Sources/CleanScopeCore/Presentation.swift` (`weatherLine`)
- Test: `Tests/CleanScopeCoreTests/DiskWeatherTests.swift`

**Interfaces:**
- Consumes: `BrandPalette.contrast`, `BrandPalette.textPrimary`, `BrandPalette.destructive` (Task 10).
- Produces: `public enum DiskWeather { public static func stops(usedFraction: Double, dark: Bool) -> (top: UInt32, bottom: UInt32, sun: UInt32); public static func usedFraction(totalBytes: Int64, availableBytes: Int64) -> Double }` with stops interpolated from 0.40 to 0.98 (light top `#E3F1E8→#F8DDB2`, bottom `#F7F3EA→#F4CB93`; dark top `#1F2E27→#3A2C18`, bottom `#1A1816→#2A2014`); `public static func StoragePresentation.weatherLine(usedFraction: Double, availableBytes: Int64, safeBytes: Int64) -> String`; `struct DiskWeatherBackground: View`.

- [ ] **Step 1: Write the failing tests**
  - `weatherCopyThresholds`: 0.69 → "Plenty of room.", 0.70 → "Getting cozy.", 0.88 with 4 GB available and 1.85 GB safe → "Room is tight. 4 GB available. Quick wins can free 1.85 GB without touching your files."
  - `unknownDiskTotalIsPlentyOfRoom`: `usedFraction(totalBytes: 0, availableBytes: 0) == 0` and its line is "Plenty of room."
  - `stopsClampOutsideRange`: 0.1 equals 0.40 stops; 1.2 equals 0.98 stops.
  - `weatherTextMeetsContrastAtBothEnds`: `BrandPalette.contrast(textPrimary, stop)` ≥ 4.5 for top and bottom at 0.40 and 0.98, light and dark.
  - `weatherNeverUsesDestructive`: no stop equals `BrandPalette.destructive` light or dark.
- [ ] **Step 2:** Run tests. Expected: FAIL.
- [ ] **Step 3:** Implement; the view uses `MeshGradient` (3×3, inner points drift ±0.03 over 20 s only while `allowsAmbientMotion`) inside `if #available(macOS 15, *)`, else a two-stop `LinearGradient`; the sun is a soft radial circle top-right in `sun`.
- [ ] **Step 4:** Run tests; snapshot Dashboard light/dark.
- [ ] **Step 5:** Commit `feat: add disk weather to the dashboard`.

### Task 20: Documents and final verification

**Files:**
- Modify: `DESIGN.md` (Motion, Iconography, Storage Map, Dashboard, fill tokens), `PRODUCT.md` (living-interface principle; drop "gauges" anti-reference), `VERIFY.md` (new states, performance checks, today's log)

- [ ] **Step 1:** Update the three documents from what shipped (spec "Documents to Update").
- [ ] **Step 2:** Full verification: `./script/swiftpm.sh test` (all pass), `./script/swiftpm.sh build` (no warnings), `./script/build_and_run.sh --verify`, snapshot run in light, dark, `--snapshot-empty` and `--reduce-motion`; confirm `CleanupReviewSheet` snapshots are pixel-identical with and without `--reduce-motion` (`cmp` the two PNGs).
- [ ] **Step 3:** VoiceOver pass on Storage Map (lens navigation), basket, terrarium label; keyboard-only pass on Storage Map. Record results in `VERIFY.md`.
- [ ] **Step 4:** Commit `docs: document the living interface and record verification`.
