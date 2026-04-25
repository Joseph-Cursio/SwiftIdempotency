# swift-property-based — Trial Findings

## TL;DR

**`swift-property-based` (PropertyBased v1.2.0) adopts cleanly into both
`SwiftProjectLint` and `SwiftIdempotency` as a test-target-only dependency,
with zero adopter-facing cost on either side.** Nine property tests were
added across the two repos (7 lattice-law tests + 2 idempotent-wrap
tests); all pass on first run. One real design finding on the lattice was
surfaced by the act of writing the properties, and one backlog item was
identified for full compatibility with PropertyBased's shrinker.

## Pinned context

- **Library:** [`x-sheep/swift-property-based`](https://github.com/x-sheep/swift-property-based) @ `1.2.0`.
- **Toolchain:** Swift 6.3.1 / Xcode 26.4.1 (2026-04-24).
- **SwiftProjectLint:** main @ `0ca8a12` (lattice laws + docstring note).
  - Dependency added to root `Package.swift`, scoped to `CoreTests` testTarget.
  - `swift-tools-version` was already `6.2` — no bump required.
- **SwiftIdempotency:** main @ `92ffaad` (PBT wrap pattern for `#assertIdempotent`).
  - Dependency added to `Package.swift`, scoped to `SwiftIdempotencyTests` testTarget.
  - `swift-tools-version` stayed at `5.10` — SwiftPM 6.3.1 accepts the dep without a bump, so no adopter impact.

## Phase 1 — lattice laws in SwiftProjectLint

**Target:** `UpwardEffectInferrer.leastUpperBound(of:)` — the effect-lattice
join used by upward inference. Not named `join`, but structurally the
same operation over the four-element lattice
`observational < idempotent < externallyIdempotent < nonIdempotent`.

**File:** `Tests/CoreTests/Idempotency/LatticeLawsTests.swift` (114 lines,
7 `@Test` properties + 1 edge case).

### Laws asserted

| Property | Shape | Status |
|---|---|---|
| Single-element identity | `lub([a]) == a` | ✅ |
| Duplication idempotence | `lub([a, a]) == a` | ✅ |
| Commutativity (rank) | `rank(lub([a,b])) == rank(lub([b,a]))` | ✅ |
| Associativity (rank) | `rank(lub([a, lub([b,c])])) == rank(lub([lub([a,b]), c]))` | ✅ |
| Upper bound | `rank(lub([a,b])) ≥ rank(a)` and `≥ rank(b)` | ✅ |
| Membership (rank) | `rank(lub([a,b])) ∈ {rank(a), rank(b)}` | ✅ |
| Empty input | `lub([]) == nil` | ✅ |

Default 100 iterations per property × 4-element lattice = 700 total
invocations. Suite runs in 3 ms.

### Real design finding

The `leastUpperBound` implementation uses strict `>` rank comparison, so
when two inputs share the highest rank the **first** one in iteration
order wins. This matters for `externallyIdempotent(keyParameter:)`: two
values with different `keyParameter` strings sit at the same lattice
position, and `lub` returns whichever appeared first. The result is
rank-correct but **not `Equatable`-symmetric across input orderings** when
same-rank duplicates carry different associated values.

Surfaced by writing the commutativity property. Resolved in two ways:

1. The test generator emits `externallyIdempotent` only with
   `keyParameter: nil` as a canonical form, keeping `Equatable`-level
   properties clean.
2. Commutativity and associativity are asserted at rank level rather
   than effect-equality level, matching the implementation's actual
   guarantee.

Docstring on `leastUpperBound` updated in commit `0ca8a12` to call out
the tie-break behaviour — preserves the finding at the code level, not
just in test design.

## Phase 2 — property-based `#assertIdempotent` wrap pattern

**Target:** `#assertIdempotent` from `SwiftIdempotency`, composed with
`propertyCheck` from `PropertyBased`.

**File:** `Tests/SwiftIdempotencyTests/PropertyBasedAssertIdempotentTests.swift`
(65 lines, 2 `@Test` properties).

### The wrap pattern

```swift
await propertyCheck(input: Gen.int(in: -100...100)) { value in
    _ = #assertIdempotent {
        insertSortedUnique(value, into: [1, 5, 10, 15])
    }
}
```

The macro runs the operation twice per iteration and asserts observable
equivalence, so a 100-iteration `propertyCheck` produces ~200 invocations
of the operation under test with paired `Equatable` checks.

### Properties demonstrated

| Property | Shape | Status |
|---|---|---|
| sync — `insertSortedUnique` is idempotent across generated ints | pure operation | ✅ |
| async — actor-isolated `UniqueBag.insert` is idempotent across generated ints | stateful operation | ✅ |

Suite runs in 2 ms. Full repo test suite remains green: 76 tests / 9
suites (was 74 / 8 — exactly +2 / +1 from the baseline).

### Tools-version finding

**SwiftPM accepted `swift-property-based` (which itself declares
`swift-tools-version: 6.2`) as a dependency of a parent package still
declaring `swift-tools-version: 5.10`.** This was not the assumed cost
from pre-flight — Phase 0 expected a tools-version bump would be
required, which would have propagated to every SwiftIdempotency adopter.
Instead, adopter impact is zero: PropertyBased is scoped to the internal
test target, and SwiftPM 6.3.1 handles the mixed-manifest-version graph
cleanly.

### Known limitation — shrinker composition

`#assertIdempotent` fails via `precondition`, which terminates the test
process. On a failing `propertyCheck` iteration the process dies before
PropertyBased's shrinker can minimise the counter-example. Users of the
wrap pattern get the raw randomised input on failure rather than a
shrunk one.

**Not experimentally verified** — no deliberately-failing property was
written. Claim rests on reading `__idempotencyAssertRunTwice`'s source
and the precondition semantics.

## Backlog

**Phase 3 (queued, not scoped):** Add a non-fatal failure mode to
`#assertIdempotent`, mirroring the existing `assertIdempotentEffects`
`failureMode: .issueRecord` surface. Would unlock PropertyBased's
shrinker for the wrap pattern for free. Scope is small — `AssertIdempotent.swift`
+ `AssertIdempotentMacro.swift` + the two test files. Flagged in project
memory so future sessions can pick it up cleanly.

## Recipe for future adoption

If adding a new PropertyBased-based test file in either repo:

1. **Import:** `import Testing; import PropertyBased` (plus whatever
   repo-internal modules are needed).
2. **Finite enum generator:** use `Gen<T>.oneOf(Gen.always(.a), Gen.always(.b), …)`.
   `Gen<T>.case` works for `CaseIterable` enums without associated
   values; `oneOf + always` is the workaround when associated values
   rule out `CaseIterable`.
3. **Range generator:** `Gen.int(in: 0...100)` and friends are provided
   for common stdlib types.
4. **Multi-input property:** `propertyCheck(input: g0, g1) { a, b in … }`
   — variadic up to 5 generators, `async throws` body.
5. **Swift Testing integration:** assert inside the body with
   `#expect(...)` as usual. Default iteration count is 100;
   override via `propertyCheck(count: N, input: g) { ... }`.

## Footer

Findings recorded 2026-04-24. Both repo test suites green at time of
writing.
