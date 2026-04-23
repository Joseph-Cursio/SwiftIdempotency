# vreader — Package Integration Trial Scope

Fourth package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
First **iOS-app** trial (Xcode project, not SPM), filling the
external-adoption-signal gap left by the synthetic-swiftdata
trial. Specifically targets a current-toolchain SwiftData-backed
real adopter to validate the v0.2.0 macro surface against code
the SwiftIdempotency authors did not write.

## Research question

> **Does the SwiftIdempotency v0.2.0 macro surface work on a
> real-adopter-authored SwiftData `@Model` type integrated via
> Xcode Package Dependencies (not SPM)? And does the
> `IdempotencyKey(fromEntity:)` path — demonstrated cleanly on
> synthetic `@Model` types with `var id: String` — survive when
> the adopter names their business identifier something else (as
> is typical in iOS apps)?**

## Pinned context

- **SwiftIdempotency tip:** `0.2.0` (tag `b831332`, GitHub Release
  live). Resolved via Xcode Package Dependencies.
- **Upstream target:** `lllyys/vreader` @ `64dd940` (main,
  pushed 2026-04-04). iOS EPUB/PDF reader with annotations,
  SwiftData persistence, Swift 6.0 strict concurrency. XcodeGen
  project (`project.yml` + regeneratable `vreader.xcodeproj`).
- **Trial fork:** `Joseph-Cursio/vreader-idempotency-trial`.
- **Trial branch:** `package-integration-trial`, forked from
  upstream `main` @ `64dd940`.
- **Toolchain:** Xcode 26.4.1 / Swift 6.3.1 /
  arm64-apple-macosx26.0. iPhone 17 simulator on iOS 26.

## Why vreader specifically

Three candidate iOS SwiftData apps were considered (all
Xcode-only, requiring xcodebuild methodology):

| Candidate | Stars | Last push | Baseline build | Verdict |
|---|---|---|---|---|
| `amangeldybaiserkeev/TeymiaHabit` | 17 | 2026-04-19 | ❌ syntax error (`TODO` literal in `WeeklyHabitChart.swift:69`) | Blocked by adopter-side baseline bug; would require upstream source patch. |
| **`lllyys/vreader`** | 6 | 2026-04-04 | ✅ `BUILD SUCCEEDED` | Picked. |
| `gahntpo/SnippetBox-SwiftData` | 73 | 2023-10-10 | Not tested — last push predates Swift 6.3 `@Model` regression; high risk of @Model + let-property errors. | Passed over. |

vreader also has pre-existing `vreaderTests` target — saves
adding a new test target to the trial scope.

## Migration plan

**Scope:** test-target-only. No vreader main-target code changes.

1. Add `SwiftIdempotency` v0.2.0 as Xcode Package Dependency
   on the `vreaderTests` target.
2. Add one new Swift Testing file under
   `vreaderTests/Models/AnnotationNoteIdempotencyTests.swift`.
3. Cover three test shapes against vreader's real
   `AnnotationNote` `@Model` type:
   - `IdempotencyKey(fromAuditedString:)` over the user-declared
     `annotationId: UUID` business key — the canonical path.
   - Two-instances-same-UUID → same key (stability).
   - `#assertIdempotent` with an `AnnotationNoteProjection`
     Equatable struct workaround (the v0.2.0 README pattern).
4. Build + test via xcodebuild on iPhone 17 simulator.

No main-target migration because:
- AnnotationNote construction is distributed across view-model
  code — migrating a single handler would over-scope.
- The trial's deciding question is macro-surface-ergonomics, not
  handler-migration ergonomics (those were covered by the
  luka-vapor + hellovapor trials).
- "One handler, one test" per the test plan — testing on the
  real `@Model` satisfies the "one test" deliverable without
  dragging the full adopter handler path in.

## Test plan

Three tests in `vreaderTests/Models/AnnotationNoteIdempotencyTests.swift`:

1. **`fromAuditedString_producesStableKey`** — canonical path on
   real adopter code. Expected: pass, `key.rawValue ==
   annotation.annotationId.uuidString`.

2. **`fromAuditedString_sameUUID_sameKey`** — two AnnotationNote
   constructions with the same `annotationId` but different
   content produce equal keys. Exercises the content-drift-
   irrelevance guarantee of the init.

3. **`assertIdempotentOnAnnotationCreation`** — `#assertIdempotent`
   closure returning an `AnnotationNoteProjection` (dedicated
   Equatable struct per the v0.2.0 README correction, since
   AnnotationNote itself is a non-Equatable `@Model final class`).

## Scope commitment

- **One test file, three tests.** No other test files migrated;
  other AnnotationNote-adjacent test files (Book, Bookmark,
  Highlight, etc.) stay on their existing shape.
- **No upstream PR.** Non-contribution fork per the test plan.
- **XcodeGen kept as YAML record, pbxproj hand-edited.** The
  trial found that XcodeGen's regen doesn't round-trip vreader's
  pre-existing pbxproj (resource-dedup differs, causing
  duplicate-output build errors on regenerate); the hand-edit
  path is what shipped.

## Pre-committed questions

1. **Does SwiftIdempotency v0.2.0 compile cleanly in vreader's
   iOS-app dep graph?** First iOS-app integration; the package
   was designed for server-side Vapor trials. Risk: unexpected
   platform-guard or module-resolution friction.
2. **`IdempotencyKey(fromEntity: annotationNote)` —
   compile-success or compile-error?** vreader's AnnotationNote
   has `@Attribute(.unique) var annotationId: UUID`, NOT named
   `id`. The synthetic-swiftdata trial used `var id: String`
   which let `fromEntity:` work. Does the business-named-UUID
   pattern still reach `fromEntity:`?
3. **xcodebuild test loop viability.** `swift test` takes <1s
   on SPM trials. How expensive is the xcodebuild + simulator
   cycle? Acceptable dev UX or pushback point?
4. **Xcode Package Dependency integration via pbxproj edit.**
   How fragile is it? What's the failure mode if the edit is
   wrong?

## Predicted outcome

- **Q1 (SwiftIdempotency on iOS):** high-confidence clean. No
  iOS-specific gotchas expected. The macro surface is pure Swift
  (no Vapor/server-side deps) so iOS vs. macOS shouldn't matter.
- **Q2 (fromEntity: on business-named UUID):** **predicted
  compile error.** `Identifiable` synthesis requires a property
  named `id` or explicit `typealias ID = ...`. Absent both,
  SwiftData's `@Model` would provide a default via
  `PersistentIdentifier`, which isn't `CustomStringConvertible`.
  If this prediction holds, it's a **new finding beyond the
  synthetic trial**: real iOS adopters with business-named UUIDs
  don't reach `fromEntity:` without explicit `typealias ID =
  UUID; var id: UUID { annotationId }` boilerplate.
- **Q3 (xcodebuild test loop):** ~30-60s per cycle (simulator
  boot + build + test). Heavier than `swift test`, but workable.
- **Q4 (pbxproj edit):** fragile — any wrong hex ID or missing
  section breaks the project. Documented patching path will be
  the trial's primary ergonomic-cost finding.

## Scope boundaries

- **Not tested:** `SwiftIdempotencyFluent` integration (vreader
  doesn't use Fluent, and the v0.2.0 release already validated
  Fluent via the hellovapor re-run).
- **Not tested:** `@ExternallyIdempotent(by:)` on a vreader
  handler. The trial focuses on `IdempotencyKey` construction
  and `#assertIdempotent` ergonomics; handler-annotation
  integration was covered by luka-vapor/hellovapor.
- **Not tested:** SwiftProjectLint scan on the migrated code.
  SwiftData-specific linter rules (if any) are a separate
  slice; no cross-framework evidence yet.
