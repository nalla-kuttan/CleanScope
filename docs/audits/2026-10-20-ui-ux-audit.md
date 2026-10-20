# CleanScope UI/UX Audit — 2026-10-20

Branch `feature/bulk-cache-selection` @ `6ab191e`. Scope: every SwiftUI view in `Sources/CleanScopeApp`, judged against `PRODUCT.md`, `DESIGN.md`, `BRANDKIT.md`, the macOS HIG and WCAG 2.1 AA.

Method: I read all of the UI source and computed WCAG contrast ratios for every palette pair used. The app was built and launched (`script/build_and_run.sh --verify` passed). I could not take window screenshots because the shell lacks Screen Recording permission, so findings come from code and math, not pixels. Every finding below was checked against the source.

Lenses applied: Impeccable native audit (scored), accessibility review (WCAG 2.1 AA), design critique, UX copy review, design-system audit. The Vercel web-interface-guidelines skill covers HTML/React only. Only the parts that carry over to a native app (keyboard, focus, destructive-action rules) were used.

---

## Audit Health Score

| # | Dimension | Score | Key finding |
|---|---|---|---|
| 1 | Accessibility | 1 | Secondary text, the primary CTA and the "Review recommended" label fail AA contrast; sidebar and results can't be used from the keyboard |
| 2 | Performance | 2 | The results list re-filters and re-sorts thousands of rows several times per render, and every streamed result re-renders the list |
| 3 | Appearance & Theming | 2 | Tokens are adaptive, but they're in the wrong colorspace, the names no longer match the colors, the docs disagree with the code, and the gauge track is invisible |
| 4 | Platform Conformance | 1 | Custom sidebar, custom card list and custom pills replace NavigationSplitView, Table, `.searchable` and native buttons |
| 5 | Adaptivity (window sizing) | 2 | Large minimum window, fixed non-collapsible sidebar, nested scroll regions, no plural handling |
| **Total** | | **8/20** | **Poor**: the fixes are mostly mechanical, but there are a lot of them |

## Platform Conformance Verdict: **Fail**

CleanScope reads as a web dashboard rendered in a Mac window. The foundation is native (SwiftUI, a Settings scene, menu commands, a grouped `Form`), but the Greenhouse restyle replaced the native containers that `PRODUCT.md` principle 5 ("Native first") and `DESIGN.md` ("Native macOS source list", "Native table behavior") require:

- **Sidebar.** It's a `VStack` of `.plain` capsule buttons (`SidebarView.swift:28-42`), not `List(selection:)` in a `NavigationSplitView`. There's no arrow-key navigation, no selected state for VoiceOver, and no collapse or resize. Settings appears both as a sidebar destination and as the ⌘, Settings scene.
- **Results.** They're a `LazyVStack` of hover-scaling cards (`ResultsView.swift:99-108`), not `Table`. You can't sort by clicking column headers, there's no ascending/descending, no ↑/↓ row movement, no Space to toggle, no Return to open, and no ⌘-click multi-select. Only the item's name text opens the details.
- **Search and sort.** Search is a hand-built capsule `TextField` instead of `.searchable`, so there's no ⌘F. Sort is four custom capsule buttons instead of `Table` sort descriptors or a `Picker`.
- **Buttons.** The scan button (`SidebarView.swift:48-72`) and the detail actions (`ItemDetailView.swift:194-207`) are `.plain` buttons painted as capsules. They have no focus ring, no pressed state and no default-button semantics.
- **No toolbar.** Scan, search and Review Cleanup belong in the window toolbar.
- **Glass and gauge.** `.ultraThinMaterial` on the sidebar and detail sheet, plus a radial gauge, are both listed as anti-references in `PRODUCT.md` ("Decorative glass effects", "alarms, gauges").

---

## Executive Summary

- **Score:** 8/20 (Poor)
- **Issues:** 1 P0 · 12 P1 · 13 P2 · 4 P3
- **Top issues:**
  1. **P0:** "Clean All Quick Wins" can move far more items to Trash than its review sheet shows.
  2. **P1:** The dashboard calls risky bytes "Ready to reclaim", and its gauge is drawn against a made-up 500 GB disk.
  3. **P1:** WCAG AA contrast failures across secondary text, the primary CTA and safety labels.
  4. **P1:** Native containers were replaced (sidebar, table, search), which breaks keyboard and VoiceOver use.
  5. **P1:** Drift: the shipped Greenhouse palette contradicts DESIGN.md, BRANDKIT.md and VERIFY.md.
- **Next step:** fix the P0 deletion-scope bug before anything else. Then make one direction decision (keep Greenhouse or return to Space Garden) before any visual work, because it decides what the docs and tokens should become.

---

## Detailed Findings

### P0: Blocking

**[P0] "Clean All Quick Wins" deletes the whole global selection, not just the items the sheet shows**
- **Location:** `DashboardView.swift:122-128` → `AppModel.swift:152-156`
- **Category:** Safety / harden
- **Impact:** The review sheet is built from `quickWins` (at most 6 items), but confirming runs `setSelection(true, for: quickWins)` and then `cleanupSelected()`. That moves *every* selected item to Trash. Selection is global and persists across sidebar destinations. If someone selected the 2,709 cache items in Ready to Delete, then clicked "Clean All Quick Wins" on the Dashboard, the sheet would say 6 items and the app would trash 2,715. This breaks the product's core promise ("trusting that… data will not be bulk deleted") and BRANDKIT's rule that destructive actions show the selected totals.
- **Recommendation:** Make the confirmed action operate on exactly the list the sheet displayed. Change `cleanupSelected` to `cleanup(_ items: [ScanResult])`, have `CleanupReviewSheet` pass its own `items` back, and add a test that pre-existing selection outside the sheet survives.
- **Suggested command:** `/impeccable harden`

### P1: Major

**[P1] "Ready to reclaim" counts items that need review**
- **Location:** `DashboardView.swift:10-12`, `Models.swift:176`, `GrowthSummaryView.swift:65`
- **Category:** Safety copy / honesty
- **Impact:** `totalCleanableBytes` adds up Safe + Review recommended + App/tool dependent bytes. The dashboard's biggest number, labelled "Ready to reclaim … reclaimable", therefore includes items the app itself says to verify first. That contradicts "Safety stays literal" and BRANDKIT ("never imply that removal is automatic or risk-free").
- **Recommendation:** Lead with `safeToDeleteBytes` as "Safe to reclaim". Show the review bytes as a separate, quieter figure ("+ 3.1 GB worth a closer look").
- **Suggested command:** `/impeccable clarify`

**[P1] The gauge is drawn against a made-up 500 GB disk, and its track is invisible**
- **Location:** `GrowthSummaryView.swift:10-11, 24-26, 93-96`
- **Category:** Data integrity / theming
- **Impact:** `totalDiskBytes` is hard-coded to 500 GB, even though `ScanSession.diskTotalBytes` holds the real value, so the arc's fill fraction is wrong on every Mac. The track is stroked in `clay` on a card filled with `clay` (1.0:1), so it can't be seen, and the arc reads as a floating fragment. A gauge is also an explicit anti-reference in PRODUCT.md.
- **Recommendation:** Remove the gauge. If a proportion is wanted, use a thin horizontal bar of reclaimable vs. used space based on `session.diskTotalBytes`, or bring back the specified "sprout grows through three stages" treatment (`StoragePresentation.growthStage` already exists and is unused).
- **Suggested command:** `/impeccable distill`

**[P1] The dashboard shows "Available 0 bytes" before any scan**
- **Location:** `DashboardView.swift:48`
- **Category:** Data integrity
- **Impact:** `session?.diskAvailableBytes ?? 0` renders a false reading on first launch. A first-time user sees a full disk.
- **Recommendation:** Read volume capacity directly (`URLResourceKey.volumeAvailableCapacityForImportantUsageKey`), or show "—" with "Scan to measure".
- **Suggested command:** `/impeccable harden`

**[P1] Return confirms "Move to Trash"**
- **Location:** `CleanupReviewSheet.swift:81`
- **Category:** Conformance / safety
- **Impact:** The destructive button is the sheet's `.defaultAction`, so pressing Return while reading the sheet trashes the selection. The HIG says a destructive button should not be the default.
- **Recommendation:** Make Cancel the default/escape button and require a click or ⌘⌫ to confirm. Put the count in the label: "Move 6 Items to Trash".
- **Suggested command:** `/impeccable harden`

**[P1] One-click Move to Trash skips the review step**
- **Location:** `ResultsView.swift:298` (row ⋯ menu), `ItemDetailView.swift:109-111`
- **Category:** Safety
- **Impact:** Both paths call `model.cleanup(result)` immediately, with no confirmation and no undo. Bulk cleanup goes through a review sheet, but single items don't. This is inconsistent with BRANDKIT's "Destructive actions always name Trash, show selected totals".
- **Recommendation:** Send single-item trashing through the same review sheet, or add an Undo (Trash supports put-back via `NSWorkspace.recycle` URLs and the original path).
- **Suggested command:** `/impeccable harden`

**[P1] WCAG AA contrast failures (computed)**
- **Location:** `BrandTheme.swift:9-16`; used everywhere
- **Category:** Accessibility (1.4.3 / 1.4.11)
- **Impact:** Text across the app fails the 4.5:1 minimum (normal text needs 4.5:1).

| Element | Light | Dark | Where |
|---|---|---|---|
| `warmGray` secondary text on `cream` / `clay` | **3.40 / 3.04** | **3.88 / 3.47** | All subtitles, paths (10 pt!), dates, sidebar labels, sidebar footer |
| White on `sage`, primary CTA and active sidebar row | **3.63** | **2.15** | Start Scan, Review Cleanup, Rescan, sort pills |
| White on `terracotta`, Cancel scan | **3.94** | **2.66** | Sidebar footer while scanning |
| `amber` "Review recommended" label on `clay` | **2.24** | 7.93 | Every review row's safety label |
| `terracotta` "App/tool dependent" on `clay` | **3.30** | 5.95 | Safety label |
| `sage` headings/status on `cream` | **3.39** | 8.23 | "Ready to reclaim", recommended action |
| `finderBlue` permission text on 10% tint | **3.50** | 5.82 | Permission banner |
| White icon on `amber` detail tile | **≈2.6** | — | Item detail header |
| `clay` card vs `cream` window (non-text) | 1.12 | 1.12 | Card edges depend on the hairline alone |

  Light mode is the main problem; most dark-mode text tokens pass. The safety label for the category that most needs reading ("Review recommended") is the worst offender.
- **Recommendation:** Add text-grade variants (for example `sageText`, `amberText`, `secondaryText` ≥ 4.5:1) separate from the fill tokens. Use `Color.secondary` (system) for secondary copy. In dark mode, use dark text on the light-sage CTA. Add an increased-contrast branch to `adaptive()` (`.accessibilityHighContrastAqua` is never matched).
- **Suggested command:** `/impeccable colorize`

**[P1] Reduce Motion is only partly honored, and durations break the 150–220 ms spec**
- **Location:** `GrowthSummaryView.swift:52, 57-61`; `SidebarView.swift:117-118`; `ResultsView.swift:324-326`
- **Category:** Accessibility
- **Impact:** `onChange(of: cleanableBytes)` animates for 0.6 s whether or not Reduce Motion is on, and it fires for every streamed result. The first appearance animates for 1.0 s. The hover `scaleEffect`s on sidebar rows (1.02) and result cards (1.003) aren't gated by Reduce Motion, and the 1.003 scale softens text rendering on every hovered row.
- **Recommendation:** Gate every `withAnimation` and `scaleEffect` on `reduceMotion`, clamp durations to `BrandTheme.motionDuration`, and replace hover scaling with a background or stroke change only.
- **Suggested command:** `/impeccable animate`

**[P1] The custom sidebar breaks keyboard and VoiceOver navigation**
- **Location:** `SidebarView.swift`, `ContentView.swift:8-19`
- **Category:** Conformance / accessibility (2.1.1, 4.1.2)
- **Impact:** You can't reach sections with ↑/↓, VoiceOver never announces which destination is selected (no `.isSelected` trait), and the sidebar can't be collapsed (⌃⌘S) or resized. A hover `nil` race (lines 38) can also clear the hover state when moving quickly between rows.
- **Recommendation:** Use `NavigationSplitView { List(selection: $model.destination) { … }.listStyle(.sidebar) }`, group the destinations into sections ("Overview", "Categories", "History"), drop the Settings row, and keep the scan button in `.safeAreaInset(edge: .bottom)` or the toolbar.
- **Suggested command:** `/impeccable adapt`

**[P1] The card list replaces the native Table**
- **Location:** `ResultsView.swift:75-108, 148-166, 233-339`
- **Category:** Conformance / accessibility
- **Impact:** The power users this app targets ("folder-level visibility") lose column sorting, sort direction, keyboard row movement, Space to toggle, Return to open, ⌘A, and Quick Look. DESIGN.md requires "Native table behavior".
- **Recommendation:** Use `Table(filtered, selection:, sortOrder:)` with Name, Size, Safety and Modified columns, plus a leading checkbox column for *cleanup* selection that stays separate from row focus. `ResultsTable` already declares an unused `sortOrder` binding. Use `.searchable` for search and `.contextMenu` for row actions.
- **Suggested command:** `/impeccable adapt`

**[P1] Excluded items can't be viewed or restored**
- **Location:** `AppModel.swift:165-188`, `SettingsView.swift`
- **Category:** UX / harden
- **Impact:** "Exclude" is permanent from the UI's point of view. There's no list of exclusions, no un-exclude and no undo, and if `exclusionStore.add` fails it's silently ignored (`catch { return }`).
- **Recommendation:** Add an "Exclusions" section in Settings with remove buttons, show a "Undo exclude" toast-style inline notice, and report failures.
- **Suggested command:** `/impeccable harden`

**[P1] The design system docs contradict the shipped code**
- **Location:** `BrandTheme.swift:18-26` vs `DESIGN.md` § Color, `BRANDKIT.md` § Color, `VERIFY.md`
- **Category:** Design system
- **Impact:** Commit `f1adfc2` replaced Space Garden with Greenhouse but left all three documents describing Space Garden. The legacy aliases now lie about what they are: `openMint` is beige `clay`, `scopeForest` is muted `sage`, and `freshLeaf` is a darker `moss`. Any future contributor, human or agent, following DESIGN.md will produce the wrong colors, and VERIFY.md's contrast claims are no longer true.
- **Recommendation:** Decide the direction first. Then rename the tokens to their roles (`accent`, `safe`, `review`, `destructive`, `info`, `textPrimary`, `textSecondary`, `surface`, `surfaceRaised`), delete the aliases, and regenerate DESIGN.md from the code.
- **Suggested command:** `/impeccable document`

**[P1] Permission guidance can't be acted on**
- **Location:** `PermissionBannerView.swift`, `AppModel.swift:48-52`
- **Category:** UX
- **Impact:** The steps tell users to open System Settings › Full Disk Access, but there's no button to get there. Before the first scan, the banner shows a green check shield next to "Scan not started.", which signals "all good" when nothing has happened yet.
- **Recommendation:** Add an "Open Full Disk Access Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`). Hide the banner, or show a neutral state, until a scan has run.
- **Suggested command:** `/impeccable clarify`

### P2: Minor

**[P2] Results rendering cost grows with result count** (`ResultsView.swift:20-38, 51-71, 122`; `AppModel.swift:94-99, 142-150`). The `filtered` property, which runs filter + search + sort over every result, is evaluated about 6 times per body pass (header count, `totalBytes`, `selectionState`, `ForEach`, `onChange` map, and `baseFiltered` separately). `selectionSummary` scans all results twice per pass. Every `ResultCardRow` observes the whole `AppModel`, so one checkbox click re-renders every row, and each streamed result spawns its own `Task` hop, publishing thousands of times per scan. **Fix:** cache the filtered/sorted array in `@State` keyed on its inputs, batch streamed results (for example every 100 ms), and pass `isSelected` into rows instead of the model. → `/impeccable optimize`

**[P2] Selection is global but looks local** (`ResultsView.swift:57-59`). The "N selected · X GB" header and the Review sheet include items selected in *other* destinations, which aren't visible here. The quick-win checkboxes on the Dashboard toggle a selection that nothing on the Dashboard uses. **Fix:** scope selection per destination, or label it "N selected across all categories". → `/impeccable clarify`

**[P2] Nested scroll in Quick Wins** (`DashboardView.swift:106-111`, `ResultsView.swift:214-228`). `ResultsTable` wraps its own `ScrollView` inside the dashboard's `ScrollView` with `minHeight: 220`, and 6 rows don't fit, so a scroll region sits inside a scroll region. **Fix:** render quick wins as a plain `VStack`. → `/impeccable layout`

**[P2] The "greenhouse" metaphor leaks into the UI copy** (`DashboardView.swift:136`, `GrowthSummaryView.swift:110`, `SidebarView.swift:17, 74`). "Your greenhouse is growing.", "ready for pruning", "Scanning greenhouse…" and a "Greenhouse" subtitle under the product name. DESIGN.md says the metaphor "must not introduce… literal scenery", and the voice guide asks for "calm, useful, and specific". The hero headline also never changes: it says "growing" before any scan and after cleanup alike. **Fix:** make the headline state-driven ("Let's see where your space went." → "You found 6.2 GB of breathing room." → "Moved safely to Trash."). The approved lines are already in DESIGN.md § Voice, and `StoragePresentation.reclaimCopy` is written but unused. → `/impeccable clarify`

**[P2] Copy defects**
| Location | Current | Suggested |
|---|---|---|
| `GrowthSummaryView.swift:69`, `ResultsView.swift:51` | "1 items found" / "0 items found" | Inflect plurals: `^[\(n) item](inflect: true)` |
| `DashboardView.swift:53` | "Safe / generated" | "Safe to remove" |
| `ItemDetailView.swift:53` | "Flagged Reason" (alarm framing) | "Why it's here" |
| `ItemDetailView.swift:70` | Confidence shows raw enum "High" | "High confidence" + one-line meaning |
| `SafetyCategoryPresentation.swift:35` | "Safe to remove - apps rebuild…" | "Safe to remove. Apps rebuild it as needed." |
| `CleanupReviewSheet.swift:79` | "Move Selected Items to Trash" | "Move 6 Items to Trash" |
| `AppModel.swift:17` / `CleanupReportView.swift:13` | "Cleanup History" (holds only the last, unpersisted session) | "Last Cleanup", or persist a real history |
| `DashboardView.swift:97-103`, `ResultsView.swift:73` | Empty states with no action; `checkmark.seal` implies success | Add a "Start Scan" button (EmptyStateView already supports `commandLabel`); use a neutral symbol |

→ `/impeccable clarify`

**[P2] Disabled rows don't say why** (`ResultsView.swift:243-247`). A grey checkbox on "Do not bulk delete" rows has no tooltip or accessibility hint. **Fix:** `.help("Review this item manually — CleanScope won't bulk delete personal or synced data.")`. → `/impeccable clarify`

**[P2] Icon-only controls and toggle states are unlabeled** (`ResultsView.swift:137-139, 301-308, 151-164`). The ⋯ row menu and the search clear button have no `.accessibilityLabel` or `.help`. Sort pills don't expose `.isSelected`. → `/impeccable harden`

**[P2] Safety and permission copy use the rounded font** (`ResultsView.swift:348`, `ItemDetailView.swift:131`). DESIGN.md: "Safety and permission copy always use the standard system design, never rounded." In practice nearly every text style is `.rounded`, so data values no longer stand out as the one rounded element. → `/impeccable typeset`

**[P2] Type scale drift.** Page titles are 26 pt rounded in Results/Dashboard and 28 pt default in Cleanup History. Fixed 10 pt text is used for paths, the sidebar footer and the gauge caption, which is below comfortable macOS body size and also low-contrast. → `/impeccable typeset`

**[P2] Shape tokens drift from the spec.** `BrandTheme.radius` = 14 (spec 7–10). Capsules are used for the sidebar selection, scan button, sort, search and detail buttons, against the spec's "Avoid pills except compact status tokens". Cards use a border *and* a hover shadow (spec: "never both"). → `/impeccable polish`

**[P2] Item detail sheet** (`ItemDetailView.swift`). Uses `.ultraThinMaterial` (glass anti-reference). The "Size vs. Large File Threshold" bar turns *terracotta*, the destructive/failure color, just because a file is big, which suggests danger where there is none. The name is `lineLimit(1)` with no tooltip. A sheet opened from the Dashboard shows a stale copy of the result (`DashboardView.swift:119-121`, unlike `ResultsView.currentResult`). → `/impeccable distill`

**[P2] Tokens are built in the wrong colorspace** (`BrandTheme.swift:73`). `NSColor(calibratedRed:…)` interprets the hex values as Generic RGB, so every token renders slightly off its sRGB spec. **Fix:** `NSColor(srgbRed:…)`. → `/impeccable colorize`

**[P2] Settings** (`SettingsView.swift`). "Show advanced categories" is a dead control: nothing reads `showAdvancedCategories`. The large-file stepper goes from 100 MB to 5 GB in 100 MB steps, up to 49 clicks. Use a `Picker` (250 MB / 500 MB / 1 GB / 2 GB / 5 GB). `settingsStore.save` failures are swallowed. → `/impeccable harden`

### P3: Polish

- **Dead code:** `ResultRowView`, five gradient aliases, `StoragePresentation.reclaimCopy` / `growthStage`, and `ResultsTable.sortOrder` / `showsBulkSelection` / `onToggleAll`.
- **Haptics:** firing `NSHapticFeedbackManager` on sort-pill clicks and at scan completion (when the user's finger is rarely on the trackpad) adds nothing. Keep it for direct manipulation only.
- **"Available after"** silently falls back to "before" when the post-cleanup reading is missing (`CleanupReportView.swift:48`), so it shows identical numbers. Show "—".
- **Minimum window** of 1040 × 680 with a fixed 210 pt sidebar. Once the sidebar is native and collapsible, the minimum can drop to about 800 pt.

---

## Patterns & Systemic Issues

1. **The restyle skipped the system layer.** One commit changed 10 files of UI without touching DESIGN.md, BRANDKIT.md, VERIFY.md or the token names. Most P2 drift findings come from this.
2. **Native controls swapped for custom ones.** Sidebar, table, search, sort, checkbox and buttons are all hand-built `.plain` buttons with capsule backgrounds. Each loses keyboard, focus and VoiceOver behavior that the native control would give for free.
3. **Fill tokens double as text tokens.** `sage`, `amber`, `terracotta`, `warmGray` and `finderBlue` were tuned as fills and are used directly as text, which explains nearly every contrast failure.
4. **Destructive paths aren't consistent.** The bulk path has a review sheet (good), but the quick-wins path widens the scope, and the single-item paths skip review entirely.
5. **Errors are silently swallowed.** `try?` and `catch { return }` on settings save, exclusion add and scan-history save. Users never learn that something failed.

## Positive Findings

- **Strong safety model at the data layer.** `canDelete` gating, risky rows disabled, ineligible rows skipped inside shift-ranges, and protected/synced data never bulk-selectable.
- **Safety never relies on color alone.** Every category has a filled SF Symbol and a literal text label, as the spec requires.
- **The review sheet is well written.** It names Trash, shows count, bytes and a per-category breakdown, and says "Nothing is permanently deleted."
- **The cleanup report shows all four outcomes**, including zero states ("None"). That's transparent and matches the spec.
- **Checkbox accessibility is done properly:** contextual labels ("Select node_modules"), values (Selected / Partially selected) and the `.isSelected` trait.
- **Decorative brand marks are hidden from VoiceOver**, and the standalone mark announces "CleanScope".
- **Menu commands** ⌘R (scan) and ⌘. (cancel) exist, and the detail sheet supports Escape.
- **Every color has a light and a dark variant**, and most dark-mode text pairs pass AA.
- **Settings uses a native grouped `Form`** with real toggles. That's the model the rest of the app should follow.

---

## Recommended Actions

1. **[P0] `/impeccable harden`.** Limit Quick Wins cleanup to the reviewed items, remove Return-to-confirm, send single-item trashing through review or add Undo, surface swallowed errors, add exclusion management, and fix the 0-byte Available reading.
2. **[P1] `/impeccable clarify`.** Separate safe from review-needed bytes in the headline number, make the hero copy state-driven, add a Full Disk Access button, and fix plurals and labels.
3. **[P1] `/impeccable adapt`.** Move to `NavigationSplitView` + `List(selection:)`, `Table` with sort descriptors, `.searchable`, toolbar actions and native buttons.
4. **[P1] `/impeccable colorize`.** Split fill and text tokens to reach ≥ 4.5:1, fix the dark-mode CTA, add increased-contrast variants, and switch to sRGB.
5. **[P1] `/impeccable animate`.** Gate all motion on Reduce Motion, clamp durations to 150–220 ms, and remove hover scaling.
6. **[P1] `/impeccable distill`.** Remove the gauge (and its fake 500 GB), the glass materials and the threshold bar. Bring back the specified growth stages if growth imagery is wanted.
7. **[P1] `/impeccable document`.** After deciding Greenhouse vs Space Garden, rename the tokens by role and regenerate DESIGN.md, BRANDKIT.md and VERIFY.md.
8. **[P2] `/impeccable optimize`.** Cache filter/sort results, batch streamed results, and stop rows from observing the whole model.
9. **[P2] `/impeccable typeset`.** Limit `.rounded` to data values, use system styles instead of fixed 10 pt text, and unify page-title styling.
10. **[P2] `/impeccable polish`.** Radius back to 7–10, pills only for status, border *or* shadow, and remove dead code.

You can ask me to run these one at a time, all at once, or in any order you prefer.

Re-run `/impeccable audit` after fixes to see your score improve.

---

## Resolution — 2026-10-20

Every finding above is addressed on `fix/audit-findings`, which builds on the P0 fix in `fix/cleanup-scope-matches-review`. Direction decision: **keep Greenhouse** and re-sync the docs to it.

| Finding | Resolution |
|---|---|
| P0 Quick Wins scope | Fixed in `9365233`: the review sheet hands back exactly its items |
| P1 "Ready to reclaim" counts risky bytes | Headline is safe bytes only; review-needed space has its own line |
| P1 Fake 500 GB gauge, invisible track | Gauge removed; disk bar uses the real volume; Sprout Lens growth stages restored |
| P1 "Available 0 bytes" before scan | Disk read from the volume at launch and after cleanup; missing values show "—" |
| P1 Return confirms Trash | Fixed in `9365233` |
| P1 One-click Move to Trash | Context menu and detail sheet now open the review sheet |
| P1 Contrast | Role tokens rebuilt; every text token ≥ 4.74:1 in light/dark/increased contrast; white on accent ≥ 4.6:1 |
| P1 Reduce Motion | One `BrandTheme.animation(reduceMotion)` helper; hover scaling and 0.6–1.0 s animations removed |
| P1 Custom sidebar | `NavigationSplitView` + `List(selection:)` with sections and count badges; Settings only in ⌘, |
| P1 Card list | Native `Table` with sortable columns, context menu, double-click/Return details, `.searchable`, toolbar action |
| P1 Exclusions | Undo bar, Settings list with Remove, errors surfaced. **Also fixed:** the scanner ignored saved exclusions, so excluded items came back deletable after every rescan |
| P1 Docs drift | DESIGN.md regenerated from code; BRANDKIT.md and VERIFY.md updated; aliases deleted |
| P1 Permission guidance | "Open Full Disk Access" button; no green check before the first scan |
| P2 Render cost | Results batched every 150 ms; summary and counts derived once per change; filter/sort once per render; type-based cached file icons |
| P2 Global selection | Header says how many selected items sit in other sections |
| P2 Nested scroll | Quick wins render as a flat grouped list |
| P2 Copy | State-driven headline, inflected counts, renamed labels, empty states with actions, "Last Cleanup" |
| P2 Disabled rows, unlabeled icons | Tooltips and VoiceOver hints explain disabled checkboxes; icon-only controls labelled |
| P2 Typography | Rounded only for data values; system text styles; window titles via `navigationTitle` |
| P2 Shape | Radius 10/7; no decorative pills; fill or border, not both |
| P2 Detail sheet | Native grouped `Form`; glass and threshold bar removed; always shows current data |
| P2 sRGB | Tokens built with `NSColor(srgbRed:)` |
| P2 Settings | Dead toggle removed; threshold is a Picker; save errors surfaced |
| P3 | Dead code and haptics removed; "Available after" shows "—"; minimum window 820 × 560 |

**Found during verification and fixed:** nested folders were counted separately (e.g. `BraveSoftware`, `Brave-Browser`, `Default`, each 1.05 GB). All byte totals now count only the outermost folder, quick wins list outermost items, and cleanup trashes only the outermost item, deselecting anything inside it. On the live scan the safe figure went from 8.01 GB to 1.85 GB.

Verification: 57 tests pass, build has no warnings, and snapshot screens were reviewed in light, dark and never-scanned states (see VERIFY.md).
