# Round 8 Trial Findings

Spike to close round-7 Finding 4. Three candidates pre-committed; one landed.

## Result overview

| Candidate | Unit tests | Sample integration | Verdict |
|---|---|---|---|
| A — `@attached(member)` | ✅ 5/5 expansion tests green | ❌ Finding 4 reproduces | **Rejected** |
| B — `@attached(extension)` | ✅ 5/5 expansion tests green | ✅ 7/1 sample green, generated test passes | **Landed** |
| C — two-macro split | (not prototyped) | (not prototyped) | **Skipped** — B succeeded |

**Finding 4 is closed.** The consumer sample (`SwiftIdempotencyPhase7Sample`) runs end-to-end with `@IdempotencyTests` + `@Idempotent` inside a `@Suite struct` and the generated `testIdempotencyOfCurrentSystemStatus` in the test output.

## Red baseline

Step 0 of the spike: restored `@Idempotent` on a zero-arg `currentSystemStatus()` inside the sample's `@Suite struct`, ran `swift build`. Reproduced Finding 4's exact three-error signature from round 7:

```
error: cannot use instance member '$s21SampleWebhookAppTests0a11IntegrationD0V36testIdempotencyOfCurrentSystemStatus4TestfMp_24generator…' within property initializer; property initializers run before 'self' is available
error: properties with attribute @used must be static
error: properties with attribute @section must be static
```

Red baseline confirmed. Candidates are evaluated against this reproduction — "works" means the same file compiles and the test runs.

## Candidate A — `@attached(member)`

### Shape prototyped

Initial design (`@IdempotencyTests(for: [functionRef1, ...])` on a `@Suite struct` — member macro scans the argument list, emits one `@Test` per reference) hit two independent frictions *before* Finding 4 could even be measured:

### Friction 1 — bare function reference doesn't resolve

```
error: cannot find 'currentSystemStatus' in scope
```

**Root cause.** The attribute's argument (`for: [currentSystemStatus]`) is evaluated at attribute-evaluation context, which is *outside* the type body. `currentSystemStatus` is an instance method; the bare reference can't resolve without an instance.

### Friction 2 — qualifying with the type name produces a cycle

```
error: circular reference resolving attached macro 'IdempotencyTests'
```

**Root cause.** Qualifying with `Self.currentSystemStatus` fails (`Self` not in scope outside the type body); qualifying with the explicit type name (`SampleIntegrationTests.currentSystemStatus`) references a member of the exact type the attribute is attached to — a cycle the compiler can't resolve.

**Pivot.** Both frictions are structural to the "pass function references as attribute arguments" shape. Redesigned to the scan-members form: attribute takes no arguments, the member macro inspects the attached type's members directly, filtering for `@Idempotent`-marked zero-arg functions. Clean shape, one attribute, no argument parsing.

### Finding 4 reproduces under Candidate A

Integration check with the redesigned scan form:

```swift
@Suite
@IdempotencyTests
struct SampleIntegrationTests {
    @Idempotent
    func currentSystemStatus() -> Int { 200 }
}
```

Even with `@Idempotent`'s own peer emission temporarily neutralised (to isolate Candidate A's `@Test` output), `swift build` fails with the identical three-error signature as the red baseline. Changing the macro role from peer to member does **not** sidestep Swift Testing's internal property-initialiser issue.

**Lesson.** Finding 4 is not about the macro role. It's about Swift Testing's `@Test` macro being nested inside *any* outer macro that emits declarations into the struct's own member layout — peer and member both do.

### Verdict

Rejected. Unit-test-surface works cleanly (5/5 expansion tests); end-to-end integration hits the same wall.

## Candidate B — `@attached(extension)`

### Shape prototyped

Identical scan-members logic as Candidate A, but the macro emits an **extension** of the attached type containing the `@Test` methods, rather than emitting them as members of the type itself. Declared as `@attached(extension, names: arbitrary)`; same attribute name, same usage shape.

### Integration result

With the same sample as Candidate A:

```
Test testIdempotencyOfCurrentSystemStatus() passed after 0.001 seconds.
…
Test run with 7 tests in 1 suite passed after 0.001 seconds.
```

**No Finding 4 errors.** The sample goes from 6/1 (round-7 end state) to **7/1** — the seventh test is the one emitted by `@IdempotencyTests`'s extension-role expansion. Runtime result: pass.

### Why this works when peer and member don't

The emitted `@Test`s live in a separate `extension` decl, not inside the original struct's member block. Swift Testing's `@Test` macro's internal property synthesis (`@used`, `@section`, `generator`/`accessor`) lands in the extension context — past the point where the original struct's properties are initialised, so there's no "use instance member in property initialiser" cycle. Candidate A had the `@Test` expanding *into* the struct's members directly, which is what collides with the initialiser-ordering check.

### Verdict

**Landed.** Macros package: 37/5 tests green (down from round-7's 39/4 by net −2 because the old peer-emission unit tests were deleted and +4 extension-role tests added; see "Macros package delta" below). Sample: 7/1 green. Finding 4 closed for the `@IdempotencyTests` shape.

## Candidate C — two-macro split

Not prototyped. Plan's Fallback clause: "Spike budget overrun past 3 days: stop at whichever candidate is known-working. Defer the remaining candidates to a follow-on if their hypothesised ergonomic wins still matter. Don't keep exploring when a green path is in hand."

Candidate B satisfies the same ergonomic profile C aimed at (single-attribute adoption path). C's theoretical advantage — avoiding nested `@Test` emission entirely — is moot now that B has demonstrated nested `@Test` emission works cleanly from an extension role. Keeping C in reserve doesn't add evidence.

## Macros package delta

Files edited on branch `spike-peer-macro-redesign`:

| File | Change |
|---|---|
| `Sources/SwiftIdempotency/Attributes.swift` | Added `@IdempotencyTests` as `@attached(extension, names: arbitrary)`; reverted `@Idempotent` to `@attached(peer)` without `names: arbitrary` (marker-only since no names are emitted). |
| `Sources/SwiftIdempotency/AssertIdempotent.swift` | Added `__idempotencyInvokeTwice` — `async rethrows` helper invoked by the extension-role expansion. Absorbs sync/async/throws polymorphism. |
| `Sources/SwiftIdempotencyMacros/IdempotentMacro.swift` | Reduced `IdempotentMacro` to marker-only (returns `[]`). Doc comment records the round-8 redesign rationale. |
| `Sources/SwiftIdempotencyMacros/IdempotencyTestsMacro.swift` | **New.** `ExtensionMacro` implementation: scans attached type's member block, filters to `@Idempotent`-marked zero-arg functions, emits `@Test` per match inside a generated extension. |
| `Tests/SwiftIdempotencyTests/IdempotentPeerMacroTests.swift` | Rewritten. Old tests (9 expansion assertions against peer-emitted `@Test func`) deleted; 4 new "marker-only" assertions added. |
| `Tests/SwiftIdempotencyTests/IdempotencyTestsMacroTests.swift` | **New.** 5 expansion tests for the extension role. |

Net result: **37 tests across 5 suites green** at spike-end. Round-7 comparison was 39/4 — the net change is −2 tests overall but +1 suite (`IdempotencyTestsMacroTests`) and a materially cleaner surface.

## Sample package delta

`/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/Tests/SampleWebhookAppTests/SampleIntegrationTests.swift`:

- Added `@IdempotencyTests` to the `@Suite struct` declaration.
- Added `@Idempotent func currentSystemStatus() -> Int { 200 }` as the function the generated test exercises.
- Replaced the round-7 "@Idempotent is intentionally NOT demonstrated — see Finding 4" comment block with a round-8 "here's how `@IdempotencyTests` scans and emits" comment block.

Sample goes from 6/1 → 7/1, with `testIdempotencyOfCurrentSystemStatus` appearing in the test output as an `@IdempotencyTests`-emitted test.

## Deferred items

- **Parameterised-function test generation** still gated on `IdempotencyTestArgs` protocol design — orthogonal to Finding 4, orthogonal to role choice.
- **Conditional-compilation wrapping** for test-target-only test emission still impossible (Finding 3 — macros can't emit `import`). `@IdempotencyTests` requires the enclosing file to `import Testing`, same as round 7.
- **Candidate C's two-macro split** documented as unnecessary given B's success. Available as a follow-on if real adopters surface a use case B can't serve.
- **Linter attribute-recognition update** for `@IdempotencyTests`: one-line addition to `SwiftProjectLint`'s recognised-attribute set so the attribute doesn't look like an unknown decoration to the parser. Trivial; queued as a separate commit on the linter's main.

## What a clean round 8 unlocks

All four macro mechanisms now ship green:

| Mechanism | Round 7 | Round 8 |
|---|---|---|
| Attribute-form annotations | ✅ | ✅ |
| `IdempotencyKey` strong type | ✅ | ✅ |
| `#assertIdempotent` | ✅ | ✅ |
| `@Idempotent` test generation | ❌ deferred (Finding 4) | ✅ via `@IdempotencyTests` extension-role redesign |

The next unit of work per the round-7 retrospective's ordering — `strict_replayable` context tier (direction 2) — starts from a no-caveats base. Direction 3 (third-corpus validation) remains valuable but is no longer the mandatory path before declaring the macros package adoption-ready.
