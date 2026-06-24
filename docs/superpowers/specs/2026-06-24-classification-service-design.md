# Classification Service Design

## Goal

Implement a conservative first-pass `ClassificationService` that translates
`CLEANING_RULES.md`, `SAFETY_RULES.md`, and `DATA_STRUCTURE.md` into typed,
inspectable rules with representative fixtures and regression tests.

## Scope

The classifier accepts file-system metadata through `ClassifiedItemInput` and
returns a complete `ScanResult`. This pass covers:

- known cache and generated-data locations;
- Downloads items older than 90 days;
- Docker volumes;
- known and unknown Application Support folders;
- cloud-synced folders;
- source-code directories and repositories.

It does not inspect file contents, query installed applications, load external
rule files, or delete anything.

## Architecture

`ClassificationService` evaluates an ordered catalog of typed rules. Each rule
contains a stable identifier, display name, typed matcher, safety category,
confidence, explanation, risk note, and optional app/tool ownership metadata.
Matchers support path components, exact item names, file extensions, folder
context, age, and combinations of those conditions.

The service collects every matching rule and selects the most cautious category
using the documented priority:

1. `do_not_bulk_delete`
2. `delete_if_app_unused`
3. `probably_unused`
4. `safe_to_delete`

Within the winning category, higher-confidence and more-specific rules win so
the returned explanation describes the strongest relevant match. An unknown
item falls back to low-confidence `do_not_bulk_delete`.

The built-in catalog remains Swift code for compile-time checking and simple
review. External JSON configuration is deferred until rules need to change
independently of an app release.

## Rule Behavior

### Safe caches and generated data

Known cache, temporary, log, and generated build locations are
`safe_to_delete`. Examples include `~/Library/Caches`, Xcode `DerivedData`,
`.next`, `.dart_tool`, `__pycache__`, and Rust `target`. Source-code protection
and cloud-folder protection take precedence when both match.

### Old Downloads

A file or folder directly or recursively inside `~/Downloads` becomes
`probably_unused` when its modification date is at least 90 days before the
classification reference date. Recent Downloads remain conservative unless a
more specific rule applies. Installer and archive extensions may explain the
match but do not bypass the 90-day requirement.

The service accepts an injectable reference date so age tests are deterministic.
Age never overrides personal, cloud-synced, source-code, protected, or excluded
status.

### Docker volumes

Paths inside Docker volume storage are `delete_if_app_unused` with high
confidence, `Docker` ownership, and a warning that volumes may contain
persistent databases or application data. They are never directly deletable by
the classifier.

### Application Support

Unknown folders under `~/Library/Application Support` are
`delete_if_app_unused`. Known app-critical locations such as browser profiles,
password managers, messages, mail, and notes are `do_not_bulk_delete`.
Application Support content is only `safe_to_delete` when a narrower known
disposable cache/temp rule matches and no more cautious rule also matches.

### Cloud-synced folders

iCloud Drive, Google Drive, Dropbox, OneDrive, Box, and Creative Cloud Files
are `do_not_bulk_delete`, marked as synced, and cannot be deleted through the
classifier. This protection wins over generated folder names.

### Source code

Repository markers and source/project directories are `do_not_bulk_delete`.
Detection includes repository metadata such as `.git` and common project/source
markers. Generated descendants can only be marked safe when they are outside a
cloud-synced location and the input is the generated directory itself; a source
root is never classified as generated merely because it contains build output.

## Result Policy

`safe_to_delete` and `probably_unused` results use the Trash deletion method.
`delete_if_app_unused` and `do_not_bulk_delete` require manual review.
Protected or excluded inputs always have `canDelete == false` and
`deletionMethod == not_allowed`, without changing the informational category.

Every result includes a non-empty reason, risk note, recommended action,
normalized path, extension where applicable, hidden/synced/protected/excluded
flags, and optional owner metadata.

## Fixtures and Tests

Tests use a shared fixture catalog containing representative inputs and expected
categories for each required family. Deterministic dates are based on a fixed
reference date and include boundary cases immediately before, at, and after 90
days.

Coverage verifies:

- safe caches and generated folders;
- old versus recent Downloads;
- personal or synced age-priority invariants;
- Docker volume warnings and ownership;
- unknown and app-critical Application Support folders;
- cloud protection winning over generated-folder matches;
- source roots remaining protected while generated directories are safe;
- protected and excluded deletion behavior;
- unknown-item fallback;
- every built-in rule having stable, non-empty explanatory fields.

## Files

- Modify `Sources/CleanScopeCore/Models.swift` for typed matcher structures.
- Modify `Sources/CleanScopeCore/ClassificationService.swift` for the rule
  catalog and evaluator.
- Add `Tests/CleanScopeCoreTests/ClassificationFixtures.swift` for reusable
  fixtures.
- Modify `Tests/CleanScopeCoreTests/ClassificationServiceTests.swift` and
  `SafetyInvariantTests.swift` for behavioral and safety coverage.

