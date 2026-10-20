# CleanScope Space Garden Verification

## Automated

- `./script/swiftpm.sh test` passes.
- `./script/swiftpm.sh build` passes.
- `./script/build_and_run.sh --verify` builds a real app bundle, launches it, and confirms the process is running.

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

## Space Garden UI States

- Dashboard empty state shows the Sprout Lens, practical scan guidance, and Start Scan.
- Scanning state changes the primary command to Cancel and grows through finite stages.
- Completed dashboard shows reclaimable space, available space, safe/generated count, review count, permission status, and Quick Wins.
- Permission-limited state exposes expandable Full Disk Access steps.
- Safe Cleanup selection uses both a checkmark and state tint; risky rows remain disabled.
- Review sheet names Trash and shows selected item count, bytes, and category breakdown.
- Item detail exposes Finder, Exclude, and Move to Trash only when operational.
- Cleanup report shows before/after availability plus deleted, skipped, blocked, and failed outcomes, including zero states.
- Settings retains native toggles and stepper beneath the compact product header.

## Appearance and Accessibility

- Light mode palette maintains contrast and does not rely on color alone for safety.
- Dark mode palette maintains contrast across dashboard, results, sheets, settings, and report.
- Reduce Motion removes scale transforms and uses immediate state changes or crossfades.
- Every icon-only button has an accessibility label or help text.
- Decorative Sprout Lens marks are hidden from VoiceOver; meaningful standalone marks announce CleanScope.
- Default 1040 × 680 window shows the dashboard header, growth surface, metrics, permission banner, and Quick Wins heading without overlap.
- Expanded window keeps content constrained and readable rather than stretching tables or copy excessively.
- The custom app icon appears in Finder, the app bundle, and the Dock.

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
