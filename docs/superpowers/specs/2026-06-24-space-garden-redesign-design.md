# CleanScope Space Garden Redesign

## Objective

Redesign the existing CleanScope MVP into a playful, satisfying native macOS utility and create a complete production brandkit around the approved **Space Garden** direction and **Sprout Lens** identity.

The redesign changes presentation and interaction quality without weakening classification, permission, selection, or deletion safety.

## Approved Direction

- Personality: playful utility with light game-like momentum.
- Visual route: Space Garden clarity with selected Color Lab precision and restrained Arcade energy.
- Logo concept: Sprout Lens.
- Tagline: **Make room for what’s next.**
- Emotional outcome: maintenance feels lighter; deletion still feels deliberate.

## Brand Deliverables

### Logo And App Icon

Create a vector master of the Sprout Lens using simple, symmetrical geometry:

- Forest lens ring and handle.
- Two Fresh Leaf shapes and a centered stem.
- Clear interior with enough negative space at 16 px.
- No text inside the app icon.

Export:

- `Assets/Brand/CleanScopeMark.svg`
- `Assets/Brand/CleanScopeWordmark.svg`
- `Assets/Brand/CleanScopeLockup.svg`
- `Assets/Brand/AppIcon-1024.png`
- macOS icon sizes: 16, 32, 64, 128, 256, 512, and 1024 px, including Retina variants where required.

The app bundle must reference the generated `.icns` or asset catalog output, and the About surface must use the lockup.

### Brandkit

Add `BRANDKIT.md` containing:

- Identity rationale and clear-space rules.
- Approved lockups and minimum sizes.
- Light and dark color tokens.
- Typography scale.
- Safety icon and color rules.
- Voice examples.
- Motion and reduced-motion rules.
- Misuse examples.

## Application Architecture

Keep `AppModel`, scanning, classification, deletion, reporting, and persistence behavior unchanged except where presentation needs additional derived state.

Add focused presentation types:

- `BrandTheme.swift`: semantic colors, spacing, radii, and animation durations.
- `BrandMarkView.swift`: scalable Sprout Lens vector view.
- `GrowthSummaryView.swift`: reclaimable-space summary and scan progress.
- `StorageMetricView.swift`: compact metric presentation.
- `PermissionBannerView.swift`: concise permission state with expandable steps.
- `CleanupCelebrationView.swift`: one-shot completion feedback.

Views receive model data through explicit inputs or the existing environment object. Brand components do not classify, scan, or delete files.

## Dashboard

Replace the generic title and equal metric grid with:

1. A branded title row:
   - Sprout Lens identity.
   - “Your Mac has room to grow.”
   - Last scan status and item count.
   - Rescan/cancel command.
2. A dominant Growth Summary:
   - Total cleanable bytes.
   - Contextual explanation based on amount.
   - Determinate scan progress when total work is known; otherwise staged indeterminate growth.
   - Restrained plant geometry rendered in SwiftUI.
3. Compact supporting metrics:
   - Available space.
   - Safe/generated storage.
   - Items requiring review.
4. “Quick wins” table:
   - Highest-confidence safe candidates first.
   - Existing selection and detail behavior.
5. Permission guidance:
   - Finder Blue banner.
   - Summary shown by default.
   - Setup steps available through disclosure.

The default 1040 × 680 window must show the growth summary and the beginning of Quick Wins without overlap.

## Sidebar

- Preserve native `List` source-list behavior.
- Add the Sprout Lens and CleanScope wordmark above destinations.
- Keep all destination labels visible at default width.
- Use Scope Forest for active selection only where native selection styling permits.
- Keep Start Scan and Cancel Scan as the primary bottom command.
- Keep Settings available both as a scene and the existing destination until a later information-architecture change is explicitly approved.

## Results

- Retain native `Table`, sorting, keyboard navigation, and checkboxes.
- Add a concise summary row with item count and total bytes.
- Use semantic category treatments with icon plus text.
- Safe selected rows receive Open Mint tint.
- Disabled risky rows remain readable and explain why selection is unavailable.
- Add Last Modified and a compact action menu when space allows.
- Move cleanup confirmation from a basic confirmation dialog to a review sheet containing:
  - Selected item count.
  - Total selected bytes.
  - Category breakdown.
  - Risk summary.
  - Explicit “Move Selected Items to Trash” action.

No permanent-delete control is added.

## Item Detail

Use a structured inspector-style sheet:

- Brand mark is not repeated.
- Safety state appears first.
- Full path, size, modified date, confidence, owner app/tool, reason, risk note, and recommended action remain visible.
- Commands: Open in Finder, Exclude, and Move to Trash when allowed.
- Destructive action remains visually subordinate until the item is reviewed.

If exclusion behavior is not yet fully implemented in `AppModel`, include it in the implementation plan rather than showing a decorative control.

## Cleanup Report

Replace the plain list with:

- Recovered-space result using rounded numeric typography.
- Available space before and after.
- A subtle one-shot leaf-settling animation.
- Clearly separated Deleted, Skipped, Permission-blocked, and Failed sections.
- Remaining recommendations and Rescan command.

Zero-count sections remain visible in compact form so the report is complete.

## Settings And Empty States

- Keep native grouped controls.
- Use brand color only for selected controls and informational callouts.
- Add a compact brand header to the dedicated Settings scene, not decorative cards.
- Empty states use a relevant SF Symbol or Sprout Lens fragment, practical next action, and friendly copy.
- No mascot or novelty jokes.

## Motion And Feedback

- Scan start: Growth Summary transitions into staged growth.
- Progressive result: update numbers without animating every row insertion.
- Scan completion: one gentle spring-free settle.
- Selection: 150 ms tint/check transition.
- Cleanup completion: one numeric roll and plant settle, under 600 ms total.
- Reduce Motion: crossfade or immediate update.
- Do not animate destructive confirmations.

## Accessibility

- Test light and dark appearances.
- Text contrast must meet WCAG AA.
- Safety states use icon, text, and color.
- VoiceOver labels describe category and whether the item can be selected.
- Dynamic text must not clip in sidebar, metric views, status tokens, or buttons.
- Keyboard commands and table navigation remain intact.

## Testing

### Automated

- Existing 30 core tests continue to pass.
- Add presentation tests where logic is extracted:
  - contextual reclaim-space copy.
  - category counts and selected byte totals.
  - scan progress stage calculation.
  - reduced-motion state selection.
- Build succeeds through `script/swiftpm.sh build`.

### Visual And Runtime

- Launch through `script/build_and_run.sh --verify`.
- Inspect default, minimum, and expanded window sizes.
- Inspect light and dark appearances.
- Inspect empty, scanning, completed, permission-limited, selection, confirmation, and cleanup-complete states.
- Verify no text truncation, overlap, blank surfaces, or unsafe selectable rows.
- Verify the production app icon appears in the Dock and app switcher.

## Non-Goals

- No points, levels, streaks, achievements, or confetti.
- No mascot.
- No new cleanup classifications.
- No automatic cleanup.
- No permanent deletion.
- No marketing website.
- No custom replacement for standard macOS tables, toggles, menus, or scrollbars.

## Acceptance Criteria

- The app is recognizably CleanScope from its Dock icon and first viewport.
- The dashboard feels colorful and rewarding while remaining work-focused.
- Safety labels and permission guidance are at least as clear as the current MVP.
- The native macOS interaction model is preserved.
- Existing core tests pass and added presentation logic is tested.
- Build, launch, light/dark inspection, and key UI states are verified.
