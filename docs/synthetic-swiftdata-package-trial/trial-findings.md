# Synthetic SwiftData Target — Package Integration Trial Findings

Third package-adoption trial. See
[`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions. Synthetic-target option per the test
plan, adopted after the [AmpFin attempt](../ampfin-package-trial/trial-scope.md)
pivoted mid-baseline.

## Overall outcome

**All four pre-committed questions answered in one session.**
8/8 tests passing in `examples/swiftdata-sample/`. Two clean
positive results on the deciding `fromEntity:` question, one
clean positive result on the `@ExternallyIdempotent` handler
shape, and **one P0 finding — the hellovapor-trial-documented
tuple-wrapping workaround does not compile, propagating a doc
error into the README's "Using with Fluent ORM" section.**

**API decision unlocked** — the `IdempotencyKey(fromEntity:)`
`CustomStringConvertible` constraint is **Fluent-specific**.
The recommended v0.1.0 post-release API move is to add a
dedicated Fluent-shaped constructor, not relax the global
constraint.

## Compilation log

| Attempt | Result | Friction |
|---|---|---|
| 1st `swift build` — library target | ✅ clean | `@Model` + `var id: String`, `@ExternallyIdempotent` on SwiftData-returning handler, plain reference `Identifiable` — all compile on first try. |
| 1st `swift test` run | ❌ 1 compile error | `#assertIdempotent` with tuple return: `type '(String, String, Bool)' cannot conform to 'Equatable'`. See Finding 4 below. |
| 2nd `swift test` run | ✅ 8/8 pass | After swapping the tuple for a dedicated Equatable struct. 0.017s total runtime. |

## Build-time delta

| State | Cold build | Units compiled |
|---|---|---|
| SwiftIdempotency alone (SwiftIdempotencyMacros + SwiftIdempotency) | — | 8 targets |
| `SwiftDataSample` umbrella (Library + SwiftIdempotency deps) | 5.56s | 9 targets (+3 source files from SwiftDataSample) |

Cold-build timing: **5.56s** for `swift build -c release` from
clean. No build-time anomaly; the SwiftData `@Model` macro
expansion adds ~0 perceptible overhead on a 3-file library.
Matches luka-vapor's ~0s-delta pattern.

## API friction log

### Finding 1 (positive — the deciding-question resolution): `IdempotencyKey(fromEntity:)` reaches SwiftData `@Model` cleanly

**Test:** `FromEntityReachabilityTests.swiftDataModel_withStringID_succeeds`

**Outcome:** ✅ compiles and runs. `IdempotencyKey(fromEntity:
offlineAlbum).rawValue == "album-42"`.

**Mechanism:** SwiftData's `@Model` macro declares
`PersistentModel: Identifiable`, but when the user supplies a
stored `var id: String`, that property satisfies the
`Identifiable.id` requirement — the synthesised
`persistentModelID: PersistentIdentifier` is a separate,
`PersistentIdentifier`-typed property (not the `Identifiable.id`).
Swift's `Identifiable` requirement resolution picks the
user-declared `String`-typed property; `String:
CustomStringConvertible` satisfies the `IdempotencyKey.init(fromEntity:)`
generic constraint.

**Consequence for the v0.1.0 API decision:** **the Optional-ID
pattern observed in Fluent is Fluent-specific.** SwiftData
adopters with the AmpFin-shape (user-declared non-Optional
`id: String`) reach `fromEntity:` without adapter code. The
v0.1.0 post-release API change is therefore tilted toward a
**dedicated Fluent-shaped constructor** (e.g.
`init(fromFluentID:)` operating on an Optional `UUID?`) rather
than a global `CustomStringConvertible` constraint relaxation
that would pay the "String(describing:) handles Optional"
ergonomic cost on every adopter.

### Finding 2 (positive): `IdempotencyKey(fromEntity:)` on plain reference-type `Identifiable` with `let id: String`

**Test:** `FromEntityReachabilityTests.referenceTypeIdentifiable_withStringID_succeeds`

**Outcome:** ✅ compiles and runs. Trivial case per prediction.

**Cross-type consistency** (`FromEntityReachabilityTests.crossTypeKeyConsistency`)
also passes: `IdempotencyKey(fromEntity: album)` ==
`IdempotencyKey(fromEntity: offlineAlbum)` when both have
`id == "album-42"`. The constructor hashes only the `id`; the
runtime type of the entity is irrelevant to the key. This is
what makes the `Album → OfflineAlbum` projection shape (the
AmpFin create-handler pattern) safe to key cross-representation.

### Finding 3 (positive): `@ExternallyIdempotent(by:)` on a SwiftData-returning handler

**Tests:** `DownloadHandlerTests.dedupGateHolds`,
`.rowCountInvariant`.

**Outcome:** ✅ compiles and runs. Two invocations with the
same `IdempotencyKey` return rows with matching
`persistentModelID`; `fetchCount` of `OfflineAlbum` stays at 1.

The handler signature is `(Album, IdempotencyKey, ModelContainer)
throws -> OfflineAlbum`. The macro expansion compiles cleanly
on this shape. Structurally identical to AmpFin's
`OfflineManager.download(album:)` modulo the injected
`ModelContainer` argument (AmpFin uses a shared
`PersistenceManager.shared.modelContainer`; the synthetic takes
a parameter for test isolation).

### Finding 4 (P0 doc error): `#assertIdempotent` tuple-wrapping workaround does not compile

**Evidence:** compile error on first `swift test` attempt.

```
error: type '(String, String, Bool)' cannot conform to 'Equatable'
note: only concrete types such as structs, enums and classes can
      conform to protocols
note: required by macro 'assertIdempotent' where
      'Result' = '(String, String, Bool)'
```

**Source of the claim:** the
[hellovapor trial findings](../hellovapor-package-trial/trial-findings.md)
at §"Pre-committed questions — answers" / question 1:

> *"The adopter workaround is to return a tuple of the Model's
> value fields from the closure: `(id, short, long)`. Tuples of
> Equatable types are synthesized-Equatable, so the macro accepts
> them."*

This claim was **never experimentally verified in the hellovapor
trial.** Inspecting the hellovapor migration.diff confirms: the
test labelled "Tuple-of-fields workaround exposes differing
UUIDs" uses `#expect(firstTuple != secondTuple)` on tuples
directly — which works because Swift synthesises `==` for
tuples of Equatable elements — but the test never wraps the
tuple in `#assertIdempotent { ... }`. The hellovapor tuple claim
propagated into the README's "Using with Fluent ORM" section
(lines 394-418, commit `0477b2f`) without a passing test
supporting it.

**Why tuples fail here:** Swift synthesises `==` for tuples
whose elements are `Equatable`, but **tuples do not conform to
the `Equatable` *protocol*.** Only named types (struct, class,
enum) can satisfy protocol constraints. The
`#assertIdempotent<Result: Equatable>` macro's generic
constraint on the closure's return type therefore rejects tuple
returns at type-check time. This is a long-standing Swift
language limitation (see Swift evolution SE-0283 for the
discussion; tuple-`Equatable` was proposed but not yet
implemented as of Swift 6.3).

**Correct workaround:** a **dedicated Equatable `struct`**
returned from the closure. Synthesised `Equatable` via the
struct-level conformance works — the constraint is satisfied
properly. The synthetic's `DownloadHandlerTests.assertIdempotentWithStructWorkaround`
uses this pattern and passes.

**Fix surface:**

| Artifact | Change |
|---|---|
| `README.md` §"Using with Fluent ORM" §"`#assertIdempotent` on Model returns needs a tuple" | Section rename + rewrite. Replace tuple example with dedicated-struct example. Add a compiler-error excerpt showing the tuple-return failure mode. |
| `docs/hellovapor-package-trial/trial-findings.md` §"Pre-committed questions — answers" / question 1 | Add a post-publication correction note pointing at this trial. Do not modify the original claim — preserve the archaeological trail. |

## Pre-committed questions — answers

### 1. `IdempotencyKey(fromEntity:)` on SwiftData `@Model` with user-declared `var id: String`

**Result:** ✅ compiles and produces `"album-42"` from `OfflineAlbum(id: "album-42", ...)`. The user-declared `var id: String` satisfies the `Identifiable.id` requirement; the synthesised `persistentModelID: PersistentIdentifier` is a separate property and is not in the `Identifiable.id` resolution path. See Finding 1.

### 2. `IdempotencyKey(fromEntity:)` on plain reference-type `Identifiable` with `let id: String`

**Result:** ✅ compiles and produces `"album-42"` trivially. Cross-type consistency with the `@Model` case also holds. See Finding 2.

### 3. `@ExternallyIdempotent(by:)` on a SwiftData-returning handler

**Result:** ✅ compiles on `throws -> OfflineAlbum`. Two-call dedup-gate test passes: identical `persistentModelID` after two invocations with the same key; row count stays at 1. See Finding 3.

### 4. `#assertIdempotent` with non-Equatable `@Model` return + tuple-wrapping workaround

**Result:** ❌ **tuple-wrapping workaround does not compile.** The hellovapor-trial claim that "tuples of Equatable types are synthesised-Equatable so the macro accepts them" is factually wrong. See Finding 4 for the evidence chain, the root cause (tuples have synthesised `==` but no `Equatable` protocol conformance), and the correct workaround (dedicated Equatable struct return).

## Linter parity check

Not applicable in a focused form — the synthetic is the
"adopter's" entire code base, so there is no "linter
road-test + package trial divergence" to compare against. The
functional correctness of `@ExternallyIdempotent(by:)` as a
first-class attribute annotation is verified by Finding 3.

## Comparison to predicted outcomes

| Prediction | Actual | Match? |
|---|---|---|
| Q1: SwiftData `@Model` `fromEntity:` succeeds cleanly | Confirmed | ✅ |
| Q2: Plain reference `Identifiable` succeeds trivially | Confirmed | ✅ |
| Q3: `@ExternallyIdempotent` compiles on SwiftData return | Confirmed | ✅ |
| Q4: Tuple workaround uncertainty resolves as "genuine uncertainty" | Resolved ❌ — workaround does not compile | ✅ (the *uncertainty* prediction was correct; the *outcome* was the worse of the two) |

## Implications for the v0.1.0 post-release API roadmap

1. **`IdempotencyKey(fromEntity:)` constraint relaxation: not
   needed globally.** Non-Fluent Identifiable types work
   out-of-the-box. Slot pivot:
   - **Previous plan:** "Drop the `CustomStringConvertible`
     constraint on `E.ID` (or add a Fluent-shaped constructor)
     so the path reaches Fluent Models without adapter code."
   - **New plan:** add a Fluent-shaped constructor ONLY. Keep
     the global generic constraint. Recommended shape:
     `init(fromFluentModel:)` or `init(fromFluentID:)`, scoped
     to `where Entity: FluentKit.Model` via a SwiftIdempotency-
     side extension that only compiles when the adopter imports
     FluentKit. Design details TBD.
2. **README §"Using with Fluent ORM" correction is a v0.1.0
   release blocker.** The current text recommends a
   non-compiling pattern. Fix before the SPI submission.
3. **Cross-adopter real-world shape coverage is unchanged.**
   Ten real-bug shapes, ten macro-surface fits — the synthetic
   verified that the `OfflineAlbum.download` shape (AmpFin's
   create-or-update handler) is an eleventh. Covered by the same
   `IdempotencyKey` / `@ExternallyIdempotent(by:)` surface.

## Trial completion status vs. test plan criteria

Per [`../package_adoption_test_plan.md`](../package_adoption_test_plan.md)
§"Completion criteria":

1. **"Three adopter integrations complete, each with a distinct
   shape"** — ✅ complete. luka-vapor (Redis+APNS, trivial-return
   pathology), hellovapor (Fluent, Optional UUID constraint
   findings), **this synthetic (SwiftData `@Model` + non-Fluent
   Identifiable, tuple-workaround correction)**. Three shapes,
   each surfacing findings the others couldn't.
2. **"No new P0 API-change requirements surface from an
   integration"** — ⚠️ partially met. This trial **did** surface
   a P0 finding: the tuple-wrapping workaround doc error. But
   the finding is a README correction, not an API shape change.
   The `IdempotencyKey(fromEntity:)` API itself is validated for
   v0.1.0 as-is.
3. **"Linter parity confirmed on at least one attribute-form-
   annotated handler"** — already met by luka-vapor and
   hellovapor.

**Conclusion:** the three-trial bar per the test plan is **met
for the v0.1.0 pre-release work, pending the README correction
from Finding 4.** Post-release trials against real SwiftData-
backed apps (TeymiaHabit, vreader, others on fresh toolchains)
are still valuable for external-adoption signal but not release-
blocking.
