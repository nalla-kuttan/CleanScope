# Classification Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace embedded classification conditionals with a typed, inspectable rule catalog and fixture-driven coverage for the documented safety cases.

**Architecture:** Introduce a typed matcher tree on `ClassificationRule`, then have `ClassificationService` build a context, evaluate every built-in rule, and select the most cautious and most specific match. Keep time injectable for deterministic 90-day Downloads behavior and preserve conservative deletion policy.

**Tech Stack:** Swift 6 package, Foundation, Swift Testing.

---

### Task 1: Fixture-driven behavior tests

**Files:**
- Create: `Tests/CleanScopeCoreTests/ClassificationFixtures.swift`
- Modify: `Tests/CleanScopeCoreTests/ClassificationServiceTests.swift`
- Modify: `Tests/CleanScopeCoreTests/SafetyInvariantTests.swift`

- [x] **Step 1: Add shared fixtures**

Create a fixed reference date and fixtures for caches, generated folders, old and recent Downloads, Docker volumes, Application Support, cloud folders, source roots, and generated source descendants.

- [x] **Step 2: Add failing behavior tests**

Assert fixture category, confidence, owner metadata, synced state, deletion behavior, and the exact 90-day boundary. Assert that every built-in rule has a stable identifier and non-empty explanatory copy.

- [x] **Step 3: Run tests to verify RED**

Run:

```bash
./script/swiftpm.sh test --filter Classification
```

Expected: compilation or assertion failures because typed matchers, injectable time, and the public built-in rule catalog do not exist.

### Task 2: Typed rule model and evaluator

**Files:**
- Modify: `Sources/CleanScopeCore/Models.swift`
- Modify: `Sources/CleanScopeCore/ClassificationService.swift`

- [x] **Step 1: Define typed matching**

Add `ClassificationRule.Matcher` cases for path components, exact names, extensions, item types, age, and boolean composition. Add specificity, optional ownership metadata, and a stable explicit identifier to `ClassificationRule`.

- [x] **Step 2: Implement classification context**

Normalize path and path components, derive name, extension, hidden and synced state, and compute age using an injectable `now` closure.

- [x] **Step 3: Build the documented rule catalog**

Represent personal/app-critical data, cloud roots, source markers, caches/generated folders, old Downloads, Docker volumes, and Application Support as typed rules.

- [x] **Step 4: Select conservatively**

Evaluate all rules; sort first by category caution, then confidence, then specificity. Fall back to low-confidence `do_not_bulk_delete`. Keep risky categories manual-review-only and protected/excluded results not allowed.

- [x] **Step 5: Run focused tests to verify GREEN**

Run:

```bash
./script/swiftpm.sh test --filter Classification
./script/swiftpm.sh test --filter SafetyInvariant
```

Expected: all focused tests pass.

### Task 3: Full verification and commit

**Files:**
- Review all modified source and test files.

- [x] **Step 1: Format and inspect**

Run:

```bash
xcrun swift-format format --in-place Sources/CleanScopeCore/Models.swift Sources/CleanScopeCore/ClassificationService.swift Tests/CleanScopeCoreTests/ClassificationFixtures.swift Tests/CleanScopeCoreTests/ClassificationServiceTests.swift Tests/CleanScopeCoreTests/SafetyInvariantTests.swift
git diff --check
```

Expected: no formatting or whitespace errors.

- [x] **Step 2: Run complete package verification**

Run:

```bash
./script/swiftpm.sh test
./script/swiftpm.sh build
```

Expected: all tests pass and the package builds successfully.

- [x] **Step 3: Review requirements**

Confirm every requested fixture family is represented and safety-priority tests cover cloud folders, source code, Application Support, and Docker volumes.

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/CleanScopeCore/Models.swift Sources/CleanScopeCore/ClassificationService.swift Tests/CleanScopeCoreTests/ClassificationFixtures.swift Tests/CleanScopeCoreTests/ClassificationServiceTests.swift Tests/CleanScopeCoreTests/SafetyInvariantTests.swift docs/superpowers/plans/2026-06-24-classification-service.md
git commit -m "feat: implement typed classification rules"
```
