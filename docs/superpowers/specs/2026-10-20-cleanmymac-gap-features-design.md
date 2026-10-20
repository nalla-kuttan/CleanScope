# CleanMyMac Gap Features Design

## Goal

Expand CleanScope with every capability CleanMyMac 5.7.1 has and CleanScope lacks: storage, performance, protection and menu bar monitoring.

Defaults stay safe. Cleanup moves items to Trash, and nothing is selected for the user. CleanMyMac's riskier behaviors (permanent deletion, pre-selection) are included as opt-in settings rather than defaults.

## Source of the Feature List

These features come from a static reverse-engineering pass over CleanMyMac 5.7.1 (Mac App Store build). Each feature notes what CleanMyMac was observed to do and how CleanScope will build it.

- Thresholds and UI choices marked **(design choice)** are ours; CleanMyMac's values were either not recovered or not worth copying.
- Items marked **(verify)** depend on macOS behavior that has not been tested yet.
- Section 9 lists CleanMyMac modules that were seen but not yet reverse-engineered.

## Product Document Impact

Several features conflict with the current `PRODUCT.md`:

- Its anti-references list gauges, warnings and one-click cleaning.
- Its Product Purpose is storage-only.

Update `PRODUCT.md` (purpose, users, anti-references) before building Phases 6–8, so design reviews and the UI audit use the new scope.

## Privilege Model

Several features need administrator rights: maintenance tasks, system logs, launch daemons and some malware removal. CleanScope uses one approach for all of them:

- **Default:** run the single command through `NSAppleScript` `do shell script "…" with administrator privileges`. macOS shows its own password prompt each time. No helper is installed, and nothing stays elevated.
- **Later option:** a privileged helper registered with `SMAppService.daemon(plistName:)` for repeated tasks. It needs a signed app and user approval in System Settings. Build this only if the per-task prompt becomes a real usability problem.

Every privileged command is a fixed string with validated arguments. User-supplied paths are never interpolated without shell quoting.

## Phasing

| Phase | Features |
|---|---|
| 0. Prerequisite | F0 Rule overrides |
| 1. Better junk detection | F1 Container caches, F2 Chromium/Electron caches, F3 Known app media caches, F25 System logs, F26 App Store download cache |
| 2. Scanner quality | F4 Parallel scanning, F5 File-flag awareness, F6 System path guards |
| 3. Storage visibility | F7 Purgeable space and local snapshots, F8 Storage Map |
| 4. Alerts | F9 Alert snooze store, F10 Menu bar status, F11 Low disk alert, F12 Trash size alert, F13 External drive alert |
| 5. Cleanup options | F14 Leftovers of apps in Trash, F27 Permanent delete option, F28 Preselect safe caches, F29 External drive cleaner |
| 6. Performance | F15 Maintenance tasks, F16 Login and background items, F17 Memory relief |
| 7. Monitoring | F18 System monitors, F19 Hung app detection, F20 Mac status summary, F21 Restart reminder, F22 Bluetooth device battery |
| 8. Protection | F23 Malware scanning, F24 Real-time monitoring, F30 Updatable rule set, F31 Privacy cleanup |
| 9. Not yet reverse-engineered | Uninstaller, Updater, Cloud Cleanup, Email Cleanup, Unused disk images, Smart Care, Assistant, My Clutter |

---

## F0. Rule Overrides (prerequisite)

### Problem

`ClassificationService.classify` selects the matching rule with the highest `SafetyCategory`, then confidence, then specificity. A new `safeToDelete` rule for `~/Library/Application Support/Slack/Cache` would lose to `tool.application-support` (`deleteIfAppUnused`), so F2 and F3 cannot work as written.

### Design

- Add `overrides: [String]` to `ClassificationRule`, defaulting to `[]`.
- In `classify`, after filtering matching rules, remove any rule whose `id` appears in the `overrides` list of another matching rule. Then apply the existing `max` ordering unchanged.
- Only `tool.application-support` and `tool.developer-storage` may be overridden. Rules with ids starting `protect.` can never be overridden; enforce this with a precondition in a test that iterates `builtInRules`.

### Tests

- Matching `safe.chromium-caches` plus `tool.application-support` yields `safeToDelete`.
- Matching `safe.chromium-caches` plus `protect.app-critical-data` (for example a Chrome path) still yields `doNotBulkDelete`.
- No built-in rule lists a `protect.*` id in `overrides`.

---

## F1. Sandboxed App Container Caches

### Observed in CleanMyMac

`CMSandboxContainersCachesScanTask` enumerates every folder in `~/Library/Containers/` and lists `<container>/Data/Library/Caches`.

### Behavior

- Developer and Full scans add `~/Library/Containers/*/Data/Library/Caches` as scan roots. Limited scan does not.
- Each container's cache folder is emitted as one folder result named after the app, for example "Mail cache (com.apple.mail)".
- The rest of the container (`Documents`, `Library/Application Support`, preferences) is never scanned by this feature.

### Implementation

- `ScanLocations`: add `containerCacheRoots(homeDirectory:)`, which lists `~/Library/Containers` and returns each `<entry>/Data/Library/Caches` that exists. Call it from `recommended(mode:)` for `.developer` and `.full`.
- Classification already works: the path contains `/library/caches/`, so `safe.known-caches` applies. Add `ownerApp` by reading the container's bundle identifier from the folder name.
- `shouldEmitFolder` already emits folders under `/Library/Caches` with non-zero size; no change needed.
- Display name: resolve with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and fall back to the bundle id.

### Permissions

On macOS 14 and later, reading another app's container triggers the "access data from other apps" prompt unless CleanScope has Full Disk Access. When reading a container fails with a permission error, record a `SkippedPath` with `.protectedByMacOS` so the existing permission banner explains it. Do not retry per container.

### Safety tests

- `~/Library/Containers/x/Data/Documents/file` is never `safeToDelete`.
- `~/Library/Containers/x/Data/Library/Application Support/db` is never `safeToDelete`.

---

## F2. Chromium and Electron App Caches

### Observed in CleanMyMac

`CMElectronAppsCacheScanTask` targets `~/Library/Application Support/<App>/Cache`, or `<container>/Data/Library/Application Support/<App>/Cache` for sandboxed apps.

### Behavior

Detect these regenerable Chromium cache folders inside any `~/Library/Application Support/<App>/` folder:

- `Cache`
- `Code Cache`
- `GPUCache`
- `DawnCache` and `DawnGraphiteCache`

Never match these, which hold user state: `Local Storage`, `IndexedDB`, `Session Storage`, `Service Worker`, `Cookies`, `databases`.

### Implementation

- New rule `safe.chromium-caches`:
  - matcher: `.all([.pathContains("/library/application support/"), .itemType(.folder), .any([.nameEquals("cache"), .nameEquals("code cache"), .nameEquals("gpucache"), .nameEquals("dawncache"), .nameEquals("dawngraphitecache")])])`
  - category `safeToDelete`, confidence `high`, specificity 85
  - `overrides: ["tool.application-support"]`
  - reason "Chromium app cache"; riskNote "The app rebuilds this cache. It may start a little slower the first time."
- `ownerApp`: the path component directly after `Application Support`.
- Emit these folders: extend `shouldEmitFolder` so a folder that matches a known-cache name under Application Support is emitted when its size is above 0.
- The existing `protect.app-critical-data` rule keeps Chrome and Firefox profile folders protected; F0 guarantees this.

### Tests

- `.../Application Support/Slack/Cache` is `safeToDelete`.
- `.../Application Support/Slack/IndexedDB` is not `safeToDelete`.
- `.../Application Support/Google/Chrome/Default/Cache` stays `doNotBulkDelete`.

---

## F3. Known App Media Caches

### Observed in CleanMyMac

Hardcoded paths in `SystemJunkScanning`, including Spotify, Adobe Media Cache, Telegram Desktop and several regional apps.

### Rules

| Rule id | Path (under home) | Category | Confidence |
|---|---|---|---|
| `safe.spotify-cache` | `Library/Application Support/Spotify/PersistentCache/Storage` | safeToDelete | high |
| `safe.adobe-media-cache` | `Library/Application Support/Adobe/Common/Media Cache Files` | safeToDelete | high |
| `review.telegram-media` | `Library/Application Support/Telegram Desktop/tdata/user_data` | probablyUnused | medium |

All three rules list `overrides: ["tool.application-support"]` and set `ownerApp`. Telegram is "review" because downloaded media may not be on the server anymore.

### Optional regional set

These paths were in CleanMyMac but are relevant mainly to Chinese-market apps. Add them only if users ask: WeChat, Tencent Video, QQ Music, Youku (exact paths are in the reverse-engineering notes).

### Implementation

Use `.pathContains` with the lowercased path fragment. Add matching fixtures to `ClassificationFixtures.swift`.

---

## F4. Parallel Scanning

### Observed in CleanMyMac

Space Lens uses `maxConcurrentScans` with a `maxDepthLevel` cap.

### Problem

`ScannerService.scanURL` awaits each child one at a time inside a single actor, so large trees scan serially.

### Design

- Fan out at two levels: each scan root, then each direct child folder of a root, becomes a work item.
- Run work items through a bounded task group: start up to `min(ProcessInfo.processInfo.activeProcessorCount, 6)` tasks, and start the next item when one finishes **(design choice)**.
- Each work item runs the existing recursive logic as a `nonisolated` function that returns a value `(bytes: Int64, results: [ScanResult], skipped: [SkippedPath])` instead of mutating `inout` arrays.
- Move `visitedRealPaths` into a lock-protected class modeled on `ScanCancellationState`, with one atomic `insertIfAbsent(_:) -> Bool`.
- The root folder's size is the sum of its children's work items plus its direct files. Emit the root folder result after its children finish.
- Keep `onResult` streaming as it is.
- Cancellation: every work item checks `cancellationState.isCancelled` at each directory, as today.

### Acceptance

- For a fixture tree, the parallel scan returns the same set of `(path, sizeBytes, category)` as the serial scan. Compare as sets; order may differ.
- Cancelling mid-scan returns status `.cancelled` with no crash.
- On a real home-folder Developer scan, record before and after timings in the plan's verification notes. There's no fixed target.

---

## F5. File-Flag Awareness: Cloud-Only and SIP-Protected Files

### Observed in CleanMyMac

Space Lens calls `lstat` and checks `st_flags & 0x40000000` (`SF_DATALESS`, a cloud placeholder whose content is not on disk). It also reads `ubiquitousItemDownloadingStatus`, blocks cloud-only items, and blocks rootless (SIP) protected paths.

### Behavior

- **Cloud-only files** (dataless):
  - Count 0 bytes toward cleanable space and folder totals.
  - Shown with a cloud badge and the note "Stored in the cloud only. Removing it here deletes it from the cloud."
  - `canDelete = false`, `deletionMethod = .manualReview`.
- **SIP-protected** (`st_flags & SF_RESTRICTED`, `0x00080000`):
  - `isProtected = true`, which already maps to `.notAllowed`.

### Implementation

- Add a small helper in Core: `FileFlags.read(path:) -> (isDataless: Bool, isRestricted: Bool)` using `lstat`.
- Call it once per file and directory in the scanner.
- Add `isCloudOnly: Bool` to `ScanResult` and `ClassifiedItemInput`. Give it a default of `false` in the decoder so saved sessions still load.
- In `classify`, `isCloudOnly` forces `canDelete = false` and `deletionMethod = .manualReview`.
- `ScanSummary`: add `cloudOnlyBytes`, using logical size for display only.
- Size rule: for dataless files, use 0 for `sizeBytes` even if `totalFileAllocatedSize` is nil. Today the fallback to `fileSize` would report the full logical size.

### Tests

Unit-test `FileFlags` against a real temporary file (both flags false). Test the classification path with an injected `isCloudOnly: true`.

---

## F6. System Path Guards

### Observed in CleanMyMac

Space Lens strips the `/System/Volumes/Data/` prefix and special-cases `/Volumes`, `/.nofollow`, `/private/var/vm` and `/home`.

### Behavior

During any traversal:

- Never descend into `/System/Volumes/Data`, `/Volumes`, `/.nofollow`, `/private/var/vm` or `/home`.
- Before inserting into the visited set, rewrite paths starting `/System/Volumes/Data/` to start with `/`.

Today's scan roots don't overlap these paths. This guard prevents double counting if a root-level scan or an external-volume scan is added later.

### Implementation

Add a `SystemPathGuard` with `shouldSkip(_ path: String) -> Bool` and `canonical(_ path: String) -> String`, and call it in the scanner. Skipped paths are silent; they are not added to `skippedPaths`.

---

## F7. Purgeable Space and Local Time Machine Snapshots

### Observed in CleanMyMac

The Performance module's "Free Up Purgeable Space" and "Thin Time Machine Snapshot" both run `/usr/bin/tmutil thinlocalsnapshots <volume> <bytes> <urgency>`. One call site uses 1 GiB and urgency 3. Space Lens shows a "Purgeable Space" figure.

### Behavior

Dashboard gains a read-only "System-managed space" card:

- **Purgeable:** `volumeAvailableCapacityForImportantUsage - volumeAvailableCapacity`, clamped at 0. Copy: "macOS can reclaim this automatically when space runs low."
- **Local snapshots:** the count and date range from `tmutil listlocalsnapshots /`. CleanScope does not show a snapshot size, because `tmutil` does not report one reliably.
- The existing "available" figure already uses the important-usage capacity, which includes purgeable space. Add a footnote: "Includes X that macOS can reclaim."

Optional action, off by default behind a setting: "Ask macOS to thin local snapshots…"

- A confirmation explains that local snapshots are removed but backups on the Time Machine disk are not affected.
- Runs `tmutil thinlocalsnapshots / <requested bytes> 1`. The user picks the requested size (default 10 GB); urgency is the lowest level **(design choice)**.
- **Verify during implementation** that this works without admin rights on macOS 13, 14 and 15. If it needs admin rights, drop the action and keep the read-only card.

### Implementation

- `SystemSpaceService` in Core:
  - `purgeableBytes(volume: URL) -> Int64`
  - `localSnapshots() async -> [Date]`
  - `thin(requestedBytes:) async throws`
- Run `tmutil` through `Process` with a 30-second timeout. Parse lines matching `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local`.
- Inject the process runner so tests can feed canned `tmutil` output.

### Tests

- Parsing canned output with zero, one and several snapshots.
- Purgeable is clamped at 0 when the API returns inconsistent values.

---

## F8. Storage Map

### Observed in CleanMyMac

Space Lens builds a size tree, groups small entries into "Other items", and draws a circle-packing bubble map. It has hover tooltips (size, modified date, selected size) and a review-before-remove list.

### Behavior

- New sidebar destination "Storage Map", placed after Dashboard.
- Shows the latest scan as a squarified treemap **(design choice)**. Rectangles compare sizes more accurately than bubbles and suit a native macOS app.
- Click a folder to drill in; a breadcrumb bar goes back up. A Back keyboard shortcut moves up one level.
- Each tile shows its name and size when it is large enough. Hovering shows size, modified date, safety label and selected size.
- Tiles are tinted by safety category and carry a small text label or symbol, so color is never the only signal (Product: "Never communicate safety category through color alone").
- Children smaller than 1% of the parent's size are merged into one "Other items" tile.
- Selecting a tile uses `AppModel.setSelection`, so the same eligibility rules apply. Removal still goes through the existing review sheet.
- Respects Reduce Motion: no zoom animation when it is on.

### Data model

- Add `ScanNode` in Core: `path`, `name`, `sizeBytes`, `itemType`, `children: [ScanNode]`, and `resultId: String?` linking to a `ScanResult` when one exists.
- The scanner builds the tree during F4's work items:
  - Keep folders up to 6 levels below each root **(design choice)**.
  - Keep files at or above 1% of their parent or the large-file threshold.
  - Aggregate everything else into an `otherBytes` value per node.
- Store the tree in memory on `ScanSession` as a non-persisted property, rebuilt by the next scan. If the app relaunches without a tree, show "Run a scan to see the map."

### Layout

- `TreemapLayout.squarify(items: [(id: String, size: Int64)], in rect: CGRect) -> [(id: String, rect: CGRect)]` in Core, as a pure function.
- Render with SwiftUI `Canvas` for tiles plus an overlay for hit-testing and accessibility elements.

### Accessibility

Each tile is an accessibility element labeled "Name, size, safety label". VoiceOver users can also switch to the existing list view of the same folder.

### Tests

- `squarify` preserves total area within 0.5% and never produces negative or overlapping rects.
- "Other items" aggregation sums correctly.

---

## F9. Alert Snooze Store

### Observed in CleanMyMac

`IssueIgnoreList.db` stores `(issueReportKind, issueDescriminator, ignoredTime, ignoreInterval)`. The UI options are: until tomorrow, a day, 3 days, a week, forever.

### Design

- `AlertKind`: `lowDiskSpace`, `trashSize`, `externalDriveLow`.
- `AlertIgnoreRecord`: `kind`, `discriminator` (a volume UUID or `"home"`), `ignoredAt`, and `interval: TimeInterval?` (nil means forever).
- `AlertIgnoreStore` saves JSON in `UserDefaults` under `CleanScope.alertIgnores`, following the `SettingsStore` pattern.
- Snooze options and how each resolves:

| Option | Resolves to |
|---|---|
| Until tomorrow | Next local midnight |
| For a day | 24 hours |
| For 3 days | 72 hours |
| For a week | 7 days |
| Forever | No expiry |

- Settings gets a "Reset snoozed alerts" button.

### Tests

Expiry math at day boundaries and across a DST change. "Forever" never expires.

---

## F10. Menu Bar Status

### Observed in CleanMyMac

A separate login-item app shows the menu and talks to another helper app that does the monitoring. CleanScope does not need two extra processes.

### Behavior

- Optional and off by default: Settings has "Show CleanScope in the menu bar".
- Uses SwiftUI `MenuBarExtra` (macOS 13+) inside the main app. When enabled, closing the main window keeps the app running.
- The menu shows:
  - Free space on the startup disk with a small bar
  - Trash size
  - "Last scan: date, potential cleanup X"
  - Buttons: Open CleanScope, Start Limited Scan, Settings…
- Settings also has "Open at login" through `SMAppService.mainApp.register()` / `unregister()`.

### Implementation

- `CleanScopeApp`: add a `MenuBarExtra` scene gated on a new setting, `showMenuBarExtra: Bool`. Give it a decode default of `false` so saved settings still load.
- Add an `AppDelegate` with `applicationShouldTerminateAfterLastWindowClosed` returning `false` when the menu bar extra is on.
- A `StatusMonitor` (MainActor `ObservableObject`) refreshes free space and Trash size:
  - every 5 minutes while the menu bar extra is visible
  - every 30 minutes otherwise **(design choice)**
  - immediately on `NSWorkspace.didMountNotification` and `didUnmountNotification`

---

## F11. Low Disk Space Alert

### Observed in CleanMyMac

`LowDiskSpaceIssueProducer`, with copy "You are running out of disk space!" and "Available: X".

### Behavior

- Trigger when startup-disk important-usage capacity is below `max(10 GB, 5% of total)` **(design choice)**.
- Clear when it rises 2 GB above the trigger, so the alert doesn't flicker.
- A macOS notification (`UNUserNotificationCenter`), calm in tone:
  - Title: "Your Mac is getting full"
  - Body: "X available. A scan can show what's using space."
  - Actions: "Scan now", "Snooze…"
- Fires at most once per crossing, and never while snoozed (F9).
- Settings: enable toggle (default on once notifications are allowed) and a threshold picker (5, 10, 20, 50 GB).

### Implementation

- `AlertEvaluator` in Core is a pure function: `evaluate(snapshot: DiskSnapshot, trashBytes: Int64, externalVolumes: [VolumeStatus], ignores: [AlertIgnoreRecord], now: Date, previous: AlertState) -> (alerts: [AlertKind: AlertPayload], next: AlertState)`.
- `StatusMonitor` calls it and posts notifications. Request notification authorization only when the user first enables an alert, never at launch.

### Tests

Threshold crossing, hysteresis, snooze suppression, and no repeat while the condition holds.

---

## F12. Trash Size Alert

### Observed in CleanMyMac

`TrashSizeIssueProducer` watches `~/.Trash/`, with copy "Your Trash Bin accumulated quite a lot of deleted files."

### Why it matters more for CleanScope

CleanScope moves cleanups to Trash, so the space isn't actually recovered until the Trash is emptied.

### Behavior

- Trigger when `~/.Trash` is larger than 5 GB **(design choice)**; the threshold is configurable.
- Notification: "Trash is holding X. Space is freed when the Trash is emptied." Actions: "Open Trash", "Snooze…".
- "Open Trash" opens `~/.Trash` in Finder.
- "Empty Trash…" (CleanMyMac's `HealthRecommendation_EmptyTrash_Action`) asks Finder through Apple Events: `tell application "Finder" to empty trash`.
  - The first use triggers the macOS Automation permission prompt. Add `NSAppleEventsUsageDescription` to the generated `Info.plist` in `script/build_and_run.sh`.
  - Show CleanScope's own confirmation first: "Permanently erase X in the Trash? This can't be undone."
- After a cleanup, the cleanup report adds one line: "X moved to Trash. Empty the Trash in Finder to free the space."

### Implementation

- Measure Trash size with a lightweight enumerator, summing `totalFileAllocatedSize`.
- If reading `~/.Trash` fails with a permission error, turn the Trash alert off, and have Settings say "Needs Full Disk Access".

---

## F13. External Drive Nearly Full Alert

### Observed in CleanMyMac

`ExternalsVolumesIssueProducer`, with copy "Connected disk is almost full" and an offer to scan it. It also shows a "connected" notification on mount.

### Behavior

- On mount, and on each status refresh, check removable and external volumes.
- Trigger when free space is under 10% of capacity **(design choice)**.
- Notification: "<Drive> is almost full. X available." Actions: "Scan drive", "Snooze…". The snooze is keyed by the volume UUID.
- "Scan drive" runs a scan with the volume root as the only path. It uses the same classifier, plus one extra rule: `/.Trashes/<uid>` on that volume is classified like `safe.trash`.
- Optional "<Drive> connected" notification with a "Show in CleanScope" action, off by default (CleanMyMac: `ExternalDrives_Notification_Mounted_*`).

### Implementation

- `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeUUIDStringKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeLocalizedNameKey], options: [.skipHiddenVolumes])`.
- Network volumes are excluded.
- `AppModel.startScan` gains an entry point that accepts explicit paths for the drive scan.

---

## F14. Leftovers of Apps in Trash (later)

### Observed in CleanMyMac

A `TrashedAppsMonitor` detects apps moved to Trash and offers to remove their leftovers. The Uninstaller module itself was not reverse-engineered, so the search locations below are **our design**, not CleanMyMac's rules.

### Behavior

- When a `.app` bundle appears in `~/.Trash`, read its `CFBundleIdentifier` and `CFBundleName`.
- If no other copy of that app is installed (`NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil), look for exact matches in:
  - `~/Library/Application Support/<bundle id>` and `/<app name>`
  - `~/Library/Caches/<bundle id>`
  - `~/Library/Containers/<bundle id>`
  - `~/Library/Preferences/<bundle id>.plist`
  - `~/Library/Saved Application State/<bundle id>.savedState`
  - `~/Library/Logs/<app name>`
  - `~/Library/HTTPStorages/<bundle id>`
  - `~/Library/WebKit/<bundle id>`
- Show a "Leftovers from apps in Trash" result group. Items are `probablyUnused`, medium confidence, and require review.
- Match only exact names. No fuzzy matching and no Group Containers in this version.
- Never touch anything that `protect.*` rules cover.

### Tests

Fixture home folder with a fake trashed app: exact matches are found, similarly named folders are not, and protected paths are excluded.

---

## F15. Maintenance Tasks

### Observed in CleanMyMac

`PerformanceService` has one runner per task. The App Store build ships no privileged helper, so the admin-only tasks fail there with "you didn't authorize this operation".

### Behavior

A new "Maintenance" destination lists the tasks below. Each row has a description, the last-run date and a Run button. "Run recommended" runs the tasks marked as recommended. None run automatically.

| Task | Command or method | Admin | Notes |
|---|---|---|---|
| Free up purgeable space | `tmutil thinlocalsnapshots / <bytes> <urgency>` (see F7) | (verify) | CleanMyMac uses 1 GiB, urgency 3 |
| Thin Time Machine snapshots | Same as above, with a larger requested size | (verify) | Backups on the backup disk are unaffected |
| Flush DNS cache | `dscacheutil -flushcache; killall -HUP mDNSResponder` | Yes | |
| Reindex Spotlight | `mdutil -E /`, then poll `mdutil -s /` for status | Yes | Copy warns that search is slow while reindexing |
| Run periodic scripts | `periodic daily weekly monthly` | Yes | (verify) that `/usr/sbin/periodic` still ships on macOS 15 |
| Repair home folder permissions | `diskutil resetUserPermissions / <uid>` | Yes | Modern equivalent of "Repair Disk Permissions". Resets home permissions to defaults; copy says so |
| Speed up Mail | Quit Mail, run SQLite `VACUUM` on `~/Library/Mail/V*/MailData/Envelope Index`, then `mdimport ~/Library/Mail` | No | Needs Full Disk Access. CleanMyMac also runs `mdimport` |

### Implementation

- `MaintenanceTask` protocol in Core: `id`, `title`, `description`, `requiresAdmin`, and `run(context:) async throws -> MaintenanceOutcome`.
- `PrivilegedRunner` wraps the `NSAppleScript` admin prompt (see Privilege Model) and returns the exit status and output. Inject it so tests can stub it.
- Speed up Mail:
  - Use the system `SQLite3` module, not a shell `sqlite3`.
  - Refuse to run if Mail is still running after a 10-second quit request.
  - Copy the database to a temporary file before `VACUUM`, and restore it if `VACUUM` fails.
- Each run records a `MaintenanceRun` (task id, date, outcome) in `UserDefaults` for the "last run" label.

### Tests

- Command strings for every admin task match a golden list; no string interpolation of unvalidated input.
- The Mail task stops when Mail is still running, and restores the backup on a simulated `VACUUM` failure.

---

## F16. Login Items and Background Items

### Observed in CleanMyMac

- `LaunchAgentsScanTask` and `LaunchServicesLoginItemsScanTask`, each checked against a "valid items" knowledge base.
- Removal falls back to the privileged agent when the client can't remove an item.
- UI copy: "Manage the list of processes and applications that run in the background."

### Behavior

Two new lists, Login Items and Background Items. Each row shows:

- the owning app's icon and name, and the signer (Team ID)
- status: running, loaded or disabled
- a "Broken" badge when the program it points to no longer exists

Actions: Disable, Remove (moves the plist to Trash), Reveal in Finder.

### Sources

| Source | How to read | How to change |
|---|---|---|
| `~/Library/LaunchAgents/*.plist` | `PropertyListSerialization`: `Label`, `Program` or `ProgramArguments[0]`, `RunAtLoad`, `KeepAlive`, `Disabled` | `launchctl bootout gui/<uid> <plist>`, then move to Trash. No admin needed |
| `/Library/LaunchAgents`, `/Library/LaunchDaemons` | Same parsing | `launchctl bootout system <plist>` plus a move, with admin |
| Legacy login items | System Events: `get the name of every login item` (Automation permission) | `delete login item "<name>"` |
| Modern login items (`SMAppService`) | Not readable through public API. Best effort: `sfltool dumpbtm` with admin (verify the output format) | Open System Settings → Login Items: `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` |

### Ownership

- Resolve each program path to its enclosing `.app`.
- Read the Team ID with `SecStaticCodeCreateWithPath` and `SecCodeCopySigningInformation`.
- Items whose label starts `com.apple.` or that are Apple-signed are hidden.

### Tests

- Plist parsing for both `Program` and `ProgramArguments` forms.
- Broken detection when the program is missing.
- Apple items are filtered out.

---

## F17. Memory Relief

### Observed in CleanMyMac

`CMRAMCleaner` reads total physical RAM, then allocates it in 256 MB blocks filled with random bytes so the memory can't be compressed. That forces macOS to evict caches and compress or swap other apps. After each block it re-reads `host_statistics64`, stops when a threshold trips twice or the user cancels, and then frees everything.

The menu bar alert is "Heavy memory usage" with "RAM + Swap" load and Free Up / Optimize actions. The reported "free" number rises, but the cost is swap writes and slower app switching afterward.

### Behavior

Build two parts:

1. **Memory view (default).**
   - Show memory pressure (`kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical) and swap used (`vm.swapusage`).
   - Show a breakdown from `host_statistics64(HOST_VM_INFO64)`: app memory, wired, compressed, cached files.
   - List the top 10 apps by memory footprint (`proc_pid_rusage` `RUSAGE_INFO_V4`, field `ri_phys_footprint`, which matches Activity Monitor's "Memory" column). Each row has a Quit button using `NSRunningApplication.terminate()`.
   - Heavy-usage alert: when pressure stays at 2 or higher for 2 minutes **(design choice)**, through F9 and F11's notification path (new `AlertKind.memoryPressure`).
2. **"Free up memory" action.**
   - Default implementation: `purge` with admin. This flushes the file cache, which is what users expect, without hogging RAM.
   - Fallback without admin: CleanMyMac's block allocator, with safety limits:
     - Never allocate more than `free + inactive − 1 GB`.
     - Stop as soon as pressure reaches 2.
     - Run off the main thread and allow cancelling.
     - Free all blocks in a `defer`.
   - Show the before and after footprint honestly. Don't claim a speed-up.

### Implementation

- `MemoryService` in Core: `snapshot() -> MemorySnapshot` and `topConsumers(limit:) -> [ProcessMemory]`.
- `MemoryReclaimer`:
  - `reclaimWithPurge()`
  - `reclaimWithAllocation(limitBytes:cancel:)`
- Processes owned by other users return errors from `proc_pid_rusage`; skip them silently.

### Tests

The allocation limit math, and cancelling stops the loop within one block.

---

## F18. System Monitors

### Observed in CleanMyMac

The HealthMonitor helper app contains these monitors:

- `SystemResourcesMonitor`: CPU via `host_processor_info`, memory, and temperature through the `AppleSMC` service with keys such as `TC0P` and `Tp0x`
- `BatteryMonitor`: power-source APIs; cycle count against `DesignCycleCount9C`; health fraction; temperature
- `NetworkMonitor`: SystemConfiguration, CoreWLAN and Reachability. Wi-Fi details use the location permission

### Behavior

The menu bar extra (F10) gains optional sections for CPU, Memory, Battery, Network and Disk. Each section shows a current value and a 60-second sparkline. Values refresh every 2 seconds while the menu is open, and sampling stops when it closes.

| Metric | Source | Notes |
|---|---|---|
| CPU load | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, difference between samples | Per core and total |
| Memory | F17 `MemoryService` | |
| Battery % and time | `IOPSCopyPowerSourcesInfo` | |
| Battery health | IORegistry `AppleSmartBattery`: `CycleCount`, `DesignCycleCount9C`, `AppleRawMaxCapacity` / `DesignCapacity`, `Temperature` | (verify) key names on Apple Silicon. Show "Critical battery health" below 70% **(design choice)** |
| Network throughput | `getifaddrs`, `AF_LINK` `if_data.ifi_ibytes` / `ifi_obytes` differences | Wi-Fi network name needs the location permission on macOS 14+. Skip the name unless the user grants it |
| CPU temperature | `AppleSMC` user client with chip-specific keys | (verify) Fragile: keys differ by chip and macOS release. Behind an "Experimental" toggle |

### Implementation

- `SystemMetricsService` actor in Core, with one sampler per metric. Each sampler returns `nil` when the data isn't available, so the UI hides that row.
- SMC access is isolated in `SMCReader`, so it can be removed if it breaks.

---

## F19. Hung App Detection

### Observed in CleanMyMac

The "Non-responsive applications" alert offers Force Quit, Force Quit All, Wait, and Ignore. The detection method was not recovered.

### Behavior

- When an app has been unresponsive for 10 seconds **(design choice)**, show a notification. Actions: Force Quit, Wait.
- The menu bar extra lists unresponsive apps with Force Quit.

### Implementation

- Detection: for each regular-activation app in `NSWorkspace.shared.runningApplications`:
  - Create `AXUIElementCreateApplication(pid)`.
  - Set `AXUIElementSetMessagingTimeout` to 1 second.
  - Read `kAXRoleAttribute`.
  - Two `kAXErrorCannotComplete` results in a row mark the app hung.
- Needs the Accessibility permission. Ask only when the user turns the feature on.
- Poll every 5 seconds, and only while monitoring is on.
- Force Quit: `NSRunningApplication.forceTerminate()`.

---

## F20. Mac Status Summary

### Observed in CleanMyMac

A "health score" whose own text says it is based on disk space, potential threats, battery condition, average load "and many more".

### Behavior

- A Dashboard card with five named checks: Disk space, Trash, Protection, Battery, Memory.
- Each check shows "Good" or "Needs attention", a reason in words, and a button to the relevant screen.
- An optional overall score (0–100) is a weighted sum with a visible breakdown, so the user can see why it's lower. No dial or gauge graphic; a number and a list.

### Implementation

- `StatusSummary` in Core is a pure function over the latest disk snapshot, Trash size, malware results, battery health and memory pressure.
- Weights are a constant table **(design choice)**: disk 35, protection 25, Trash 10, battery 15, memory 15.

---

## F21. Restart Reminder

### Observed in CleanMyMac

"It's been %@ since your last restart."

### Behavior

- When uptime passes 14 days **(design choice)**, show a gentle notification.
- New `AlertKind.restart`, snoozable through F9.
- Uptime comes from `sysctl` `kern.boottime`.

---

## F22. Bluetooth Device Battery

### Observed in CleanMyMac

"Time to juice up!" alerts, with default device names for headphones, keyboard, mouse and trackpad.

### Behavior

- When a connected device's battery drops below 15% **(design choice)**, show a notification.
- New `AlertKind.bluetoothBattery`, keyed by device.

### Implementation

- Find IORegistry entries with a `BatteryPercent` property using `IOServiceMatching`, and read the `Product` name.
- (verify) AirPods and some headphones may not expose `BatteryPercent` this way.

---

## F23. Malware Scanning

### Observed in CleanMyMac

The Moonlock engine. Its rule database is downloaded and encrypted. Rule types:

- path
- file hash plus size
- Team ID (detect or ignore)
- launch agent
- Safari extension and Safari homepage
- Chrome extension
- configuration profile
- YARA (with file-type rules and dependencies)

Scan sources: system paths, user drive, external drives, running processes, launch agents, cron jobs, browser extensions, profiles and Mail attachments. DMG, PKG and archive contents are scanned within depth and size limits. Threat categories include adware, trojan, stealer, dropper, botnet, exploit, worm, riskware and installer.

### Rule sources

CleanScope cannot use Moonlock's database. Use these sources:

1. **CleanScope rules (F30):** JSON with path, hash, Team ID, launch-agent, extension and profile rules. Curated by you.
2. **YARA rules:** CleanScope-maintained `.yar` files shipped with F30 updates.
3. **Apple XProtect's YARA file, read locally at scan time:** (verify) `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.yara`. Read it in place; don't redistribute it.

### Engine

- **Hash rules:** CryptoKit SHA-256, streamed, with a size pre-check first so most files skip hashing.
- **YARA:** vendor libyara (BSD-3-Clause) as a C target in `Package.swift`. Compile rules once per scan.
- **Team ID rules:** `SecStaticCode` signing info. A user-editable trusted-Team-ID list suppresses matches.
- **Containers:**
  - Mount DMGs read-only with `hdiutil attach -nobrowse -readonly`.
  - Expand PKGs with `pkgutil --expand` into a temporary folder.
  - Read ZIPs with `/usr/bin/ditto -x -k`.
  - Limits: nesting depth 3, archive size 500 MB, YARA file size 100 MB **(design choice)**.

### Scan targets

| Target | How it's read |
|---|---|
| Applications | `/Applications` and `~/Applications` |
| Downloads | `~/Downloads` |
| Launch agents and daemons | Shares the F16 parser |
| Running processes | `proc_listpids` and `proc_pidpath` |
| Cron | `crontab -l` |
| Safari extensions | `pluginkit -mAvvv -p com.apple.Safari.web-extension` (verify the output) |
| Chrome and Chromium extensions | `~/Library/Application Support/<browser>/*/Extensions/<id>/<version>/manifest.json` |
| Configuration profiles | `profiles list` (verify user-level output without admin) |
| Mail attachments | `~/Library/Mail/V*/*/Attachments` (Full Disk Access) |

### Removal

Pre-removal steps, in order:

1. Terminate processes whose executable is inside the item.
2. Boot out the related launch agent.
3. Detach any mounted DMG.

Then:

- **Files:** move to Trash by default. With F27 enabled, offer "Delete permanently". CleanMyMac deletes threats permanently.
- **Profiles:** open System Settings → Device Management. Profiles can't be removed silently.
- **Browser extensions:** open the browser's extensions page.

### UI

- A "Protection" destination with Scan, last-scan date, threats found (name, category, location, detected by which rule) and actions.
- Category descriptions use plain language, without fear wording.

### Caveat for the copy

Detection quality depends entirely on the rule set. The UI must not claim complete protection.

---

## F24. Real-Time Monitoring

### Observed in CleanMyMac

FSEvents streams and per-folder vnode watchers, with Downloads explicitly watched. Also watched: launch agents, Chromium extensions, app launch and drive mount events, and Mail attachments on a schedule. Processes are polled with `proc_listpids`. It does not use Endpoint Security.

### Behavior

- Opt-in, and runs only while the app is alive (menu bar mode, F10).
- New or changed files are scanned with F23's engine.
- A detection posts a notification with Remove and Ignore actions.

### Implementation

- One `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`. Paths:
  - `~/Downloads`
  - `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`
  - Chrome and Chromium `Extensions` folders
- Latency 2 seconds; events for the same path within 10 seconds are merged.
- `NSWorkspace.didLaunchApplicationNotification`: scan the launched app bundle once per version (cache by path and modification date).
- `didMountNotification`: scan only the top level of the new volume.
- Endpoint Security could block threats before they run, but it needs an Apple-granted entitlement (`com.apple.developer.endpoint-security.client`). Leave it as a future option.

---

## F25. System and Diagnostic Logs

### Observed in CleanMyMac

Rotated logs `system.log.N.gz`, `wifi.log.N.bz2`, plus `install.log`, `fsck_hfs.log`, `fsck_apfs.log`, and container `Data/Library/Logs`.

### Behavior

- Full scan adds these roots:
  - `/private/var/log`
  - `/Library/Logs`
  - `~/Library/Logs/DiagnosticReports`
  - `/Library/Logs/DiagnosticReports`
- New rules:
  - `safe.rotated-logs`: names matching `*.N.gz` or `*.N.bz2` under `/private/var/log`.
  - `safe.diagnostic-reports`: files under `DiagnosticReports`.
  - Live logs (`system.log`, `install.log`) are `probablyUnused` with low confidence, because a process may be writing to them.
- Root-owned items need admin rights to remove.
  - Use `/usr/bin/trash` through the admin runner where it exists. (verify) That it ships with macOS 15.
  - Otherwise, items are labeled "Removed permanently (needs administrator)" and are only removable with F27 on.

---

## F26. App Store Download Cache

### Observed in CleanMyMac

`CMAppStoreDownloadsCacheScanTask` exists. Its path was not recovered.

### Behavior

- (verify) Locate it by checking `$(getconf DARWIN_USER_CACHE_DIR)com.apple.appstore`, and partial downloads under `/Library/Application Support/App Store`.
- Add a `safe.appstore-downloads` rule once the paths are confirmed.
- Low priority.

---

## F27. Permanent Delete Option

### Observed in CleanMyMac

Junk cleanup (configurable), Space Lens, malware removal and the drive cleaner all delete permanently.

### Behavior

- Setting "When cleaning up": **Move to Trash** (default) or **Delete immediately**.
- With Delete immediately:
  - The review sheet button reads "Delete Permanently".
  - A second confirmation states the item count and size, and that this can't be undone.
- Items whose method is `.manualReview` or `.notAllowed` are never deleted, whatever the setting.

### Implementation

- `DeletionMethod.permanent` and `Settings.defaultDeletionMethod` already exist.
- `DeletionService` gains a `FileRemover` for `.permanent` that uses `FileManager.removeItem`.
- `classify` keeps producing `.trash`. `AppModel` maps `.trash` to `.permanent` at cleanup time when the setting is on, so saved sessions don't change.
- Report messages say "Deleted permanently".

### Tests

- With the setting off, `.permanent` is never used.
- With it on, `.manualReview` and `.notAllowed` items are still skipped or blocked.

---

## F28. Preselect Safe Caches

### Observed in CleanMyMac

`CMCacheScanTask.isResultAutoselectable` returns `true`, so every cache found is pre-selected.

### Behavior

- Setting "Preselect Ready to Delete caches after a scan", off by default.
- When on, after a scan completes, select every result that passes the existing Ready to Delete predicate: `safeToDelete`, high confidence, `canDelete`, not excluded, and a cache path.
- Cleanup still goes through the review sheet.

### Implementation

In `AppModel.startScan`, after `session = completed`, call `setSelection(true, for:)` with the filtered results when the setting is on.

---

## F29. External Drive Cleaner

### Observed in CleanMyMac

`CleanMyDriveScanner` in the menu app walks a drive with `fts` and deletes with `removefile()`. Its targets were not recovered.

### Behavior

Extends F13's "Scan drive":

| Item | Classification |
|---|---|
| `/.Trashes/<uid>` | `safe.trash` |
| `._*` AppleDouble files on exFAT, FAT and NTFS volumes (`volumeLocalizedFormatDescription`) | `safeToDelete` |
| `.DS_Store` | `safeToDelete`, grouped into one result |
| `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100`, `.TemporaryItems` | `doNotBulkDelete`; system-managed |

---

## F30. Updatable Rule Set

### Observed in CleanMyMac

An encrypted SQLite rules archive is downloaded from `https://public-apis.moonlock.com/engine/v3/database`, with versioning and a "no update needed" check. A separate encrypted `info.cmmkb` knowledge base ships in the app.

### Behavior

- Classification rules (F0–F3, F25, F26) and malware rules (F23) can update without an app release.
- The update check runs at most once a day while the app is open, and is silent when nothing changed. Settings shows the rule version and date.

### Implementation

- A manifest JSON at a URL you control: `{ "version": Int, "minAppVersion": String, "rules": URL, "malware": URL, "signature": base64 }`.
- Sign with Ed25519 (CryptoKit `Curve25519.Signing`). The app embeds the public key and rejects unsigned or downgraded manifests.
- Downloaded rules are stored in Application Support. Bundled rules remain the fallback.
- Validation before activation:
  - Downloaded rules may not change, remove or override any `protect.*` rule.
  - The F0 invariant test logic runs at load time, and the set is rejected on failure.

---

## F31. Privacy Cleanup

### Observed in CleanMyMac

`SystemJunkScanning` references `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2`. The `PrivacyScanning` and `PrivacyService` frameworks exist but were not analyzed (see section 9).

### Behavior

- Starts with one item: "Download history" from the QuarantineEvents database. It records every file downloaded through a quarantine-aware app.
- Shows the entry count and a "Clear download history" action.

### Implementation

- SQLite `DELETE FROM LSQuarantineEvent;` on the `QuarantineEventsV2` database, then `VACUUM`.
- Confirm first; this can't be undone.
- Leave the files' own quarantine flags alone. Those protect Gatekeeper checks.

---

## 9. Not Yet Reverse-Engineered

These CleanMyMac modules exist in the 5.7.1 bundle but were not analyzed. Each needs an REA pass before it can be specified.

| Module | Frameworks seen | Hints from strings |
|---|---|---|
| Uninstaller | `UninstallerScanning`, `ApplicationsModule`, `ApplicationsTerminator`, `ApplicationSelfRemoverService` | Leftover detection; overlaps F14 |
| Updater | `UpdaterScanning`, `AppInfoNetworkService`, `MASUpdaterServiceAPI` | "%@ ready to be updated" |
| Cloud Cleanup | `CloudStorageModule`, `CloudStorageScanning`, `DropboxService`, `GoogleDriveService`, `MicrosoftService` | "This item is cloud-only. Manage it in Cloud Cleanup Module." |
| Email Cleanup | `EmailCleanupModule`, `GmailService`, `MailboxService`, `MailJunkScanning` | Gmail and Outlook sign-in through OAuth |
| Unused disk images | `UnusedDiskImagesScanning` | Old `.dmg` and `.iso` files |
| Privacy | `PrivacyScanning`, `PrivacyService` | Expands F31 |
| Smart Care | `SmartCareModule` | One-click combined scan |
| Assistant | `AssistantCore`, `AssistantUI`, `TipsServiceAI` | AI-generated tips |
| My Clutter | `OrganizeModule`, `OrganizeScanning`, `LocalModelScanning`, `DownloadsScanning` | "Look through your clutter"; likely duplicates and similar files |
| AI tool caches | `AIToolScanning` | Likely caches from local AI tools |

---

## Cross-Cutting Changes

### Model and storage compatibility

- New fields need decode defaults so existing saved sessions and settings still load:
  - `ScanResult`: `isCloudOnly`
  - `Settings`: `showMenuBarExtra`, alert toggles and thresholds, `allowSnapshotThinning`, `preselectSafeCaches`, monitoring and protection toggles
  - `ScanSummary`: `cloudOnlyBytes`
- Add `ScanRepositoryTests` and `StoreTests` cases that decode the old JSON.
- `AlertKind` grows across features: `lowDiskSpace`, `trashSize`, `externalDriveLow`, `memoryPressure`, `restart`, `bluetoothBattery`, `hungApp`, `malwareDetected`.

### Permissions and Info.plist

`script/build_and_run.sh` writes `Info.plist`. Add usage strings as features land:

- `NSAppleEventsUsageDescription`: Finder empty Trash, System Events login items, admin prompts
- `NSLocationWhenInUseUsageDescription`: Wi-Fi network name (F18)

Accessibility (F19) and Full Disk Access (F15 Mail, F23 Mail attachments) have no `Info.plist` key. The existing permission banner gains matching setup steps.

### Navigation

New destinations: Storage Map, Maintenance, Login Items, Background Items, Memory, Protection. Group the sidebar into sections (Storage, Performance, Protection, History) so the list stays scannable.

### Copy

Follow the existing tone checks in `VERIFY.md`: no alarms, gauges or fear language, including in Protection and Memory. Alerts state the fact and the next step.

### Verification additions for `VERIFY.md`

- A Developer scan lists container caches and Chromium caches as Safe to delete. IndexedDB and Local Storage are never listed as safe.
- Cloud-only files show the cloud badge, count 0 bytes, and can't be selected.
- The Storage Map drill-down and the selection made from it match the list view.
- The menu bar extra is off by default. Enabling it keeps the app alive after the window closes.
- The low-disk and Trash alerts respect snooze and don't repeat.

## Open Questions

1. F7 and F15: does `tmutil thinlocalsnapshots` run without admin rights on macOS 13, 14 and 15? If not, route it through the admin runner.
2. F8: should the Storage Map tree persist across relaunches? Default answer: no, to keep saved sessions small.
3. F15: does `periodic` still ship on macOS 15? F25: does `/usr/bin/trash` exist on every supported version?
4. F18: which battery and SMC keys are reliable on Apple Silicon? Test on at least one M-series and one Intel Mac before enabling.
5. F23: is reading Apple's local XProtect YARA file at scan time acceptable for distribution? Is its path stable across macOS updates?
6. F24: is it worth applying for the Endpoint Security entitlement to block threats before they run?
7. F30: where will the signed rule manifest be hosted, and who signs releases?
8. Section 9: which unanalyzed module should get the next REA pass? Uninstaller is suggested, because it completes F14.
