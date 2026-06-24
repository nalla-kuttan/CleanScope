# Bulk Selection and Ready-to-Delete Cache Design

## Goal

Make cleanup selection faster without weakening CleanScope’s safety model. Users can select all eligible visible results, extend a selection across a row range with Shift-click, and review a dedicated section containing only high-confidence cache files that can currently move to Trash.

## Scope

This change applies to result-list screens. It does not auto-select files, bypass the cleanup review sheet, permanently delete files, or broaden the classifier’s definition of safe data.

## Ready-to-Delete Cache Definition

An item belongs in the new section only when all of these conditions are true:

- `category == .safeToDelete`
- `confidence == .high`
- `canDelete == true`
- `isExcluded == false`
- the normalized path identifies cache data:
  - contains `/Library/Caches/`
  - contains `/.cache/`
  - contains a package-manager cache component such as `.npm`, `.yarn`, or `.pnpm-store`
  - contains the pip cache paths already recognized by the classifier

Logs, Trash contents, generic temporary folders, generated build folders, and DerivedData do not appear in this cache-only section even if they are high-confidence and safe to delete.

The cache predicate will live in the core presentation layer as a reusable, testable property or helper rather than being duplicated as view-only string matching.

## Navigation and Section

Add `Ready to Delete` as its own sidebar destination near `Safe Cleanup`, using a cache-oriented SF Symbol. The destination opens the existing results experience filtered by the cache predicate.

The screen title is `Ready to Delete`. Supporting text explains that the list contains high-confidence cache files that apps can recreate. The empty state says that no high-confidence cache files are currently ready, rather than implying the whole Mac is clean.

This section is a filtered view of the same scan results and selection state. An item selected here remains selected if the user navigates to another results section.

## Bulk Selection

### Select All Visible

The first table-column header becomes a tri-state selection control:

- unchecked when no eligible visible rows are selected
- checked when every eligible visible row is selected
- mixed when some eligible visible rows are selected

Activating it selects all eligible visible rows when the state is unchecked or mixed. Activating it again when checked deselects those visible rows. It affects only rows in the current filtered result set. Disabled, protected, or excluded rows are never added.

The control has an accessibility label that clearly describes selecting or deselecting all eligible visible items.

### Shift-Click Range Selection

The view tracks the most recently clicked eligible row as the range anchor. Shift-clicking another eligible row applies the target row’s new selected state across the inclusive range between the anchor and target, using the current visible sort order.

Ineligible rows inside the range remain unchanged. A normal click updates the anchor. If the previous anchor no longer exists in the visible results, Shift-click behaves like a normal click and establishes a new anchor.

Because SwiftUI’s standard `Toggle` does not expose modifier-key behavior reliably for this interaction, the checkbox cell will use a small button with native checkbox imagery and accessibility traits while preserving standard keyboard focus and activation.

## Selection Summary

When at least one item is selected globally, the results header shows a compact selection summary:

- selected item count
- combined selected size
- `Clear` action
- `Review Cleanup` primary action

`Clear` removes the whole cleanup selection, including selections made in other sections, so the displayed count and action always describe the actual review payload. The review sheet remains the mandatory confirmation step before moving files to Trash.

When nothing is selected, the header keeps the existing `Review Cleanup` action disabled and does not reserve unnecessary space for the summary.

## State and Components

`AppModel` gains focused selection operations:

- set selected state for one item
- select or deselect a supplied collection of eligible items
- clear selection
- compute selected count and bytes from current scan results

`ResultsView` owns the current range anchor because range behavior depends on the visible filtered order. `ResultsTable` receives the visible results and a range-selection callback. Shared helpers determine eligible visible IDs and header checkbox state.

Selection is pruned when a new scan starts and cleared after cleanup, preserving the current behavior.

## Safety and Error Handling

Every bulk operation rechecks `canDelete` and `isExcluded`; it does not trust only the filter that produced the screen. Cleanup still routes through `CleanupReviewSheet` and `DeletionService`.

If an item changes eligibility after selection, model operations exclude it from new bulk selections, and selected results used for review are restricted to currently deletable, non-excluded items.

The feature adds no automatic cleanup and no permanent deletion path.

## Testing

Core/model tests cover:

- cache predicate includes high-confidence deletable Library and package-manager caches
- cache predicate excludes logs, Trash, generated folders, protected caches, excluded caches, and lower-confidence items
- select-all selects only eligible visible results
- deselect-all affects only the supplied visible results
- clear selection removes all selected IDs
- selected count and byte total use currently valid selected results

View-level verification covers:

- unchecked, mixed, and checked header states
- Shift-click selects and deselects an inclusive range
- ineligible rows inside a range stay unchanged
- range anchor resets safely when filters change
- selection summary count and size update immediately
- `Ready to Delete` navigation and empty state
- cleanup review receives exactly the valid selected items
- keyboard focus, VoiceOver labels, light/dark appearance, and narrow window layout

## Acceptance Criteria

- A user can select or deselect every eligible row in the current result view with one control.
- A user can Shift-click to apply selection across a visible row range.
- A dedicated `Ready to Delete` section contains only high-confidence, currently deletable cache files.
- Cache files are not selected automatically.
- Bulk selection cannot include protected, excluded, or non-deletable items.
- Cleanup still requires the existing review and confirmation flow.
