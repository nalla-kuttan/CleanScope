# CleanMyMac Gap Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the storage, performance, monitoring and protection features from the gap spec (F0–F31) to CleanScope while keeping every default safe.

**Architecture:** Pure, testable logic goes in `CleanScopeCore` (rules, scanner, tree/layout, alert evaluation, parsers, command builders, rule engines). Anything that touches system processes is behind an injectable runner (`ProcessRunner`, `PrivilegedRunner`) so tests feed canned output. SwiftUI destinations in `CleanScopeApp` consume Core services through `AppModel` and a new `StatusMonitor`.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftUI, AppKit, Foundation, CryptoKit, IOKit, Security, SQLite3, ServiceManagement, UserNotifications, CoreServices (FSEvents), Swift Testing, SwiftPM, macOS 13+.

**Spec:** `docs/superpowers/specs/2026-10-20-cleanmymac-gap-features-design.md`

## Global Constraints

- Platform floor stays macOS 13 (`Package.swift` `.macOS(.v13)`).
- Cleanup default stays Move to Trash; nothing is preselected unless `preselectSafeCaches` is on.
- `.manualReview` and `.notAllowed` items are never removed, whatever the deletion setting.
- Every new persisted field decodes with a default so old `latest-scan.json` and `CleanScope.settings` still load.
- Privileged commands are fixed strings; user paths only enter through `ShellQuote.quote(_:)`.
- No rule may list a `protect.*` id in `overrides`; downloaded rule sets that try are rejected.
- Copy: no alarms, gauges or fear language. Alerts state the fact and the next step. Never claim complete protection.
- Safety category is never conveyed by color alone (tiles and rows carry a label or symbol).
- Notification authorization is requested only when the user first enables an alert.
- Run tests with `./script/swiftpm.sh test`; build with `./script/swiftpm.sh build`.

## Verified Environment Facts (resolve spec "(verify)" items)

Checked on macOS 27.0 (Apple Silicon) on 2026-10-20:

- `/usr/sbin/periodic` is absent → the "Run periodic scripts" task is shown only when the binary exists.
- `/usr/bin/trash` exists (`trash [-v] file…`) → used for admin Trash moves of root-owned items.
- `~/Library/Containers` mixes bundle-id names and UUID names; the bundle id is `MCMMetadataIdentifier` in `<container>/.com.apple.containermanagerd.metadata.plist`.
- `AppleSmartBattery` has `CycleCount`, `DesignCycleCount9C`, `DesignCapacity`, `NominalChargeCapacity`; `AppleRawMaxCapacity` is absent → health = (`AppleRawMaxCapacity` ?? `NominalChargeCapacity`) / `DesignCapacity`.
- `XProtect.yara` exists at the spec path. No `yara` binary is installed and libyara is not vendored (see Deviations).
- `tmutil listlocalsnapshots /` prints `com.apple.os.update-…` lines that are not Time Machine snapshots; the parser only accepts `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local`.
- App Store caches live at `$(getconf DARWIN_USER_CACHE_DIR)com.apple.appstoreagent` and `…com.apple.appstorecomponentsd`, already inside `/private/var/folders` (covered by `safe.known-caches`).

## Deviations From the Spec

- **F23 YARA:** vendoring libyara requires downloading third-party source. Instead `YaraScanner` is a protocol; the shipped implementation runs an external `yara` binary when one is found (`/opt/homebrew/bin/yara`, `/usr/local/bin/yara`) and reports "YARA rules unavailable" otherwise. Vendoring libyara is a follow-up.
- **F30:** the manifest URL and signing key are unknown (Open Question 7). The updater ships with `RuleUpdateConfiguration.manifestURL = nil` (disabled) and a `script/sign_rules.swift` helper; enabling it is a config change.
- **F3 regional set, Section 9 modules:** out of scope, as the spec says.

## Review Focus

1. **Chromium cache folder nested inside user-state folders** (e.g. `…/Service Worker/CacheStorage/Cache`) must not become Safe — Task 2 adds a `.not` matcher and a test.
2. **Parallel scan with overlapping roots** (`~/Library/Caches` and a symlinked child) must not double count — Task 5 tests set equality with the serial result on a fixture containing a symlink and a duplicate root.
3. **Old saved JSON** (sessions and settings written before this change) must still load — Task 1 and Task 9 add decode-old-JSON tests.
4. **Permanent delete on with a mixed selection** must still skip manual-review and block not-allowed items — Task 11 tests it.
5. **Downloaded rule set that overrides or edits a `protect.*` rule** must be rejected — Task 20 tests it.

---

## Phase 0–1: Rules and Junk Detection

### Task 1: Rule overrides, new matchers and model fields (F0, F5 model, F25 matcher)

**Files:**
- Modify: `Sources/CleanScopeCore/Models.swift`, `Sources/CleanScopeCore/ClassificationService.swift`
- Test: `Tests/CleanScopeCoreTests/ClassificationServiceTests.swift`, `Tests/CleanScopeCoreTests/ScanRepositoryTests.swift`, `Tests/CleanScopeCoreTests/SafetyInvariantTests.swift`

**Interfaces:**
- Produces: `ClassificationRule.overrides: [String]` (decode default `[]`); `Matcher.not(Matcher)`, `Matcher.nameMatches(String)` (case-insensitive regex on the name); `ScanResult.isCloudOnly: Bool`, `ScanResult.cloudOnlyBytes: Int64`, `ScanResult.requiresAdmin: Bool` (all decode default false/0); `ClassifiedItemInput.isCloudOnly`, `.cloudOnlyBytes`, `.requiresAdmin`; `ScanSummary.cloudOnlyBytes`; `ClassificationService.rules: [ClassificationRule]` (init param `rules: [ClassificationRule] = builtInRules`); `ClassificationService.validateOverrides(_ rules:) -> [String]` (returns violations).

- [ ] **Step 1: Write failing tests** — `overrideLetsChromiumCacheBeatApplicationSupport` (use an injected rule set containing a `safe.chromium-caches`-style rule with `overrides: ["tool.application-support"]` → `.safeToDelete`); `protectRuleStillWinsOverOverridingRule` (Chrome path → `.doNotBulkDelete`); `noBuiltInRuleOverridesProtectRules` (`validateOverrides(builtInRules).isEmpty`, and only `tool.application-support`/`tool.developer-storage` appear in any `overrides`); `cloudOnlyInputIsNeverDeletable` (`isCloudOnly: true` on a cache path → `canDelete == false`, `deletionMethod == .manualReview`); `sessionWithoutNewFieldsDecodes` (JSON from an encoded session with `isCloudOnly`/`cloudOnlyBytes`/`requiresAdmin`/`cloudOnlyBytes` keys stripped decodes with defaults).
- [ ] **Step 2: Run** `./script/swiftpm.sh test` — expect compile failures.
- [ ] **Step 3: Implement.** In `classify`, after filtering matches, drop any rule whose id is in another match's `overrides`, then apply the existing `max`. `validateOverrides` flags any `protect.*` id in `overrides` and any override target outside the two allowed ids. `isCloudOnly` forces `canDelete = false`, `.manualReview` (unless protected/excluded → `.notAllowed`). Custom `init(from:)` on `ScanResult`, `ScanSummary`, `ClassificationRule` using `decodeIfPresent` for new keys.
- [ ] **Step 4: Run tests** — PASS.
- [ ] **Step 5: Commit** `feat: add rule overrides and cloud-only result fields`

### Task 2: Container, Chromium, media-app and log rules (F1, F2, F3, F25, F26)

**Files:**
- Modify: `Sources/CleanScopeCore/ClassificationService.swift`, `Sources/CleanScopeCore/ScanLocations.swift`
- Test: `Tests/CleanScopeCoreTests/ClassificationFixtures.swift`, `ClassificationServiceTests.swift`, `SafetyInvariantTests.swift`, `ScanRepositoryTests.swift`

**Interfaces:**
- Produces: rules `safe.chromium-caches`, `safe.spotify-cache`, `safe.adobe-media-cache`, `review.telegram-media`, `safe.rotated-logs`, `safe.diagnostic-reports`, `review.live-system-logs`; `ScanLocations.containerCacheRoots(homeDirectory:) -> [String]`; `ScanLocations.containerBundleIdentifier(containerURL:) -> String`; `ClassificationService(appName: @Sendable (String) -> String?)` resolver used for container display names; `ScanResult.displayName` is `name` except container caches → `"<App> cache (<bundle id>)"` (stored in `name`).

- [ ] **Step 1: Failing tests** — fixtures: `…/Application Support/Slack/Cache` safe, ownerApp `Slack`; `…/Slack/IndexedDB` not safe; `…/Slack/Service Worker/CacheStorage/Cache` not safe; Chrome `…/Google/Chrome/Default/Cache` doNotBulkDelete; Spotify/Adobe safe; Telegram `probablyUnused`; `~/Library/Containers/x/Data/Library/Caches` safe with ownerApp `x`; `Containers/x/Data/Documents/file` and `Containers/x/Data/Library/Application Support/db` never safe; `/private/var/log/system.log.0.gz` and `wifi.log.3.bz2` safe; `/private/var/log/system.log` probablyUnused low; `~/Library/Logs/DiagnosticReports/a.ips` safe. `containerCacheRoots` on a temp home with one bundle-id container and one UUID container with metadata plist returns both cache paths; `containerBundleIdentifier` reads `MCMMetadataIdentifier` and falls back to the folder name. Full mode includes `/private/var/log`, `/Library/Logs`, both `DiagnosticReports` roots; developer and full include container cache roots; limited does not.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** rules per spec tables (specificity 85 for chromium; 88 for app media; rotated logs `.all([.pathContains("/private/var/log/"), .nameMatches(#"\.\d+\.(gz|bz2)$"#)])`; live logs `.all([.pathContains("/private/var/log/"), .itemType(.file)])` probablyUnused/low). Chromium matcher adds `.not(.any([pathComponent "local storage","indexeddb","session storage","service worker","cookies","databases"]))`. Owner app for chromium = component after `Application Support`; for container caches = bundle id from the container path (resolver turns it into an app name).
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: detect container, Chromium, media-app and system log caches`

## Phase 2: Scanner Quality

### Task 3: FileFlags and SystemPathGuard (F5, F6)

**Files:** Create `Sources/CleanScopeCore/FileFlags.swift`, `Sources/CleanScopeCore/SystemPathGuard.swift`; Test `Tests/CleanScopeCoreTests/FileSystemHelpersTests.swift`

**Interfaces:** `FileFlags.read(path: String) -> FileFlags?` with `isDataless` (`st_flags & 0x40000000`), `isRestricted` (`st_flags & 0x00080000`); `SystemPathGuard.shouldSkip(_ path: String) -> Bool`, `SystemPathGuard.canonical(_ path: String) -> String`.

- [ ] Tests: temp file → both false; missing path → nil; `shouldSkip` true for `/System/Volumes/Data`, `/Volumes`, `/Volumes/X/a`, `/.nofollow`, `/private/var/vm`, `/home`, false for `/Users/me` and `/Volumesque`; `canonical("/System/Volumes/Data/Users/me") == "/Users/me"`.
- [ ] Implement with `lstat`; run; commit `feat: add file flag and system path helpers`.

### Task 4: Storage tree and treemap layout (F8 Core)

**Files:** Create `Sources/CleanScopeCore/ScanNode.swift`, `Sources/CleanScopeCore/TreemapLayout.swift`; Test `Tests/CleanScopeCoreTests/TreemapLayoutTests.swift`

**Interfaces:** `struct ScanNode: Identifiable, Sendable, Equatable { path, name, sizeBytes, itemType, children: [ScanNode], otherBytes: Int64, resultId: String? }`; `ScanNode.displayChildren(minimumFraction: Double = 0.01) -> [ScanNode]` (children under 1% plus `otherBytes` merged into one `"Other items"` node with id `path + "#other"`); `TreemapLayout.squarify(items: [(id: String, size: Int64)], in rect: CGRect) -> [(id: String, rect: CGRect)]`.

- [ ] Tests: `squarifyPreservesArea` (sum of areas within 0.5% of rect), `squarifyHasNoOverlapsOrNegativeRects`, `squarifyIgnoresZeroSizes`, `otherItemsAggregatesSmallChildren` (children 900, 50, 5, 5 + otherBytes 40 under parent 1000 → "Other items" = 50).
- [ ] Implement standard squarified algorithm (Bruls et al.); commit `feat: add storage tree and squarified treemap layout`.

### Task 5: Parallel scanner with flags, guards and tree (F4, F5, F6, F8 tree, F1 permissions, F25 emission)

**Files:** Modify `Sources/CleanScopeCore/ScannerService.swift`, `Models.swift` (`ScanSession.tree: ScanNode?`, not encoded); Test `ScannerServiceTests.swift`

**Interfaces:** `ScannerService.scan(paths:mode:settings:onResult:)` unchanged signature; `ScannerService(classifier:largeFileThresholdBytes:maxConcurrency: Int = min(activeProcessorCount, 6), treeDepth: Int = 6)`; `ScanSession.tree` (excluded from `CodingKeys`, so it is never persisted); a `VisitedPaths` lock class with `insertIfAbsent(_:) -> Bool`.

- [ ] Tests: `parallelScanMatchesSerialScan` (fixture tree with caches, a symlink and duplicate root; `maxConcurrency: 1` vs `6` produce equal sets of `(path,sizeBytes,category)`); `cancelMidScanReturnsCancelled` (existing test still passes); `scanBuildsTreeWithRootSizes` (root node size equals sum of file allocations); `containerPermissionErrorIsProtectedByMacOS` (unreadable folder under a `Library/Containers` path → `.protectedByMacOS`); `chromiumCacheFolderUnderApplicationSupportIsEmitted`; `diagnosticReportsFolderIsEmitted`.
- [ ] Implement: work items = each root's direct children; bounded task group; each item runs a `nonisolated` recursive function returning `(bytes, results, skipped, node)`; root result emitted after children. Dataless files count 0 bytes and record `cloudOnlyBytes = fileSize` (emitted when logical size ≥ threshold). `isRestricted` → `isProtected`. `requiresAdmin = !isWritableFile(parent)`. Skip `SystemPathGuard.shouldSkip` paths silently; visited set uses `canonical`. Emit folder also when (a) name is a Chromium cache name under `/Application Support/`, (b) name is `DiagnosticReports`; emit file when under `/private/var/log/` with size > 0. Tree keeps folders ≤ `treeDepth` levels and files ≥ 1% of parent or ≥ large threshold; rest goes to `otherBytes`.
- [ ] Record before/after Developer-scan timings in `VERIFY.md`. Commit `feat: scan in parallel and build a storage tree`.

## Phase 3: Storage Visibility

### Task 6: Process runner and system space service (F7)

**Files:** Create `Sources/CleanScopeCore/ProcessRunner.swift`, `Sources/CleanScopeCore/SystemSpaceService.swift`; Test `SystemSpaceServiceTests.swift`

**Interfaces:** `protocol ProcessRunning: Sendable { func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput }`; `struct ProcessOutput { status: Int32; stdout: String; stderr: String }`; `ProcessRunner: ProcessRunning` (Foundation `Process`, kills on timeout, throws `ProcessRunnerError.timedOut`); `SystemSpaceService(runner:)` with `static purgeableBytes(important: Int64, available: Int64) -> Int64`, `purgeableBytes(volume: URL) -> Int64`, `localSnapshots() async -> [Date]`, `static parseSnapshots(_ output: String) -> [Date]`, `thin(requestedBytes: Int64) async throws` (runs `/usr/bin/tmutil thinlocalsnapshots / <bytes> 1`, throws on non-zero status with stderr).

- [ ] Tests: parse zero/one/several snapshots and ignore `com.apple.os.update-…` lines; purgeable clamped at 0; `thin` passes exact arguments to a stub runner.
- [ ] Implement; commit `feat: report purgeable space and local snapshots`.

### Task 7: Dashboard system-space card, Storage Map view and sidebar sections (F7 UI, F8 UI, navigation)

**Files:** Modify `AppModel.swift` (destinations, `Destination.section`), `SidebarView.swift`, `ContentView.swift`, `DashboardView.swift`, `SettingsView.swift`; Create `Sources/CleanScopeApp/Views/StorageMapView.swift`, `Sources/CleanScopeApp/Views/SystemSpaceCard.swift`.

**Interfaces:** `AppModel.Destination` gains `storageMap`, `maintenance`, `loginItems`, `backgroundItems`, `memory`, `protection`, `privacy`; `Destination.Section` enum `storage, performance, protection, history`; `Settings.allowSnapshotThinning: Bool` (default false, decode default).

- [ ] Sidebar groups rows by section with small headers. Dashboard card shows Purgeable, local snapshot count + date range, footnote "Includes X that macOS can reclaim." and, when `allowSnapshotThinning`, "Ask macOS to thin local snapshots…" with the confirmation from the spec and a size picker (default 10 GB).
- [ ] Storage Map: breadcrumb, `Canvas` tiles from `TreemapLayout`, tint + SF Symbol per safety category, name/size label when tile ≥ 60×28 pt, hover tooltip (size, modified, safety label, selected size), click folder to drill, ⌘[ to go up, context selection via `AppModel.setSelection`, "Show as list" toggle, Reduce Motion disables animation, "Run a scan to see the map." when `session?.tree == nil`. Each tile is an accessibility element "Name, size, safety label".
- [ ] Build, launch with `./script/build_and_run.sh --verify`, check the map in the app; commit `feat: add storage map and system-managed space card`.

## Phase 4: Alerts and Menu Bar

### Task 8: Alert snooze store and alert evaluator (F9, F11, F12, F13, F17 alert, F21, F22 kinds)

**Files:** Create `Sources/CleanScopeCore/Alerts.swift`, `Sources/CleanScopeCore/AlertIgnoreStore.swift`; Test `AlertTests.swift`

**Interfaces:** `enum AlertKind: String, Codable, CaseIterable { lowDiskSpace, trashSize, externalDriveLow, memoryPressure, restart, bluetoothBattery, hungApp, malwareDetected }`; `enum SnoozeOption { untilTomorrow, day, threeDays, week, forever }` with `record(kind:discriminator:now:calendar:) -> AlertIgnoreRecord`; `struct AlertIgnoreRecord: Codable { kind, discriminator, ignoredAt, interval: TimeInterval? ; func isActive(at:) -> Bool }`; `AlertIgnoreStore(defaults:)` `load/save/add/reset` under `CleanScope.alertIgnores`; `struct VolumeStatus { uuid, name, totalBytes, availableBytes }`; `struct AlertThresholds { lowDiskBytes: Int64 (default 10 GB), trashBytes: Int64 (5 GB), externalFreeFraction: 0.10, restartUptime: 14 days, bluetoothPercent: 15, memoryPressureDuration: 120 }`; `struct AlertInputs { disk: DiskSnapshot; trashBytes: Int64?; externalVolumes: [VolumeStatus]; memoryPressureLevel: Int?; pressureSince: Date?; uptime: TimeInterval?; bluetooth: [BluetoothBattery] }`; `struct AlertState: Codable, Equatable { active: Set<String> }`; `struct AlertPayload: Equatable { kind, discriminator, title, body }`; `AlertEvaluator.evaluate(inputs:thresholds:ignores:now:previous:) -> (alerts: [AlertPayload], next: AlertState)`; low-disk trigger `max(thresholds.lowDiskBytes, 5% of total)`, clear at trigger + 2 GB.

- [ ] Tests: snooze expiry at midnight boundary and across a DST change (`TimeZone(identifier: "America/New_York")`, 2026-11-01); forever never expires; low-disk crossing fires once, holds silent, clears only above +2 GB (hysteresis), re-fires after clearing; snoozed kind suppressed; trash over 5 GB fires; external < 10% fires keyed by uuid; restart > 14 days fires; bluetooth < 15% keyed by device name; memory pressure ≥ 2 for 120 s fires.
- [ ] Implement; commit `feat: add alert evaluation and snooze store`.

### Task 9: Settings fields (all phases) with decode defaults

**Files:** Modify `Models.swift`; Test `StoreTests.swift`

**Interfaces (all decode-default):** `showMenuBarExtra=false`, `openAtLogin=false`, `lowDiskAlertEnabled=true`, `lowDiskThresholdBytes=10_000_000_000`, `trashAlertEnabled=true`, `trashThresholdBytes=5_000_000_000`, `externalDriveAlertEnabled=true`, `externalDriveMountedNotice=false`, `memoryAlertEnabled=false`, `restartReminderEnabled=true`, `bluetoothBatteryAlertEnabled=true`, `hungAppMonitoringEnabled=false`, `allowSnapshotThinning=false`, `preselectSafeCaches=false`, `deleteImmediately=false`, `showSystemMonitors=true`, `experimentalTemperature=false`, `realTimeProtectionEnabled=false`, `trustedTeamIDs: [String]=[]`.

- [ ] Test `oldSettingsJSONDecodesWithDefaults` (the pre-change 8-key JSON decodes and new fields equal `Settings.default`'s); round-trip still passes. Commit `feat: add settings for alerts, monitoring and cleanup options`.

### Task 10: StatusMonitor, notifications, menu bar extra, open at login, Trash and external-drive actions (F10–F13, F21, F22 wiring)

**Files:** Create `Sources/CleanScopeCore/TrashService.swift` (`trashSize(at:) throws -> Int64`, `static emptyTrashScript`), `Sources/CleanScopeCore/VolumeService.swift` (`externalVolumes() -> [VolumeStatus]`, excludes internal/network), `Sources/CleanScopeApp/StatusMonitor.swift`, `Sources/CleanScopeApp/NotificationCoordinator.swift`, `Sources/CleanScopeApp/AppDelegate.swift`, `Sources/CleanScopeApp/Views/MenuBarContentView.swift`; Modify `CleanScopeApp.swift`, `SettingsView.swift`, `AppModel.swift` (`startScan(paths:mode:)`), `CleanupReportView.swift`, `script/build_and_run.sh` (`NSAppleEventsUsageDescription`, `NSLocationWhenInUseUsageDescription`); Test `TrashServiceTests.swift`.

- [ ] Tests: `trashSize` sums allocated sizes of a temp folder; permission error throws `TrashServiceError.needsFullDiskAccess`; `VolumeService.isEligible` excludes internal and network volumes.
- [ ] `StatusMonitor` (MainActor) refreshes every 5 min while the menu bar extra is shown, 30 min otherwise, and immediately on mount/unmount; it calls `AlertEvaluator` and hands payloads to `NotificationCoordinator` (categories with actions Scan now / Open Trash / Scan drive / Snooze…; snooze submenu via notification action identifiers per `SnoozeOption`). Authorization requested when an alert toggle is first switched on.
- [ ] `MenuBarExtra` (gated by `showMenuBarExtra`) shows free space bar, Trash size, last scan + potential cleanup, Open CleanScope / Start Limited Scan / Settings…, Empty Trash… (CleanScope confirmation first). `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns `!showMenuBarExtra`. Open at login via `SMAppService.mainApp`.
- [ ] Cleanup report adds "X moved to Trash. Empty the Trash in Finder to free the space." Commit `feat: add menu bar status and disk, Trash and drive alerts`.

## Phase 5: Cleanup Options

### Task 11: Permanent delete, admin removal and preselect (F27, F28, F25 removal)

**Files:** Create `Sources/CleanScopeCore/PrivilegedRunner.swift` (`protocol PrivilegedRunning`, `AppleScriptPrivilegedRunner`, `ShellQuote.quote`), Modify `DeletionService.swift`, `AppModel.swift`, `CleanupReviewSheet.swift`, `SettingsView.swift`, `ReportService.swift`; Test `DeletionServiceTests.swift`, `PrivilegedRunnerTests.swift`

**Interfaces:** `DeletionService(fileMover:fileRemover:privileged:trashBinaryExists:diskSnapshot:)`; `cleanup(selected:method: DeletionMethod = .trash)`; `AppModel.cleanupMethod` maps `.trash`→`.permanent` when `deleteImmediately`; `ShellQuote.quote(_:) -> String` (single quotes, `'\''` escape); `PrivilegedRunning.run(command: String) async throws -> ProcessOutput`.

- [ ] Tests: permanent uses remover not mover and message "Deleted permanently."; with permanent on, manual-review skipped and not-allowed blocked; with setting off `.permanent` never used (AppModel mapping is a pure static func `DeletionService.effectiveMethod(deleteImmediately:)` tested); `requiresAdmin` items batch into one privileged call `/usr/bin/trash -- 'a' 'b'` when trash exists; without trash binary and method `.trash` → skipped with "Removed permanently (needs administrator)"; `ShellQuote` escapes `'`; preselect helper `ResultPresentation.preselection(for:)` returns only Ready-to-Delete cache ids.
- [ ] Review sheet: button "Delete Permanently" plus a second confirmation alert with count and size when `deleteImmediately`. Commit `feat: add permanent delete option and cache preselection`.

### Task 12: Trashed-app leftovers and external drive cleaner (F14, F29)

**Files:** Create `Sources/CleanScopeCore/LeftoverFinder.swift`, Modify `ClassificationService.swift` (rules `safe.volume-trashes`, `safe.appledouble`, `safe.ds-store`, `protect.volume-system`), `ScannerService.swift` (emit `._*` on non-APFS/HFS volumes and group `.DS_Store` into one result per scan root), `AppModel.swift`, `ContentView.swift`; Test `LeftoverFinderTests.swift`, `ClassificationServiceTests.swift`

**Interfaces:** `LeftoverFinder(homeDirectory:isInstalled: @Sendable (String) -> Bool, classifier:)`; `trashedApps() -> [TrashedApp]` (`bundleID`, `name`, `path`); `leftovers(for: TrashedApp) -> [ScanResult]` — exact-match locations from spec F14, each result `probablyUnused`/medium unless a `protect.*` rule matches (then excluded). `Destination` result group "Leftovers" filtered by `ownerApp` tag `"leftover:<bundle id>"` is avoided; leftovers are appended to `streamedResults` with `reason == "Leftover from an app in Trash"`.

- [ ] Tests: fixture home with fake `Foo.app` (Info.plist `CFBundleIdentifier=com.foo`) in `.Trash` → finds `Application Support/com.foo`, `Caches/com.foo`, `Preferences/com.foo.plist`; does not find `Application Support/com.foobar`; installed app → no leftovers; `Application Support/1Password` style protected path never returned. Volume rules: `/Volumes/X/.Trashes/501` safe, `/Volumes/X/._file` safe, `.DS_Store` safe, `/Volumes/X/.Spotlight-V100` doNotBulkDelete.
- [ ] Commit `feat: find leftovers of trashed apps and clean external drives`.

## Phase 6: Performance

### Task 13: PRODUCT.md scope update

- [ ] Update purpose (storage, performance, protection, monitoring), users, and anti-references (gauges/dials still out; calm alerts in; one-click cleaning still out — every action is reviewed). Commit `docs: widen product scope for performance and protection`.

### Task 14: Maintenance tasks (F15)

**Files:** Create `Sources/CleanScopeCore/Maintenance.swift`, `Sources/CleanScopeCore/MailVacuum.swift`, `Sources/CleanScopeApp/Views/MaintenanceView.swift`; Test `MaintenanceTests.swift`

**Interfaces:** `protocol MaintenanceTask: Sendable { id, title, description, requiresAdmin, isRecommended, isAvailable; func run(context: MaintenanceContext) async throws -> MaintenanceOutcome }`; `MaintenanceContext { runner: ProcessRunning; privileged: PrivilegedRunning; space: SystemSpaceService; homeDirectory: String; uid: uid_t }`; `MaintenanceCatalog.all(fileExists:) -> [any MaintenanceTask]`; `MaintenanceCatalog.adminCommand(for id:, uid:) -> String?`; `MaintenanceRunStore` (`CleanScope.maintenanceRuns`); `MailVacuum.vacuum(databaseURL:, isMailRunning: () -> Bool, vacuum: (URL) throws -> Void)`.

- [ ] Tests: golden admin commands — `flush-dns` = `/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder`; `reindex-spotlight` = `/usr/bin/mdutil -E /`; `periodic` = `/usr/sbin/periodic daily weekly monthly` (only available when file exists); `repair-home-permissions` = `/usr/sbin/diskutil resetUserPermissions / 501` for uid 501. Mail task refuses when Mail running, restores backup on simulated VACUUM failure.
- [ ] View lists tasks with description, last-run date, Run, and "Run recommended". Commit `feat: add maintenance tasks`.

### Task 15: Login and background items (F16)

**Files:** Create `Sources/CleanScopeCore/LaunchItems.swift`, `Sources/CleanScopeCore/CodeSigning.swift`, `Sources/CleanScopeApp/Views/LaunchItemsView.swift`; Test `LaunchItemsTests.swift`

**Interfaces:** `struct LaunchItem: Identifiable { id(path), label, program: String?, plistPath, scope: user|system, runAtLoad, keepAlive, disabled, isBroken, owningApp: String?, teamID: String? }`; `LaunchItemParser.parse(plistURL:fileExists:) -> LaunchItem?`; `LaunchItemService.items(directories:) -> [LaunchItem]` (filters `com.apple.` and Apple-signed); `LaunchItemService.disableCommand/bootoutCommand(item:uid:) -> [String]`; `CodeSigning.teamID(path:) -> String?`; `LegacyLoginItems` via System Events AppleScript.

- [ ] Tests: `Program` form, `ProgramArguments` form, broken detection, Apple label filtered. Commit `feat: list and manage login and background items`.

### Task 16: Memory view and relief (F17)

**Files:** Create `Sources/CleanScopeCore/MemoryService.swift`, `Sources/CleanScopeCore/MemoryReclaimer.swift`, `Sources/CleanScopeApp/Views/MemoryView.swift`; Test `MemoryTests.swift`

**Interfaces:** `MemorySnapshot { totalBytes, appBytes, wiredBytes, compressedBytes, cachedBytes, freeBytes, inactiveBytes, swapUsedBytes, pressureLevel }`; `MemoryService.snapshot() -> MemorySnapshot`; `topConsumers(limit:) -> [ProcessMemory]` (`ri_phys_footprint`); `MemoryReclaimer.allocationLimit(free:inactive:) -> Int64` (= max(0, free+inactive−1 GiB)); `reclaimWithAllocation(limitBytes:blockBytes:pressure:isCancelled:) async -> Int64`; `reclaimWithPurge(privileged:)` runs `/usr/sbin/purge`.

- [ ] Tests: limit math; cancel stops within one block; pressure 2 stops. Commit `feat: add memory view and memory relief`.

## Phase 7: Monitoring

### Task 17: System metrics, hung apps, status summary, restart and Bluetooth (F18–F22)

**Files:** Create `Sources/CleanScopeCore/SystemMetrics.swift` (CPU, network, battery, uptime, Bluetooth samplers), `Sources/CleanScopeCore/SMCReader.swift`, `Sources/CleanScopeCore/StatusSummary.swift`, `Sources/CleanScopeApp/HungAppMonitor.swift`; Modify `MenuBarContentView.swift`, `DashboardView.swift`, `StatusMonitor.swift`; Test `MonitoringTests.swift`

**Interfaces:** `CPULoad.usage(previous: [CoreTicks], current: [CoreTicks]) -> (total: Double, perCore: [Double])`; `NetworkThroughput.rate(previous:current:interval:)`; `BatteryHealth.from(registry: [String: Any]) -> BatteryHealth?` (health uses `AppleRawMaxCapacity ?? NominalChargeCapacity` / `DesignCapacity`, `isCritical` < 0.70); `Uptime.since(bootTime:now:)`; `BluetoothBattery { name, percent }`; `StatusSummary.evaluate(inputs:) -> StatusSummary` with checks Disk space, Trash, Protection, Battery, Memory and weights 35/10/25/15/15; `HungAppDetector.record(pid:result:)` marks hung after two consecutive `cannotComplete`.

- [ ] Tests: CPU diff math; battery health from a dict without `AppleRawMaxCapacity`; summary score and per-check "Needs attention" reasons; hung after two failures, reset on success. Commit `feat: add system monitors, status summary and reminders`.

## Phase 8: Protection

### Task 18: Malware rule engine and scan targets (F23)

**Files:** Create `Sources/CleanScopeCore/Malware/MalwareRules.swift`, `MalwareScanner.swift`, `ExtensionInventory.swift`, `YaraScanner.swift`, `ContainerExpander.swift`, `Sources/CleanScopeApp/Views/ProtectionView.swift`; Resource `Sources/CleanScopeCore/Resources/malware-rules.json`; Modify `Package.swift` (resources); Test `MalwareTests.swift`

**Interfaces:** `MalwareRuleSet { version, pathRules, hashRules(sha256,size), teamIDRules(detect|ignore), launchAgentRules(label/program pattern), extensionRules(browser,id), profileRules(identifier) }`; `Threat { id, name, category: ThreatCategory, location, detectedBy }`; `MalwareScanner(rules:yara:runner:trustedTeamIDs:)` `scan(targets: [MalwareTarget]) async -> MalwareScanReport`; `FileHasher.sha256(url:) throws -> String` (streamed); `ChromeExtensions.list(home:) -> [BrowserExtension]`; `CronParser`, `ProfilesParser`; `ContainerExpander` (limits depth 3, 500 MB archives, 100 MB YARA files); removal plan `MalwareRemoval.steps(for:) -> [RemovalStep]`.

- [ ] Tests: hash match only after size pre-check (hasher not called on size mismatch); team-ID detect suppressed by trusted list; path rule; Chrome manifest discovery; removal order terminate → bootout → detach. Commit `feat: add malware scanning`.

### Task 19: Real-time monitoring (F24)

**Files:** Create `Sources/CleanScopeCore/Malware/EventCoalescer.swift`, `Sources/CleanScopeApp/RealTimeMonitor.swift`; Test `EventCoalescerTests.swift`

**Interfaces:** `EventCoalescer(window: 10)` `shouldProcess(path:at:) -> Bool`; `LaunchScanCache.shouldScan(path:modified:) -> Bool`.

- [ ] Tests: same path within 10 s merged; after 10 s processed; launch cache per path+mtime. Commit `feat: add real-time protection monitoring`.

### Task 20: Updatable rule set (F30)

**Files:** Create `Sources/CleanScopeCore/RuleUpdates.swift`, `script/sign_rules.swift`; Test `RuleUpdateTests.swift`

**Interfaces:** `RuleManifest { version, minAppVersion, rules: URL, malware: URL, signature }`; `RuleUpdateVerifier(publicKey:)` `verify(manifestData:signature:) -> Bool`, `accept(manifest:currentVersion:appVersion:) throws`; `RuleSetValidator.validate(downloaded: [ClassificationRule], builtIn:) throws` (rejects changed/removed/added `protect.*` ids and any override of `protect.*`); `RuleUpdateConfiguration.manifestURL: URL?` = nil.

- [ ] Tests: valid signature accepted; tampered rejected; downgrade rejected; protect override rejected; protect removal rejected. Commit `feat: add signed rule updates`.

### Task 21: Privacy cleanup (F31)

**Files:** Create `Sources/CleanScopeCore/QuarantineHistory.swift`, `Sources/CleanScopeApp/Views/PrivacyView.swift`; Test `QuarantineHistoryTests.swift`

**Interfaces:** `QuarantineHistory(databaseURL:)` `count() throws -> Int`, `clear() throws` (`DELETE FROM LSQuarantineEvent; VACUUM`).

- [ ] Tests on a temp SQLite DB with the `LSQuarantineEvent` table. Commit `feat: add download history cleanup`.

### Task 22: Verification

- [ ] `./script/swiftpm.sh test`, `./script/swiftpm.sh build`, `./script/build_and_run.sh --verify` all pass.
- [ ] Add the spec's VERIFY.md additions plus a dated section with results; commit `test: verify gap features`.
