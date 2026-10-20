# CleanScope Verification

## Automated

- `./script/swiftpm.sh test` passes.
- `./script/swiftpm.sh build` passes.
- `./script/build_and_run.sh --verify` builds a real app bundle, launches it, and confirms the process is running.

- Visual check (debug builds only, needs no Screen Recording permission):
  `dist/CleanScope.app/Contents/MacOS/CleanScopeApp --snapshot-dir <dir>` writes a PNG of
  every destination, an item detail sheet and the 820 × 560 minimum window, then quits.
  Add `--dark-preview` for dark mode and `--snapshot-empty` for the never-scanned state.
  It never scans or moves anything to Trash. The sidebar's material can't be drawn
  in-process, so its rows appear blank in these captures.

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

- Dashboard before any scan: "Let’s see where your space went.", real disk capacity, "—" for safe space, and a Start Scan empty state.
- Scanning: sidebar shows Cancel Scan plus a live count; the Sprout Lens grows through three stages.
- Completed dashboard: safe-to-reclaim figure (nested folders counted once), review-needed space on its own line, disk bar, permission state, and up to six outermost quick wins.
- Permission-limited state: "Open Full Disk Access" button plus expandable steps.
- Results: native Table with sortable columns, search in the toolbar, checkbox column with shift-range selection, disabled checkboxes explain themselves on hover.
- Every Move to Trash path opens the review sheet listing exact items; Return does not confirm.
- Exclude shows an Undo bar; Settings lists exclusions with Remove; a rescan keeps excluded items undeletable.
- Last Cleanup shows before/after availability plus moved, skipped, blocked, and failed outcomes, including zero states.

## Appearance and Accessibility

- Every text token is at least 4.5:1 on both surfaces in light, dark and increased-contrast appearances (lowest 4.74:1); white on accent at least 4.6:1.
- Safety category is always icon plus text label, never color alone.
- Reduce Motion removes every animation; there is no hover scaling.
- Sidebar and results support arrow keys, Return, ⌘A and VoiceOver selection state through native List and Table.
- Icon-only buttons carry accessibility labels and help text.
- Decorative Sprout Lens marks are hidden from VoiceOver.

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

## 2026-10-20 — Audit fixes

- `./script/swiftpm.sh test`: passed with 57 tests (new: exclusion remove/apply, count inflection, state headlines, nested-folder byte totals, cleanup plan trashing only outermost items).
- `./script/swiftpm.sh build`: passed with no warnings.
- `./script/build_and_run.sh --verify`: passed.
- Snapshot pass in light, dark and never-scanned states: dashboard, all result destinations, Last Cleanup, item detail and the minimum window reviewed. The safe-to-reclaim figure on the live scan dropped from 8.01 GB to 1.85 GB once nested folders stopped being double-counted.
- Sidebar structure confirmed from the view tree (3 sections, 10 destinations); its rows can't be rendered in-process.
- Safety: no cleanup confirmation was activated and no files were moved to Trash during verification.
