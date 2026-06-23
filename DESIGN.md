# CleanScope Design System

## Theme

**Space Garden** combines a calm native macOS utility with light, organic momentum. The interface feels fresh and optimistic, while safety-critical content remains precise and familiar.

The visual metaphor is simple: scanning reveals where space can grow. It must not introduce a mascot, literal scenery throughout the product, or game mechanics.

## Identity

### Primary Mark

**Sprout Lens:** a magnifying lens containing a two-leaf sprout.

- The lens represents inspection, clarity, and the `Scope` name.
- The sprout represents reclaimed room and future possibility.
- The mark must remain recognizable at 16 px and use bold, simple geometry.
- The production app icon uses the mark without text on a macOS rounded-square composition.

### Lockup

- Wordmark: `CleanScope` in SF Pro Display Bold or the system equivalent.
- Tagline: **Make room for what’s next.**
- Use the full lockup only in onboarding, About, documentation, and release artwork.
- Navigation and compact UI use the mark plus product name.

## Color

| Token | Light | Dark | Role |
| --- | --- | --- | --- |
| `scopeForest` | `#176F5D` | `#63C6A7` | Primary actions, selection, active scan |
| `freshLeaf` | `#50B77A` | `#71D198` | Safe state and positive progress |
| `openMint` | `#DFF2E8` | `#173C33` | Growth surface and safe selection tint |
| `sunToken` | `#FFCF4A` | `#E7BC43` | Review recommended |
| `actionCoral` | `#E9573F` | `#FF7865` | Destructive confirmation and failures |
| `finderBlue` | `#426BD2` | `#7395F2` | Information, permission guidance, tools |
| `deepInk` | `#17231F` | `#F1F6F3` | Primary text |
| `clearPaper` | `#FBFDFC` | `#121816` | Main surface |

Use semantic system colors when they improve accessibility. Color never replaces the safety icon and text label.

## Typography

- Family: SF Pro / system font throughout.
- Hero message: 26–30 pt, bold.
- Section heading: 17–20 pt, semibold or bold.
- Body and table text: standard macOS control sizes.
- Data values: SF Pro Rounded or `.rounded` system design, bold, tabular digits.
- Safety and permission copy always use the standard system design, never rounded display styling.
- Letter spacing remains zero.

## Shape And Depth

- Component radius: 7–10 px.
- App icon follows the macOS icon mask.
- Avoid pills except compact status tokens.
- Prefer a border or a tight shadow, never both as decoration.
- Page sections remain unframed. Cards are reserved for metrics, the growth summary, and repeated item rows where framing improves scanning.

## Iconography

- Use SF Symbols for interface controls.
- Use filled symbols for safety state and outline symbols for navigation.
- The Sprout Lens is the only custom brand mark.
- Safety icons:
  - Safe: `checkmark.circle.fill`
  - Review: `questionmark.circle.fill`
  - App/tool dependent: `exclamationmark.triangle.fill`
  - Do not bulk delete: `hand.raised.fill`
  - Protected: `lock.fill`

## Motion

- Standard transitions: 150–220 ms ease-out.
- Scan progress: the sprout gains up to three growth stages as results stream in.
- Safe selection: mint tint and checkmark transition together.
- Cleanup completion: recovered-space value rolls once and leaves settle into place.
- No bounce, streaks, points, levels, confetti, or repeated ambient animation.
- Reduce Motion replaces all transforms with immediate state changes or crossfades.

## Voice

Prefer:

- “Your Mac has room to grow.”
- “You found 6.21 GB of breathing room.”
- “Three items deserve a closer look.”
- “Moved safely to Trash.”

Avoid:

- “Junk detected.”
- “Critical cleanup.”
- “Fix now.”
- “Boost your Mac.”

## Core Component Patterns

### Sidebar

- Native macOS source list.
- Sprout Lens plus `CleanScope` at the top.
- Full destination labels at the default width.
- Primary scan action remains at the bottom with visible cancel state.

### Growth Summary

- One mint-tinted summary surface.
- Shows reclaimable space, short contextual copy, scan progress, and restrained plant geometry.
- It is informative before it is decorative.

### Metrics

- Available space, generated files, and review count.
- Keep metrics compact and unequal in emphasis.
- Do not create a repeated grid of identical promotional cards.

### Results

- Native table behavior with richer selection and category treatment.
- Safe rows are selectable; risky rows remain visibly disabled.
- Row details and Finder action remain familiar macOS affordances.

### Cleanup Completion

- Recovered space is the primary result.
- Show deleted, skipped, blocked, and failed outcomes without hiding zero states.
- Celebration remains subtle and stops automatically.
