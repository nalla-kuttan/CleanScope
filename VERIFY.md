# CleanScope Verification

## Automated

- `./script/swiftpm.sh test` passes.
- `./script/swiftpm.sh build` passes.
- `./script/build_and_run.sh --verify` builds a real app bundle, launches it, and confirms the process is running.

- Visual check (debug builds only, needs no Screen Recording permission):
  `dist/CleanScope.app/Contents/MacOS/CleanScopeApp --snapshot-dir <dir>` writes a PNG of
  every destination, an item detail sheet, `CleanupReviewSheet` (`review-<appearance>.png`,
  five sample items, never confirmed), the menu bar sprout stages and the 820 × 560 minimum
  window, then quits. `--snapshot-dir` must be the first flag. A run that opens no window and writes nothing was launched with `--dark-preview` or `--reduce-motion` before a value flag such as `--snapshot-disk-used`; put those two last. Every other flag below is
  debug-only and none of them scans, cleans or touches a file:
  - `--dark-preview`: dark appearance. `--snapshot-empty`: the never-scanned state (files get an `empty-` prefix).
  - `--reduce-motion`: forces Reduce Motion on in `MotionPolicy`.
  - `--snapshot-scan-progress <0…1>`: a simulated mid-scan Dashboard and Storage Map built from the saved scan (add `--snapshot-scan-cancelled` for a cancelled one). Use a separate directory.
  - `--snapshot-disk-used <0…1>`: the Dashboard's disk weather reads the disk as that full (try 0.5, 0.8 and 0.93 for the three weather lines).
  - `--snapshot-select one|all`: selects the largest eligible item, or every eligible item, so the toolbar basket shows a selection.
  - `--snapshot-flight`: selects one Ready to Delete item and captures the basket flight (`flight-early/mid/after`).
  - `--snapshot-cleanup`: seeds an in-memory cleanup and captures `lastCleanup-mid` (terrarium mid-compost), `lastCleanup` and `dashboard-cleaned`.
  - `--map-fixture <N>`: replaces the session with a synthetic N-item Storage Map. `--snapshot-collapse` (with a fixture and `--snapshot-select all`) captures `collapse-mid` and `collapse-after`.
  - `--map-benchmark`: with `--map-fixture`, times the map (see Performance checks) and quits.
  - `--terrarium-cpu-check <seconds>`: idles on the Dashboard shown, then minimised, and prints this process's CPU use for both.
  The sidebar's material can't be drawn in-process, so its rows appear blank in these captures.

`script/swiftpm.sh` delegates to SwiftPM directly and works around incomplete
Command Line Tools installations where Apple ships stale private manifest
interfaces or omits automatic Swift Testing framework paths.

## Manual Scan Checks

- Start a limited scan.
- Confirm Dashboard shows disk used, available, potential cleanup, and protected bytes.
- Confirm progressive results appear before scan completion on a folder with many files.
- Confirm permission-denied paths appear as skipped paths and do not crash the app.
- Confirm symlinks are not recursively followed.
- Confirm Documents and Desktop results are marked Do Not Bulk Delete during a full scan.
- Confirm caches and generated build folders are marked Safe to Delete.
- Confirm unknown Application Support folders are marked App/tool dependent.
- Confirm cloud-synced folders are marked Do Not Bulk Delete.

## Manual Cleanup Checks

- Select a Safe to Delete test file in a temporary cache folder.
- Confirm the cleanup sheet says Move Selected Items to Trash.
- Confirm the file moves to Trash.
- Confirm the cleanup report shows deleted, skipped, blocked, failed, and recovered bytes.
- Select a Do Not Bulk Delete item and confirm CleanScope skips it or requires manual review.
- Confirm no permanent deletion is offered as the default path.

## Tone and UI Checks

- No scareware language appears in dashboard, results, confirmations, or reports.
- Safety labels match: Safe to delete, Review recommended, App/tool dependent, Do not bulk delete.
- Rows do not truncate the category label at the default macOS window size.

## UI States

- Dashboard before any scan: "Let’s see where your space went." with the first-run reassurance, real disk capacity ("X available of Y", no safe-space figure until a scan), and a Start Scan empty state.
- Scanning: sidebar shows Cancel Scan plus a live count; the hero reads "Looking for room to grow…" with a progress bar, the scan theatre shows the path and four jars with the streamed counts, and the Storage Map outlines tiles the scan has not reached.
- Completed dashboard: safe-to-reclaim figure (nested folders counted once), review-needed space on its own line, disk bar, permission state, and up to six outermost quick wins.
- Permission-limited state: "Open Full Disk Access" button plus expandable steps.
- Results: native Table with sortable columns, search in the toolbar, checkbox column with shift-range selection, disabled checkboxes explain themselves on hover.
- Every Move to Trash path opens the review sheet listing exact items; Return does not confirm.
- Exclude shows an Undo bar; Settings lists exclusions with Remove; a rescan keeps excluded items undeletable.
- Last Cleanup shows before/after availability plus moved, skipped, blocked, and failed outcomes, including zero states.

## Appearance and Accessibility

- Every text token is at least 4.5:1 on both surfaces in light, dark and increased-contrast appearances (lowest 4.74:1); white on accent at least 4.6:1.
- Safety category is always icon plus text label, never color alone.
- Reduce Motion removes every animation (see Living Interface Checks); there is no hover scaling.
- Sidebar and results support arrow keys, Return, ⌘A and VoiceOver selection state through native List and Table.
- Icon-only buttons carry accessibility labels and help text.
- Decorative Sprout Lens marks are hidden from VoiceOver.

## Living Interface Checks

New snapshot states (each in light, dark and with `--reduce-motion`):

- Dashboard idle, scanning (`--snapshot-scan-progress 0.5`), results, tight disk (`--snapshot-disk-used 0.93`: "Room is tight. X available." in the hero) and cleaned (`--snapshot-cleanup`).
- Dashboard terrarium shows five soil layers; Last Cleanup shows the terrarium after the compost; the menu bar popover thumbnail comes from the same scene.
- Storage Map with a fixture: tiles in the safety fills, the free-space tile only on a whole-Mac scan, the lens resting on the largest selectable tile, selected tiles lifted with a check badge, and `collapse-mid` / `collapse-after`.
- Module icons at 64 pt (headers, empty states), 40 pt (results header) and 32 pt (Dashboard Modules row, menu popover); none in the sidebar, tables or dialogs.
- Toolbar basket: "Nothing selected" disabled, then item count and total; "N selected in other sections" in the results header; flight frames.
- Menu bar sprout stages 0, 1 and 2 on light and dark bars, plus the size label.
- `CleanupReviewSheet` is pixel-identical with and without `--reduce-motion` (`cmp review-light.png` between the two runs prints nothing).
- A live Dashboard with `--reduce-motion`: the terrarium is a still frame, the hero crossfades, no sweep band, no theatre dots, no flight, the recovered number appears without rolling.
- Trashed items disappear from every list and total after a confirmed cleanup, while Last Cleanup still lists them.

## Performance checks

- Storage Map, 3,000 tiles: `CleanScopeApp --map-fixture 3000 --map-benchmark` renders the map and the lens offscreen 300 times at 1180 × 700 (2×) and prints the mean and p95. **Pass: mean at or under 16.7 ms.** It prints `shader off (SwiftUI glass)` when the build has no compiled Metal library.
- Terrarium CPU: `CleanScopeApp --snapshot-dir <dir> --terrarium-cpu-check 10` prints the process CPU use while the Dashboard is visible and while the window is minimised (the minimised figure should be near zero).

## Pending manual verification

These need a person at a Mac with Xcode (the Metal shader needs its toolchain). None of them has been done; do not tick an item that was not run.

- [ ] **VoiceOver, Storage Map.** Turn VoiceOver on (⌘F5), open Storage Map with a scan loaded, and move into the map. Confirm each tile reads "Name, size, safety label, selected/not selected" (selectable tiles only for the last part), that Space toggles the focused tile, and that the Open action on a selectable folder drills in. Confirm the lens bubble is not read as a second element.
- [ ] **VoiceOver, basket.** Select items. Confirm the toolbar basket reads the item count and total, activating it opens the review sheet, and "N selected in other sections" is read in the results header.
- [ ] **VoiceOver, terrarium.** On the Dashboard, confirm the terrarium is one element reading "Storage terrarium: … safe to reclaim, … worth a closer look, … app data, … personal files, … macOS and apps."
- [ ] **Keyboard only, Storage Map.** Without the mouse, Tab into the map, then arrow through every tile (top to bottom, then left to right), Space to select and deselect, Return to open a folder, ⌘[ to go up. Confirm focus is visible on every tile, including small ones under the lens, and that the toolbar basket is reachable by Tab.
- [ ] **Instruments, Storage Map.** Time Profiler or the Animation Hitches template on a 3,000-tile map (`--map-fixture 3000`), moving the lens continuously for 10 s. Pass: at most 1% dropped frames.
- [ ] **Instruments, terrarium.** Dashboard idle: under 10% of one CPU core. Cover or minimise the window and confirm GPU work stops (Metal System Trace).
- [ ] **Terrarium pause when the real window is occluded.** Snapshot runs treat the window as visible, so this path is only exercised by hand: cover the window with another app's window, then check Activity Monitor (CPU, GPU) and confirm the terrarium stops redrawing; bring the window back and confirm it resumes without the lens jumping.
- [ ] **Live menu bar.** Enable the menu bar extra in Settings. Confirm the sprout draws as a template image in light and dark menu bars and with a tinted wallpaper, the size label appears at 14 days and 500 MB (set the clock or the cleanup log to test), and the popover shows the terrarium thumbnail and "Review Quick Wins…".
- [ ] **Menu bar label at midnight.** Leave the app running across midnight (or change the system date). Confirm the days-since-cleanup stage and label refresh without relaunching.
- [ ] **Metal lens shader.** Build on a machine with Xcode so `build_and_run.sh` compiles `Lens.metal` into the resource bundle. Confirm the benchmark prints `shader on`, the lens refracts, its content lines up with the ring (compare `map-lens-check.png`), and the benchmark is still at or under 16.7 ms. Also confirm that without the library the map still works.
- [ ] **Permanent-delete alert, Return key.** Turn on Delete immediately in Settings, start a permanent delete and confirm the second alert. Press Return: it must activate Cancel, never the delete button. Escape must also cancel.

## 2026-06-24 — Bulk selection and ready cache

- `./script/swiftpm.sh test`: passed with 46 tests.
- `./script/swiftpm.sh build`: passed.
- `./script/build_and_run.sh --verify`: passed and launched the staged app bundle.
- Ready to Delete: verified in the live app with 2,709 high-confidence cache results; sampled paths were under recognized cache locations.
- Cache predicate: automated tests cover Library caches, package-manager caches, logs, Trash, generated folders, protected items, excluded items, and lower-confidence items.
- Select all visible: verified live for unchecked and checked states; the selection summary updated to 2,709 items and 21.81 GB.
- Clear selection: verified live; the review action returned to its disabled state.
- Mixed-state and eligible range calculations: covered by automated presentation tests, including ineligible rows within a range.
- Shift-click handling: implemented through the native event modifier and eligible range helper; direct modifier-key UI automation was unavailable in this runtime.
- Cleanup review payload: verified live without confirming deletion; the sheet showed 2,709 selected Safe to delete items and 21.81 GB, then was cancelled.
- Accessibility: live accessibility output exposed Select/Deselect all labels, selected values, disabled review state, and individual row selection values.
- Layout: verified in the default expanded window with the Ready to Delete subtitle, selection control, summary actions, table columns, and long paths visible without overlap.
- Safety: no cleanup confirmation was activated and no files were moved to Trash during verification.

## Gap Features Checks

- A Developer scan lists container caches and Chromium caches as Safe to delete. IndexedDB and Local Storage are never listed as safe.
- Cloud-only files show the cloud badge, count 0 bytes, and can't be selected.
- The Storage Map drill-down and the selection made from it match the list view.
- The menu bar extra is off by default. Enabling it keeps the app alive after the window closes.
- The low-disk and Trash alerts respect snooze and don't repeat.
- Delete immediately asks for a second confirmation with item count and size, including for single-item actions.
- Protection finds the EICAR test file in a scanned folder, inside a ZIP, and nothing in a clean folder.

## 2026-10-20 — CleanMyMac gap features

- `./script/swiftpm.sh test`: passed with 184 tests in 31 suites.
- `./script/swiftpm.sh build`: passed with no warnings.
- `./script/build_and_run.sh --verify`: passed; the app bundle launched and kept running.
- Parallel scanning (F4): a warm Developer scan of this Mac took 16.9 s serial (`maxConcurrency: 1`) and 6.6 s with 6 workers, with the same 3,601 results. The automated test compares serial and parallel result sets on a fixture with a symlink and duplicate roots.
- Verified on macOS 27.0 (Apple Silicon): `/usr/sbin/periodic` is absent (the task is hidden), `/usr/bin/trash` exists, `XProtect.yara` exists, many containers are UUID-named (bundle id read from container metadata), battery capacities sit in the nested `BatteryData` dictionary, and Foundation's directory listing hides `._` AppleDouble files (the drive cleaner reads them with `readdir`).
- Live samplers on this Mac: CPU, network, battery charge and battery health read correctly; no Bluetooth accessories reported `BatteryPercent`; the experimental SMC temperature returned no reading, so its row stays hidden.
- Rule signing: a manifest from `script/sign_rules.swift` verified with the app's verifier.
- Live UI checked by window capture: sidebar sections and the System-managed space card on the Dashboard, and the Storage Map empty and scanning states.
- Not verified live: Storage Map tiles with real data, the menu bar extra, notifications and their actions, administrator prompts, login items through System Events, real-time protection events, and hung-app detection. Scans in the rebuilt ad-hoc–signed app stopped at macOS privacy prompts (Downloads, other apps' data), and window capture started asking for screen-recording access, so those checks need a person at the Mac.
- `tmutil thinlocalsnapshots` without administrator rights (Open Question 1) was not run, to avoid removing snapshots during verification. The action is off by default and shows macOS's error if it fails.

## 2026-10-20 — Audit fixes

- `./script/swiftpm.sh test`: passed with 57 tests (new: exclusion remove/apply, count inflection, state headlines, nested-folder byte totals, cleanup plan trashing only outermost items).
- `./script/swiftpm.sh build`: passed with no warnings.
- `./script/build_and_run.sh --verify`: passed.
- Snapshot pass in light, dark and never-scanned states: dashboard, all result destinations, Last Cleanup, item detail and the minimum window reviewed. The safe-to-reclaim figure on the live scan dropped from 8.01 GB to 1.85 GB once nested folders stopped being double-counted.
- Sidebar structure confirmed from the view tree (3 sections, 10 destinations); its rows can't be rendered in-process.
- Safety: no cleanup confirmation was activated and no files were moved to Trash during verification.

## 2026-10-20 — Merge of audit fixes into gap features

- `./script/swiftpm.sh build`: passed with no compiler warnings.
- `./script/swiftpm.sh test`: passed with 196 tests in 33 suites, including the audit's `cleanupPlan*`, `outermost*` and exclusion tests and every gap-features suite.
- Every destructive path, including single-item actions and "Delete immediately", goes through the cleanup review sheet, which hands back exactly the items it showed.
- Not yet verified live: snapshot pass of the gap-features destinations in the audit layout.

## 2026-10-21 — Living interface

- `./script/swiftpm.sh test`: passed with 263 tests in 42 suites.
- `./script/swiftpm.sh build`: passed with no warnings (all sources touched first, so everything recompiled).
- `./script/build_and_run.sh --verify`: passed; the app bundle launched and kept running. It reported that the Metal toolchain is missing, so the lens shader is skipped and the SwiftUI glass fallback is used.
- Snapshot pass in light, dark, `--snapshot-empty`, `--reduce-motion` and dark with `--reduce-motion`: 29 PNGs per full run (27 for never-scanned), no blank frames in the Dashboard, Storage Map, Last Cleanup, review sheet and minimum-window captures that were opened. Extra state runs: scanning at 50%, simulated cleanup, basket flight, disk weather at 93% in light and dark, and a 400-item Storage Map fixture with all eligible tiles selected and the collapse.
- `CleanupReviewSheet` snapshots with and without `--reduce-motion`: `cmp` reported the PNGs identical in light and in dark (SHA-1 `31dff86f…` for light). The same flag does change the Dashboard capture, so the comparison is not vacuous.
- 3,000-tile Storage Map benchmark (`--map-fixture 3000 --map-benchmark`): mean 8.36 ms per frame, p95 9.05 ms, max 9.78 ms, 300 of 300 frames rendered, lens at its resting tile, shader off (SwiftUI glass). Pass (limit 16.7 ms).
- Not verified: everything under Pending manual verification (VoiceOver, keyboard-only pass, Instruments, live menu bar, Metal lens shader, occluded-window pause, midnight label refresh, permanent-delete Return key). The Metal shader could not be built on this machine, so only the fallback was measured.
- Safety: no cleanup confirmation was activated and no files were moved to Trash. The review sheet snapshot only displays sample items.
