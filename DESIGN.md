# CleanScope Design System

## Theme

**Greenhouse** pairs a calm, native macOS utility with warm paper surfaces and muted botanical color. The interface feels fresh and optimistic, while safety-critical content stays precise and familiar.

The visual metaphor is quiet: scanning reveals where space can grow. It must not introduce a mascot, literal scenery or game mechanics, and the word "greenhouse" never appears in UI copy.

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

Color never replaces the safety icon and text label.

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

## Motion

- Every transition uses `BrandTheme.animation(reduceMotion)`: 200 ms ease-out, or no animation when Reduce Motion is on.
- Scan progress: the sprout gains three growth stages (stem, first leaf, second leaf) as results stream in (`StoragePresentation.growthStage`).
- Cleanup completion: the mark settles in once.
- No hover scaling, bounce, streaks, points, levels, confetti, or repeated ambient animation. No haptics.

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

### Growth Summary

- One raised surface: Sprout Lens at its growth stage, “Safe to reclaim” figure, a line with the safe count and review-needed space, and a disk bar showing used vs. available space with the safe share marked.
- It is informative before it is decorative. No gauges.

### Results

- Native `Table` with sortable Name, Size, Safety and Modified columns, plus a leading cleanup checkbox column that stays separate from row highlight.
- Shift-click on checkboxes selects an eligible range. Double-click or Return opens details. The context menu offers details, Finder, select/deselect for cleanup, exclude, and Move to Trash….
- `.searchable` in the toolbar. Review Cleanup… is the toolbar primary action.
- Ineligible rows keep a disabled checkbox whose tooltip and VoiceOver hint explain why.
- The header states the selection, including items selected in other sections.

### Destructive Actions

- Every path to Trash (bulk, quick wins, context menu, detail sheet) goes through `CleanupReviewSheet`, which lists the exact items, their categories and total.
- The confirm button is never the default action. Escape cancels.
- Excluding an item shows an Undo bar. Exclusions are listed and removable in Settings and are applied to every later scan.

### Cleanup Completion

- Recovered space is the primary result.
- Show moved, skipped, blocked, and failed outcomes without hiding zero states, plus available space before and after.
- Celebration stays subtle and stops automatically.
