# Synthetic SwiftData Target — Package Integration Trial Scope

Third package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
This is the **synthetic** target — option #3 in the test plan's
"Proposed first-trial targets" enumeration ("Fresh synthetic
target — build a small from-scratch adopter"). The trial was
originally scoped as a real-adopter trial against
[`rasmuslos/AmpFin`](../ampfin-package-trial/trial-scope.md); the
AmpFin attempt pivoted to this synthetic after ~30 min of
Swift-6.3 toolchain-drift friction on the AmpFin baseline that
did not inform the API question. See the AmpFin scope doc's
"Result: pivoted" section for the pivot rationale.

## Research question

> **On a non-Fluent Identifiable type — specifically a SwiftData
> `@Model` with user-declared `var id: String` and a plain
> reference-type `Identifiable` with `let id: String` — does
> `IdempotencyKey(fromEntity:)` reach its intended target without
> adopter-side adapter code? Does the answer invalidate or confirm
> the "Optional-ID pattern is Fluent-specific" hypothesis that
> would justify adding a Fluent-shaped constructor rather than
> relaxing the global `CustomStringConvertible` constraint on
> `E.ID`?**

## Pinned context

- **SwiftIdempotency tip:** `fff6f08` (post-Fluent-README section
  ship).
- **SwiftProjectLint tip:** `70f2d61` (post-slot-19 merge).
- **Target:** `examples/swiftdata-sample/` in this repo. No
  upstream; the synthetic is authored by this session to answer
  the deciding question cleanly.
- **Toolchain:** `swift-driver 1.148.6 / Apple Swift 6.3.1 /
  arm64-apple-macosx26.0`.

## Synthetic design

The synthetic mirrors two shapes observed in the AmpFin
attempt — the exact two types the deciding question pivots on:

1. **`SwiftDataSample.OfflineAlbum`** — a SwiftData `@Model
   final class` with user-declared `var id: String` marked
   `@Attribute(.unique)`. Mirrors `AmpFin.OfflineAlbumV2`. Stands
   for "real-adopter SwiftData persistence type with a
   String-keyed `Identifiable`."
2. **`SwiftDataSample.Album`** — a plain reference-type
   `Identifiable` with `let id: String`. Mirrors
   `AmpFin.AFFoundation.Item` / `Album` (a `Codable, Identifiable`
   base class). Stands for "non-ORM domain Identifiable."
3. **`SwiftDataSample.OfflineManager.download(...)`** —
   `@ExternallyIdempotent(by: "idempotencyKey")` handler that
   fetches-or-inserts an `OfflineAlbum` under a stable
   `IdempotencyKey`. Mirrors `AmpFin.OfflineManager.download(album:)`
   exactly (dedup-guarded-shape: `if let existing = ... else
   context.insert`).

The synthetic intentionally **does not** reproduce AmpFin's
Swift-5.9-era `let`-property `@Model` pattern — the sample
declares `var id: String` from the outset, sidestepping the
Swift 6.3 `@Model` + `let` regression surfaced during the AmpFin
attempt. The AmpFin scope doc records that regression separately;
it is adopter/toolchain friction, not a SwiftIdempotency API
question.

## Test plan

Two test suites in `Tests/SwiftDataSampleTests/`:

1. **`FromEntityReachabilityTests`** (the deciding question).
   - `IdempotencyKey(fromEntity:)` on plain `Album` — baseline
     positive control.
   - Same on inserted SwiftData `@Model` `OfflineAlbum` — the
     deciding case.
   - Same pre-insertion (never touches a `ModelContext`).
   - Cross-type consistency: `Album(id:)` and `OfflineAlbum(id:)`
     with equal `id` produce equal keys.
2. **`DownloadHandlerTests`** (handler-shape runtime check).
   - Two calls with the same key → same `persistentModelID`
     (dedup gate holds).
   - `fetchCount` invariant: row count stays at 1 after two
     invocations.
   - `#assertIdempotent` closure over the handler — tests the
     annotation-plus-macro interaction on a non-Equatable
     `@Model` return (via the workaround pattern).

## Scope commitment

- **Synthetic-only.** No real adopter fork; the trial deliverables
  are the package code plus findings. Per the test plan's
  synthetic-target caveats, "zero external-adoption signal." The
  trial answers the API-constraint question definitively; external
  adopter validation is a separate, lower-priority workstream
  (real adopter when one surfaces that (a) uses SwiftData and
  (b) is on current toolchain).
- **No `migration.diff`.** The package is authored fresh; the
  equivalent artifact is the `examples/swiftdata-sample/`
  directory itself.
- **In-memory SwiftData.** `ModelConfiguration(isStoredInMemoryOnly:
  true)` per test. No network, no disk.

## Pre-committed questions

1. **`IdempotencyKey(fromEntity:)` on a SwiftData `@Model` with
   user-declared `var id: String`: does it compile and produce a
   key over the user's String, or does SwiftData's
   `PersistentModel: Identifiable` synthesis route through
   `PersistentIdentifier` (which is NOT `CustomStringConvertible`,
   so would fail the constraint)?**
2. **`IdempotencyKey(fromEntity:)` on plain reference-type
   `Identifiable` with `let id: String`: clean success
   expected — any failure here invalidates the generalisation
   hypothesis entirely.**
3. **`@ExternallyIdempotent(by:)` on a SwiftData-returning
   handler: does the macro expansion compile on `throws ->
   OfflineAlbum`, and does the two-call dedup-gate test produce
   identical rows under the same key?**
4. **`#assertIdempotent` with a non-Equatable `@Model` return:
   does the hellovapor-trial-documented tuple-wrapping workaround
   actually work? The hellovapor trial claimed tuples of
   Equatable types are synthesised-Equatable and satisfy the
   `Result: Equatable` constraint. The claim was never
   experimentally verified in the hellovapor trial — this is the
   first trial that actually executes the pattern.**

## Predicted outcome

- **Q1 (SwiftData `@Model` `fromEntity:`):** positive result
  likely. SwiftData's `@Model` macro declares the `id: String` as
  the `Identifiable.id` requirement when the user supplies one;
  the synthesised `persistentModelID: PersistentIdentifier` is a
  separate property. `String: CustomStringConvertible` satisfies
  the constraint.
- **Q2 (reference Identifiable):** trivial success expected.
- **Q3 (handler + `@ExternallyIdempotent`):** clean success
  expected. The macro is `@attached(peer)` with no
  function-signature constraints.
- **Q4 (tuple workaround):** **genuinely uncertain.** Swift
  tuples have synthesised `==` for types where the elements are
  `Equatable`, but tuples do not themselves conform to the
  `Equatable` *protocol*. This is a long-standing limitation;
  the generic `<Result: Equatable>` constraint on `#assertIdempotent`
  may reject tuples at type-check time. If so, the hellovapor
  trial's claim is wrong and the README's "Using with Fluent ORM"
  section recommends a pattern that doesn't compile.

**Decision lever the trial turns:**

- If Q1 + Q2 succeed → **Fluent-specific API shape** is the
  right fix for the `fromEntity:` reachability gap. The v0.1.0
  API decision is: add a dedicated constructor
  (`init(fromFluentID:)` or `init(fromModelID:)`) rather than
  relax the generic `CustomStringConvertible` constraint.
- If Q4 fails → **P0 README / hellovapor-findings error**:
  the tuple-wrapping workaround claim is false. The README's
  "Using with Fluent ORM" section needs a correction to recommend
  a dedicated Equatable struct instead. The hellovapor
  trial-findings document also needs a correction note.
