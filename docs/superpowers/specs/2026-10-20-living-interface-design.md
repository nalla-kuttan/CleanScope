# Living Interface Design

## Goal

Give CleanScope a distinctive, animated interface that stands apart from CleanMyMac. CleanMyMac decorates each module with a static illustration; CleanScope makes the user's actual storage the thing that moves. Every animated value comes from real scan data.

The direction was chosen from the concept board at https://claude.ai/artifact/DCp379qA5JfsUrtvRPhdhg (private to the owner):

- **Core:** B · Field Lens. The Storage Map is a treemap inspected with a magnifying Sprout Lens.
- **Moments:** A · Terrarium. A 3D terrarium appears only on the Dashboard hero and on Last Cleanup.
- **Icons:** a 12-icon 3D family in a soft-clay style.
- **Motion:** harvest basket, rolling result, scan theatre, hero states, menu bar sprout, disk weather.

## Non-Goals

- No change to what the app scans, classifies or deletes. This is presentation only, apart from two small data additions in Phase 0: a cleanup log (0.5) and scan progress reporting (0.6).
- No sound.
- No 3D in the sidebar, tables, review sheets or confirmation dialogs.
- No confetti, points, streaks, levels or countdowns.

## Fixed Rules

These apply to every phase and are checked in review.

1. **Real numbers drive motion.** Tile areas, soil-layer heights, particle counts and ring angles come from `AppModel` data. Nothing animates toward an invented value. Sample data appears only in the debug snapshot mode.
2. **Review stays still.** `CleanupReviewSheet`, item detail and any confirmation show no ambient motion. Celebration happens only after a confirmed cleanup.
3. **Reduce Motion is a full design.** Each animated surface defines its Reduce Motion version: a still frame or an immediate state change with the same information.
4. **No fear.** No red alarms or "critical" copy. Disk weather never uses the destructive color.
5. **Paused when not visible.** 3D scenes and particle systems stop rendering when off-screen, when the window is hidden or minimized, and in Low Power Mode.
6. **Accessible equivalents.** The Storage Map keeps its list view, and every 3D or animated element has an accessibility label stating the same facts in words.

## Phasing

| Phase | Work | Depends on |
|---|---|---|
| 0 | Merge audit fixes, raise minimum to macOS 14, add `MotionPolicy`, resource bundle, cleanup log and scan progress | — |
| 1 | 3D icon family | 0 |
| 2 | Field Lens Storage Map | 0 |
| 3 | Terrarium moments | 0, 1 (shares model code) |
| 4 | Motion studies | 0 |

Phases 1, 2 and 4 are independent of each other once Phase 0 lands.

---

## Phase 0. Foundation

### 0.1 Merge `fix/audit-findings`

`feature/cleanmymac-gap-features` branched from `6ab191e`, before the audit work. Merge `fix/audit-findings` (`9365233`, `d7641f6`, `461d6fa`, `86554c0`) into it.

Conflict policy:

- **Keep from the audit branch:** `NavigationSplitView` + sidebar `List`, the native results `Table`, `BrandTheme` role tokens, `CleanupReviewSheet` scoping (P0 fix), `ResultPresentation.outermost` totals, exclusion handling, `CountPhrase`, `StoragePresentation` copy, debug snapshot mode.
- **Keep from gap-features:** every new destination (Storage Map, Leftovers, Maintenance, Login Items, Background Items, Memory, Protection, Privacy), the menu bar extra, monitors, alerts and rule updates.
- **Move gap-features destinations into the audit structure:** `AppModel.Destination` gains the new cases with `title`, `systemImage`, `section` and `includes(_:)`. Sidebar sections become Overview (Dashboard, Storage Map, Ready to Delete, Safe Cleanup), Browse (Large Files, Hidden Folders, Developer Files, App Support, Downloads, Trash, Leftovers), Performance (Maintenance, Login Items, Background Items, Memory), Protection (Protection, Privacy) and Activity (Last Cleanup). Settings stays out of the sidebar.
- **Replace old token names** in gap-features views (`cream`, `bark`, `sage`, `clay`, `warmGray`, `scopeForest` …) with the role tokens (`surface`, `textPrimary`, `accent`, `surfaceRaised`, `textSecondary` …).

Done when: both branches' test suites pass on the merged result, the build has no warnings, and the debug snapshot pass shows every destination.

### 0.2 Raise the minimum to macOS 14

`Package.swift` sets `.macOS(.v14)`. This unlocks `contentTransition(.numericText())`, `PhaseAnimator`, `keyframeAnimator` and `.layerEffect` shaders. `MeshGradient` (macOS 15) stays behind an availability check.

Update `LSMinimumSystemVersion` in `script/build_and_run.sh` to `14.0`.

### 0.3 `MotionPolicy`

A single `@MainActor` observable object owned by `AppModel`:

```swift
final class MotionPolicy: ObservableObject {
  @Published private(set) var allowsAmbientMotion: Bool   // false when Reduce Motion, Low Power, or window not visible
  @Published private(set) var allowsTransitions: Bool    // false only when Reduce Motion
  func animation(_ base: Animation = .easeOut(duration: 0.2)) -> Animation?
}
```

Inputs:

- `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
- `ProcessInfo.processInfo.isLowPowerModeEnabled`, observed via `NSProcessInfoPowerStateDidChange`.
- Main window occlusion (`NSWindow.occlusionState`) and app activation.

`BrandTheme.animation(_:)` delegates to `MotionPolicy`. Views must not check Reduce Motion themselves except through this object.

### 0.4 App resource bundle

Add `resources: [.process("Resources")]` to the `CleanScopeApp` target. `script/build_and_run.sh` copies `CleanScope_CleanScopeApp.bundle` into `Contents/Resources`. A `Bundle.cleanScope` accessor checks `Bundle.main.resourceURL` first and falls back to `Bundle.module`, so assets load both from the `.app` and from `swift run`.

### 0.5 Last cleanup date

`CleanupLogStore` persists the `completedAt` and `recoveredBytes` of each confirmed cleanup (most recent 50) as JSON in Application Support. `AppModel.cleanup(_:)` appends to it. Phase 4's menu bar sprout and Last Cleanup read it.

Tests: round-trip, cap at 50, newest first.

### 0.6 Scan progress

`ScannerService.scan` gains an `onProgress: @Sendable (_ completedRoots: Int, _ totalRoots: Int) -> Void` callback, called after each scan root finishes. `AppModel` publishes `scanProgress: Double` (0…1) and `latestStreamedCategory: SafetyCategory?` (the category of the last result in the most recent batch). The Storage Map sweep, terrarium glow and hero progress bar read these.

Tests: progress reaches 1.0 exactly once per scan; cancelling stops progress callbacks.

---

## Phase 1. 3D Icon Family

### Icons

| Key | Module | Model | Hover action |
|---|---|---|---|
| `scan` | Smart Scan / Dashboard | Sprout Lens: torus lens, glass disc, handle, two-leaf sprout | Sprout sways |
| `cleanup` | Safe Cleanup, Ready to Delete | Bin with open lid and a sprout growing out | Lid lifts, sprout grows |
| `map` | Storage Map | Slab with five extruded blocks | Block heights breathe |
| `large` | Large Files | Three stacked rounded crates | Top crate lifts |
| `dev` | Developer Files | Extruded `</>` | Brackets spread |
| `downloads` | Downloads | Arrow over a tray | Arrow drops |
| `leftovers` | Leftovers | Open carton with two cubes | Cubes float |
| `maintenance` | Maintenance | Two meshing gears | Gears turn |
| `memory` | Memory | Chip with pins and a core | Core glows |
| `login` | Login Items, Background Items | Key with a leaf tag | Key turns |
| `protection` | Protection | Shield carrying a sprout | Sprout pulses |
| `privacy` | Privacy | Padlock | Shackle lifts |

Palette: forest `#2F6B57`, sage `#86AE8C`, leaf `#6CC48A`, mint `#DFF2E8`, cream `#F1E9DC`, bark `#6B5140`, amber `#E6B35A`, terracotta `#D9806A`, blue `#6E93BD`, gold `#DDB45E`, card `#C99F72`, chip `#2F4A3E`. Material: physically based clay (roughness 0.42, clearcoat 0.55, sheen 0.3). Lighting: one warm key light from the upper left plus a studio environment map, identical for every icon.

### Rendering pipeline

`script/render_icons.swift` (run with `swift script/render_icons.swift`) builds each model in SceneKit, mirroring the board's three.js geometry:

- Writes `Sources/CleanScopeApp/Resources/Icons/<key>.png` at 64, 128 and 192 px (1×, 2×, 3× of 64 pt) with transparent background and a soft contact shadow.
- Writes an 18-frame hover loop per icon as `<key>-hover-<n>.png` at 128 px.
- Is deterministic: same input produces byte-identical output, so diffs show real changes.

The rendered PNGs are committed. The script is not run at build time.

### `ModuleIcon` view

```swift
struct ModuleIcon: View {
  var key: ModuleIconKey
  var size: CGFloat = 64
}
```

- Shows the still PNG. On hover (when `allowsTransitions`) it plays the hover loop at 30 fps once, then rests, and tilts up to 10° toward the pointer with `rotation3DEffect`.
- `accessibilityHidden(true)`. The adjacent title carries the meaning.

### Placement

- Section header of each module destination (64 pt, left of the title).
- Empty states (replaces the SF Symbol, 64 pt).
- Dashboard "Modules" row: a compact row of module links with their counts (40 pt icons).
- Menu bar popover header (32 pt, `scan`).

The sidebar, tables and dialogs keep SF Symbols.

### Tests

Snapshot pass renders each placement in light, dark and Reduce Motion. A unit test asserts every `ModuleIconKey` has all three still sizes and 18 hover frames in the bundle.

---

## Phase 2. Field Lens Storage Map

Extends the existing `StorageMapView` (treemap, drill-in, breadcrumb, list toggle).

### Layout (Core)

Move tile layout into `CleanScopeCore/Treemap.swift`:

```swift
public struct TreemapTile: Equatable, Sendable { public var id: String; public var rect: CGRect }
public enum Treemap {
  public static func squarify(_ items: [(id: String, bytes: Int64)], in rect: CGRect, gap: CGFloat) -> [TreemapTile]
}
```

Tests: areas proportional to bytes within 0.5%; no overlaps; every tile inside `rect`; worst aspect ratio for a known fixture is at most 3.0; zero-byte items dropped; output order is stable for equal sizes.

### Tile color

Each tile takes the safety category of its node's matching result (`resultId`). Folders without a result use the dominant category by bytes among descendants, falling back to `textSecondary` at 30% for unclassified space. Free space is shown as one mint tile when viewing the volume root. Colors come from new fill tokens in `BrandTheme` (`safeFill`, `reviewFill`, `appFill`, `keepFill`, `systemFill`, `freeFill`) with light and dark values from the concept board.

### The lens

- A circular magnifier (radius 46–78 pt by window width, zoom 2.6×) follows the pointer over the map.
- Rendering: the map is drawn once into a `Canvas`. The lens is the same canvas content, masked to a circle and scaled around the lens center. Refraction and the rim highlight come from a `.layerEffect` Metal shader (`Lens.metal`), applied only inside the lens.
- A label bubble above the lens shows name, size and safety label of the tile under its center.
- Keyboard: the map is focusable; arrow keys move the lens tile to tile in reading order, Space toggles selection, Return drills in, ⌘[ goes up. VoiceOver reads each focused tile as "Name, size, safety label, selected/not selected".
- When the pointer leaves, the lens rests on the largest safe tile. It does not roam.

### Scan sweep

While a scan runs, tiles appear left to right as a soft light band sweeps across, in step with real progress: the band position is `AppModel.scanProgress`. Tiles not yet reached draw as outlines. Reduce Motion: tiles appear without the band.

### Select, lift, collapse

- Clicking a safe tile toggles its selection (same `AppModel.selection` as the tables). Selected tiles lift 4 pt with a soft shadow and a check badge. Non-safe tiles show the reason they can't be selected in the label bubble.
- "Review Cleanup…" in the toolbar opens `CleanupReviewSheet` with exactly the selected items.
- After a confirmed cleanup, trashed tiles shrink to nothing over 0.7 s while the free-space tile grows into the space, then the layout settles. Reduce Motion: the new layout appears immediately.

### Performance

Target 60 fps while moving the lens over a map of 3,000 tiles on an M1. The base map re-renders only when data, size, selection or theme change; lens movement redraws only the lens layer.

---

## Phase 3. Terrarium Moments

### Where

- Dashboard hero, right side, about 360 × 240 pt, beside the headline and Safe-to-reclaim figure.
- Last Cleanup, above the outcome list, showing the post-cleanup state.

Nowhere else.

### Scene (`TerrariumScene`)

A SceneKit scene in an `NSViewRepresentable` wrapping `SCNView` (Metal, 4× multisampling, transparent background), built from the board's geometry:

- Wooden plinth, gold rim, glass dome (physically based, transmission-like via `transparency` + `fresnelExponent`).
- Five soil layers bottom to top: macOS & apps, personal (Do not bulk delete), app data (App/tool dependent), review recommended, safe caches.
- Leaf litter: 170 instanced leaves on the top layer.
- Sprout on top with three growth stages.
- The Sprout Lens parked beside the dome.

### Data binding (Core)

```swift
public enum TerrariumLayout {
  public static func layerHeights(for summary: ScanSummary, diskUsedBytes: Int64) -> [TerrariumLayer]
  public static func growthStage(cleanupsInLast30Days: Int) -> Int   // 1...3
}
```

Heights use `(0.12 + sqrt(GB) × 0.06) × 0.55` so small layers stay visible while order and relative size stay true. Tests cover ordering, monotonicity and the zero-bytes case.

### Behavior

- Idle: slow 0.12 rad/s rotation and pointer-following tilt (±0.3 rad). Stops entirely when `allowsAmbientMotion` is false.
- Scanning: the lens orbits the dome once per three seconds, and the layer matching `AppModel.latestStreamedCategory` glows faintly.
- After confirmed cleanup (Last Cleanup screen): litter shrinks and sinks over 1.6 s, the safe layer thins, and the sprout gains a stage.
- Reduce Motion: a single rendered frame of the current state, no rotation.
- Accessibility: one element labelled, for example, "Storage terrarium: 5.94 GB safe to reclaim, 6.3 GB worth a closer look, 22.9 GB app data, 75 GB personal files, 48 GB macOS and apps."

### Cost control

The `SCNView` pauses (`isPlaying = false`, `rendersContinuously = false`) when off-screen, when the window is occluded, or when `allowsAmbientMotion` is false. A static snapshot (`SCNView.snapshot()`) is cached for the menu bar popover thumbnail.

---

## Phase 4. Motion Studies

### 4.1 Harvest basket

- A toolbar item on result destinations and the Storage Map: basket glyph, item count and deduplicated total (`ResultPresentation.totalBytes`). Clicking opens the review sheet.
- When an item is selected, a chip with its name flies from the row or tile to the basket (`matchedGeometryEffect` into an overlay, 0.55 s), and the basket pulses once.
- Replaces the "N selected · X GB" header line. The header keeps "Clear Selection".
- Reduce Motion: no flight; the count updates in place.

### 4.2 Rolling result

`contentTransition(.numericText(value:))` on recovered bytes in Last Cleanup and the Dashboard headline after a confirmed cleanup, once per cleanup. Never on estimates or during scanning.

### 4.3 Scan theatre

- Shown on the Dashboard while scanning, below the hero: a monospaced line with the path currently being scanned, and four jars (Safe, Review, App data, Keep) whose fill and counts rise.
- Particles: each streamed batch spawns one dot per result (capped at 40 per batch), colored by category, flying from the path line to its jar along a short arc. Implemented with `TimelineView(.animation)` + `Canvas`, no per-dot views.
- Counts are the real streamed counts. Jar fill is `count / max(count across jars)`.
- Reduce Motion or `allowsAmbientMotion` false: no particles; counts and fills update directly.

### 4.4 Hero states

The Dashboard hero is one view with four states driven by `AppModel`:

| State | When | Headline | Sprout |
|---|---|---|---|
| Idle | No scan yet | "Let's see where your space went." | Lens only |
| Scanning | `isScanning` | "Looking for room to grow…" | Stem |
| Results | Scan finished | "You found X of breathing room." | Stem + leaf |
| Cleaned | Confirmed cleanup in this session | "Moved safely to Trash." | Stem + two leaves |

Transitions use `PhaseAnimator`: headline blurs out and in (0.25 s), the progress bar eases, the sprout gains its stage with a small overshoot. Reduce Motion: crossfade only.

### 4.5 Menu bar sprout

- The `MenuBarExtra` label uses three template images: `sprout-0` (lens only), `sprout-1` (stem and one leaf), `sprout-2` (two leaves).
- Stage comes from `MenuBarPresentation.sproutStage(daysSinceCleanup:safeBytes:)` in Core: stage 0 if fewer than 5 days or under 250 MB; stage 2 if at least 12 days and at least 1 GB; otherwise stage 1. "Days since cleanup" comes from `CleanupLogStore` (falls back to days since first launch). "Safe bytes" is the last scan's `safeToDeleteBytes`.
- At 14 or more days and at least 500 MB, the label also shows the size ("1.2 GB").
- Popover header shows the terrarium snapshot thumbnail and "Review Quick Wins…".
- Tests: stage boundaries and label threshold.

### 4.6 Disk weather

- The Dashboard background is a gradient that moves from "fresh morning" to "warm afternoon" as disk use rises from 40% to 98%, using the board's color stops (light and dark sets). Below 40% it stays at the morning stops.
- macOS 15: `MeshGradient` 3×3 with a slow drift of the inner points (stopped when `allowsAmbientMotion` is false). macOS 14: two-stop `LinearGradient` with the same colors.
- The hero sub-line follows `StoragePresentation.weatherLine(usedFraction:availableBytes:safeBytes:)`: "Plenty of room." below 70%, "Getting cozy." below 88%, otherwise "Room is tight. X available. Quick wins can free Y without touching your files."
- Text on the gradient is checked for 4.5:1 at both ends of each set.
- Tests: copy thresholds and gradient interpolation endpoints.

---

## Verification

- **Unit tests** for every Core addition: `Treemap.squarify`, `TerrariumLayout`, `MenuBarPresentation.sproutStage`, `StoragePresentation.weatherLine`, `CleanupLogStore`, scan progress, icon bundle completeness.
- **Snapshot pass** (`--snapshot-dir`) extended with states: Dashboard idle / scanning / results / cleaned, Storage Map with lens and with selection, Last Cleanup after cleanup, each in light, dark and with `--reduce-motion` (a new debug flag that forces `MotionPolicy` off).
- **Performance:** Instruments Time Profiler run on the Storage Map with a 3,000-tile fixture, lens moving continuously for 10 s, at most 1% dropped frames. Terrarium on Dashboard idle: under 10% of one CPU core and zero GPU work when the window is occluded.
- **Accessibility:** VoiceOver pass over the Storage Map lens navigation, the basket and the terrarium label. Keyboard-only pass over the Storage Map.
- **Safety:** the existing P0 test (review scope) and nested-folder tests still pass. Snapshots of `CleanupReviewSheet` taken with `MotionPolicy` on and off must be pixel-identical.

## Documents to Update

- `DESIGN.md`: Motion section (allowed motions, durations, `MotionPolicy`), Iconography (3D module icons and where they may appear), Storage Map and Dashboard component patterns, fill tokens.
- `PRODUCT.md`: Brand Personality gains the living-interface principle; anti-references keep confetti/casino/fear and drop "gauges" (already superseded by the gap-features spec).
- `VERIFY.md`: new snapshot states and performance checks.

## Risks

- **SceneKit glass looks flat compared to the WebGL board.** Mitigation: tune with an HDR environment map committed to resources; if it still reads poorly, render the dome as a pre-rendered transparent PNG over the live soil.
- **Merge conflicts in Phase 0 are large** (about 26 overlapping UI files). Mitigation: resolve file by file under the conflict policy above, and run both branches' tests before any Phase 1 work.
- **The lens shader needs macOS 14.** Accepted: the minimum is raised in Phase 0.
