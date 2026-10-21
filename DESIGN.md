# CleanScope Design System

## Theme

**Greenhouse** pairs a calm, native macOS utility with warm paper surfaces and muted botanical color. The interface feels fresh and optimistic, while safety-critical content stays precise and familiar.

The visual metaphor is quiet: scanning reveals where space can grow. It must not introduce a mascot or game mechanics. The only literal scenery is the storage terrarium on the Dashboard hero and Last Cleanup, built from the user's real numbers. The word "greenhouse" never appears in UI copy.

## Identity

### Primary Mark

**Sprout Lens:** a magnifying lens containing a two-leaf sprout.

- The lens represents inspection, clarity, and the `Scope` name.
- The sprout represents reclaimed room and future possibility.
- The mark must remain recognizable at 16 px and use bold, simple geometry.
- The production app icon uses the mark without text on a macOS rounded-square composition.
- In the app the mark keeps its own colors (`BrandTheme.Mark`) so it always matches the app icon. It is never recolored with UI tokens.

### Lockup

- Wordmark: `CleanScope` in SF Pro Display Bold or the system equivalent.
- Tagline: **Make room for what’s next.**
- Use the full lockup only in onboarding, About, documentation, and release artwork.
- Navigation and compact UI use the mark plus product name.

## Color

Tokens live in `Sources/CleanScopeApp/Brand/BrandTheme.swift`. They are named by role, built in sRGB, and each has light, dark and increased-contrast values.

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `surface` | `#FAF7F2` | `#1A1816` | Window and detail background |
| `surfaceRaised` | `#F0EAE2` | `#252220` | Summary surface, grouped lists |
| `textPrimary` | `#2C2420` | `#F2EDE8` | Primary text |
| `textSecondary` | `#6B6561` | `#918C87` | Secondary text, captions, paths |
| `accent` | `#526D56` | `#4D814D` | Fills that carry white labels: prominent buttons, checkboxes, app tint |
| `accentText` | `#526D56` | `#8FBC8F` | Accent-colored text and icons |
| `safe` | `#3D6B4A` | `#5DA96A` | Safe state, positive progress |
| `review` | `#816025` | `#E0B05A` | Review recommended |
| `destructive` | `#A54C3F` | `#E8836F` | App/tool dependent, destructive confirmation, failures |
| `info` | `#4B698A` | `#7DA4CC` | Information, permission guidance |
| `hairline` | system separator | system separator | Dividers |

Brand mark only (`BrandTheme.Mark`): lens `#176F5D` / `#63C6A7`, leaf `#50B77A` / `#71D198`, field `#DFF2E8` / `#173C33`.

**Contrast contract.** Every text-role token measures at least 4.5:1 against both `surface` and `surfaceRaised` in light, dark and both increased-contrast appearances; the lowest is 4.74:1. White on `accent` is at least 4.6:1. Do not use a state color at reduced opacity as text. Tinted backgrounds (8–10% of a state color) carry `textPrimary` or the state color at full strength.

### Fill tokens

Tile fills for the Storage Map and the scan theatre jars. They live in Core (`BrandPalette`) next to the role tokens and have light and dark values. Labels on a fill use `BrandPalette.labelColor(onFill:)`, which picks `textPrimary` or `surface` per appearance, whichever reaches 4.5:1 (a test checks every fill in light, dark and both increased-contrast appearances).

| Token | Light | Dark | Used for |
| --- | --- | --- | --- |
| `safeFill` | `#86B892` | `#528F60` | Safe to delete |
| `reviewFill` | `#E4BC6A` | `#B98A35` | Review recommended |
| `appFill` | `#DE9682` | `#BC6C58` | App/tool dependent |
| `keepFill` | `#C3B8AC` | `#625A53` | Do not bulk delete |
| `systemFill` | `#9C9085` | `#4A423C` | Reserved for system-managed space (defined, not yet drawn) |
| `freeFill` | `#D4ECDD` | `#27443A` | The free-space tile |
| `unclassifiedFill` | `#D9D2C9` | `#3A3531` | Folders with no classified descendants, and "Other items" |

The dark `safeFill` (`#528F60`) and `appFill` (`#BC6C58`) are lifted slightly from the concept board (`#4F8A5D`, `#B8644F`) because labels on the board values measured 4.32:1 and 4.19:1.

Color never replaces the safety icon and text label. A tile's safety label is also in its tooltip, its label bubble and its VoiceOver text.

## Typography

- Family: SF Pro / system font throughout, using system text styles (`.body`, `.callout`, `.caption`, `.title3`) so text follows the user's settings.
- Dashboard headline: 26 pt bold, state-driven copy.
- Section heading: `.title3` semibold.
- Window titles use `navigationTitle` and `navigationSubtitle`, not in-content headers.
- Data values (byte sizes, the safe-to-reclaim figure): SF Pro Rounded, bold or semibold, tabular digits. **Rounded is reserved for data values.**
- Safety, permission and confirmation copy always use the standard system design.
- No fixed sizes below `.caption`. Letter spacing remains zero.

## Shape And Depth

- Component radius: `BrandTheme.radius` 10 pt, `smallRadius` 7 pt.
- App icon follows the macOS icon mask.
- No pills outside native control styles. Selection, search and sort use native controls.
- A surface gets a fill or a border, not both. Only floating overlays (the exclusion undo bar) carry a shadow.
- Page sections remain unframed. A raised surface is reserved for the growth summary, grouped lists (quick wins, cleanup outcomes) and the undo bar.
- No translucent materials as decoration. The sidebar's material comes from the native sidebar list.

## Iconography

- Use SF Symbols for interface controls and Finder file-type icons for files and folders.
- Use filled symbols for safety state and outline symbols for navigation.
- The Sprout Lens is the only custom brand mark.
- Safety icons:
  - Safe: `checkmark.circle.fill`
  - Review: `questionmark.circle.fill`
  - App/tool dependent: `exclamationmark.triangle.fill`
  - Do not bulk delete: `hand.raised.fill`
  - Protected: `lock.fill`

### 3D module icons

Twelve soft-clay 3D icons (`ModuleIconKey`: scan, cleanup, map, large, dev, downloads, leftovers, maintenance, memory, login, protection, privacy) mark modules. They are rendered by `script/render_icons.swift` from the geometry in `Brand/IconGeometry.swift` and committed as PNGs in `Resources/Icons` (`<key>@1x/@2x/@3x.png` plus an 18-frame `<key>-hover-NN.png` loop). The render is deterministic and is not run at build time.

- Placement is limited to: module headers and empty states (64 pt), the results header (40 pt), the Dashboard Modules row and the menu bar popover header (32 pt).
- Never in the sidebar, tables, review sheets, item detail or any dialog. Those keep SF Symbols.
- `ModuleIcon` is hidden from VoiceOver; the adjacent title carries the meaning.
- On hover it plays the 18 frames once at 30 fps, rests on the last frame while hovered, and tilts up to 10° toward the pointer. Reduce Motion shows the still image.

## Motion

Motion shows real data or confirms a user action. Nothing animates toward an invented value; sample data exists only in debug snapshots.

### Policy

`MotionPolicy` (App) is the only gate. It wraps Core's `MotionDecision`, which has two outputs:

- `allowsTransitions`: short transitions and user-triggered motion. Off only when Reduce Motion is on.
- `allowsAmbientMotion`: continuous, decorative motion (terrarium spin, weather drift, scan sweep band, theatre particles). Off when Reduce Motion is on, Low Power Mode is on, the main window is occluded or minimised, or the app is inactive.

Views read these through the environment object and never check Reduce Motion themselves. `motion.animation(_:)` returns the animation (default 200 ms ease-out) or `nil`. In debug builds `--reduce-motion` forces Reduce Motion on.

### Allowed motion

| Surface | Motion | Duration | Reduce Motion |
| --- | --- | --- | --- |
| Transitions | `MotionPolicy.animation(_:)` (default ease-out) | 200 ms | None |
| Module icon | Hover loop, tilt toward pointer (max 10°) | 18 frames at 30 fps, tilt 150 ms | Still image |
| Storage Map lens | Follows the pointer; rests on the largest selectable tile | Follows input | Same (it is input, not decoration) |
| Storage Map sweep | Tiles not yet reached draw as outlines; a light band marks `scanProgress` | Follows the scan | Outlines, no band |
| Storage Map collapse | Trashed tiles shrink while the layout settles | 0.7 s | New layout at once |
| Harvest basket | A chip with the item name flies to the basket; the basket pulses once | 0.55 s | No flight; count updates in place |
| Hero | Headline blurs in, sprout gains a stage with a spring, progress bar eases | 0.25 s | Crossfade, 200 ms |
| Recovered bytes | Rolls from 0 to the total, once per confirmed cleanup | 0.9 s | Shows the total |
| Scan theatre | One dot per streamed result (at most 40 per batch) arcs to its jar; jar fill eases | 0.62 s per dot, fill 0.35 s | No dots; counts and fills update directly |
| Terrarium idle | Spin at 0.12 rad/s, pointer tilt up to 0.3 rad, lens bob, sprout sway | Continuous | One still frame |
| Terrarium scanning | Lens orbits the dome (3 s per turn); the layer of the latest streamed category glows | Continuous | One still frame |
| Terrarium after cleanup | Litter shrinks and sinks, safe layer thins, sprout gains a stage | 1.6 s after a 0.4 s hold | New state at once |
| Disk weather | Colors interpolate with disk use; on macOS 15 the mesh's inner points drift (20 fps) | 400 ms | Still gradient |
| Menu bar sprout | Template image changes stage; no animation | None | None |

### Rules

- Review stays still: `CleanupReviewSheet`, item detail and confirmations show no ambient or decorative motion. Their snapshots are pixel-identical with and without `--reduce-motion`.
- Delight follows a confirmed action. The terrarium compost, the rolling number and the hero's cleaned face start only after a cleanup the user confirmed.
- 3D scenes and particles stop when off-screen, when the window is hidden or minimised, and in Low Power Mode (`isPlaying` and `rendersContinuously` follow `allowsAmbientMotion`).
- No hover scaling on controls, bounce, streaks, points, levels, confetti or countdowns. No haptics. No sound.
- The sprout's growth stages (stem, first leaf, second leaf) come from `StoragePresentation.growthStage` and `HeroState.sproutStage`.

## Voice

Prefer:

- “Let’s see where your space went.”
- “You found 1.85 GB of breathing room.”
- “274 items deserve a closer look.”
- “Moved safely to Trash.”

Avoid:

- “Junk detected.”
- “Critical cleanup.”
- “Fix now.”
- “Boost your Mac.”
- Garden or greenhouse scenery in copy (“pruning”, “your greenhouse”).

Counts always inflect (`CountPhrase.make`): “1 item”, “2,709 items”. Destructive buttons name the count and the destination: “Move 6 Items to Trash”.

## Honest Numbers

- Byte totals never count a folder and its contents twice. Sum with `ResultPresentation.totalBytes` and pick quick wins with `ResultPresentation.outermost`.
- The headline figure is safe-to-delete space only. Review-needed space is shown separately and labelled as needing review.
- Disk capacity comes from the real volume, including before the first scan. Missing values show “—”, never zero.

## Core Component Patterns

### Window

- `NavigationSplitView` with a collapsible, resizable sidebar (⌃⌘S). Minimum window 820 × 560.
- Settings live only in the Settings scene (⌘,).

### Sidebar

- Native `List(selection:)` with `.sidebar` style, grouped into Overview, Browse and Activity.
- Each result destination shows an item-count badge after a scan.
- Sprout Lens plus `CleanScope` at the top.
- Primary scan action pinned at the bottom with a visible Cancel state and a one-line status.

### Dashboard

- A weather background (`DiskWeatherBackground`) sits behind the top of the page and fades into the plain surface. It moves from a fresh morning to a warm afternoon as disk use rises from 40% to 98% (`DiskWeather`, light and dark stop sets). It never uses the destructive color, and `textPrimary` is checked against every stop.
- The hero (`DashboardHero`) is one view with four faces (`HeroState`): Idle ("Let’s see where your space went."), Scanning ("Looking for room to grow…", live progress bar), Results ("You found X of breathing room.") and Cleaned ("Moved safely to Trash.", or "Deleted permanently." when "Delete immediately" was on for that cleanup, with the recovered figure rolling up; `StoragePresentation.cleanedHeadline` picks the line from the method the cleanup used). The Sprout Lens beside the headline grows one stage per face.
- The hero sub-line is `StoragePresentation.heroSubline`: the first-run reassurance before a scan, "N items found so far." while scanning, and the weather line after (`weatherLine`: "Plenty of room." below 70% used, "Getting cozy." below 88%, otherwise "Room is tight. X available." plus the quick-win figure when there is one).
- The storage terrarium (360 × 240 pt, right of the headline) shows five soil layers (macOS and apps, personal, app data, review, safe) sized from the scan (`TerrariumLayout`). It is one accessibility element that states the same figures in words. It appears nowhere else except Last Cleanup and the menu bar popover thumbnail.
- While scanning, the scan theatre sits below the hero: the path being scanned in monospace and four jars (Safe, Review, App data, Keep) with the exact streamed counts; fill is the count relative to the fullest jar.
- Below the hero: one raised summary surface (safe count, review-needed space, disk bar with the safe share marked, permission state), Mac status, System-managed space, a Modules row of 32 pt module icons with counts, and up to six outermost quick wins.
- It is informative before it is decorative. Numbers and the disk bar carry the story; there are no dials.

### Storage Map

- A squarified treemap (`TreemapLayout`) of the current folder, drawn once into a `Canvas` (`MapCanvas`, `MapTileLayer`). Tiles have 6 pt corners and a 2 pt gap. Small folders group into one "Other items" tile.
- Tile color is the safety fill of its result (`StorageMapPresentation.tone`); a folder without a result takes the category covering the most bytes beneath it, then `unclassifiedFill`. A free-space tile in `freeFill` appears only at the top level of a whole-Mac scan (`showsFreeSpace`), never in a limited or developer scan.
- The Sprout Lens is a circular magnifier (radius 46–78 pt by window width, 2.6× zoom, 7 pt accent ring, handle at 45°) that follows the pointer and shows a label bubble with the tile's name, size and safety label. With no pointer or focus it rests on the largest selectable tile and never roams. Refraction comes from a Metal shader (`Lens.metal`) where the app bundle has a compiled library; otherwise the lens draws plain SwiftUI glass with the same layout and labels.
- Selecting: clicking a safe tile toggles its selection (the same `AppModel.selection` as the tables), as do Space on the focused tile and the context menu "Select for Cleanup". Double-click (or Return) opens a folder; a single click opens a folder that can't be selected. Because the single and double click are exclusive gestures, a single click lands after the system double-click interval. Selected tiles lift 4 pt and show a check badge.
- Keyboard: the map is focusable. Arrow keys move through tiles top to bottom, then left to right; Space toggles, Return opens, ⌘[ goes up a folder. VoiceOver reads each tile as "Name, size, safety label, selected" and offers an Open action on selectable folders. "Show as list" shows the same data as a list with checkboxes.
- While a scan runs, tiles not yet reached by `scanProgress` draw as outlines. After a confirmed cleanup the trashed tiles shrink over 0.7 s, then the report opens.

### Results

- Native `Table` with sortable Name, Size, Safety and Modified columns, plus a leading cleanup checkbox column that stays separate from row highlight.
- Shift-click on checkboxes selects an eligible range. Double-click or Return opens details. The context menu offers details, Finder, select/deselect for cleanup, exclude, and Move to Trash….
- `.searchable` in the toolbar. The harvest basket is the toolbar primary action.
- Ineligible rows keep a disabled checkbox whose tooltip and VoiceOver hint explain why.
- The header states the selection and, when part of it is outside the current section, "N selected in other sections". Clear Selection stays in the header.
- The toolbar harvest basket shows the item count and the deduplicated total of everything selected. Clicking it opens the review sheet with exactly those items. Cleanups never overlap: Review actions, and every Start Scan control, are disabled while one runs ("A cleanup is already running"). A selection the app makes itself (scan-completion preselection) flies no chip.

### Destructive Actions

- Every path to Trash (bulk, quick wins, context menu, detail sheet) goes through `CleanupReviewSheet`, which lists the exact items, their categories and total.
- The confirm button is never the default action. Escape cancels.
- Excluding an item shows an Undo bar. Exclusions are listed and removable in Settings and are applied to every later scan.

### Cleanup Completion

- Recovered space is the primary result.
- Show moved, skipped, blocked, and failed outcomes without hiding zero states, plus available space before and after.
- The recovered figure rolls up once, the terrarium composts its litter and gains a growth stage, and the hero shows its cleaned face. Celebration stays subtle and stops automatically.
- The menu bar sprout (`MenuBarPresentation`) grows with cache age: stage 0 under 5 days or 250 MB of safe space, stage 2 from 12 days and 1 GB, otherwise stage 1. From 14 days and 500 MB the label also shows the size.
