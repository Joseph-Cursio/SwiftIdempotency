# Implementation Plan: Peer-Macro Redesign — Finding 4 Follow-on

First post-round-7 plan. Targets the one deferred mechanism from the round-7 trial: `@Idempotent`'s peer-macro test generation, blocked end-to-end by Finding 4 (Swift Testing's `@Test` expansion interacting poorly with macro-emitted peers at type-member scope). Companion to [`claude_phase_5_macros_plan.md`](claude_phase_5_macros_plan.md) and the [round-7 trial findings](phase5-round-7/trial-findings.md).

## Why this is the right next work

Round 7 shipped three of four macro mechanisms green (attribute-form annotations, `IdempotencyKey` strong typing, `#assertIdempotent`) and documented the fourth (`@Idempotent` peer-test expansion) as deferred with a concrete root cause. The retrospective's recommended path ordered three directions by evidence-per-day:

1. Peer-macro redesign addressing Finding 4 (2-3 days)
2. `strict_replayable` context tier (3-5 days, benefits from #1 closed)
3. Third-corpus validation (duplicates evidence until new mechanisms ship)

This plan is direction 1. Closing Finding 4 cleanly unblocks the strict-mode work and removes the one asterisk from the "macros shipped" claim.

## Scope of this plan

**In scope:**

- Spike investigation of three candidate redesigns (A, B, C below). Each gets a time-capped prototype in the `SwiftIdempotency` package and an end-to-end check against the existing `SwiftIdempotencyPhase7Sample/` consumer.
- Edits to `SwiftIdempotency`'s `Attributes.swift`, `IdempotentMacro.swift`, and the `IdempotentPeerMacroTests` suite to whichever candidate the spike selects.
- One round-8 validation in `SwiftIdempotencyPhase7Sample/` — the same local consumer that surfaced Finding 4 — now demonstrating the redesigned surface working end-to-end in a `@Suite struct` at type-member scope.
- Retrospective writeup under `docs/phase5-round-8/`.

**Out of scope with reasons:**

- **Parameterised-function test generation.** Still gated on the `IdempotencyTestArgs` protocol design, orthogonal to the scaffold question Finding 4 raised. Revisit after the scaffold is stable.
- **Conditional-compilation wrapping for the emitted peer.** Finding 3 (macros cannot emit `import`) is still live and not what this spike closes. The redesigned peer still assumes `import Testing` at file scope.
- **Linter-side changes.** Attribute-form recognition (`58d302d` in `SwiftProjectLint`) handles `@Idempotent` + any new companion attribute identically to the doc-comment form. If the spike lands a second attribute (`@IdempotentTestable`), the linter needs one line added to its recognised-attribute set — a trivial follow-up, not part of this spike's scope.
- **Migration from round-7's `names: arbitrary` shape to whatever the spike picks.** The macro package is pre-1.0 and has no external adopters yet. Breaking changes to the attribute surface are acceptable during this spike; semver starts after round 8 closes.
- **`strict_replayable` tier work.** Explicitly queued after this plan per the round-7 retrospective ordering.

## Design candidates

Four shapes worth evaluating. The spike prototypes the top three and picks based on measured behaviour in the consumer sample, not theory.

### Candidate A — `@attached(member)` on the enclosing `@Suite` type

Shape: re-attach the generation role from the function to the type. User writes a single `@IdempotencyTests` attribute on a `@Suite struct`; the macro scans the struct's stored `@Idempotent`-marked functions-by-reference (or a declared list) and emits `@Test` members for each.

```swift
@Suite
@IdempotencyTests(for: [pureMultiplier, currentSystemStatus])
struct IdempotencyChecks {}
```

**Pros.** Member-macro expansion happens inside a type where `self` *is* available, which is the exact context Swift Testing's `@Test` expansion expects. The "property initializer runs before self" symptom from Finding 4 may not fire. Test-target scope only — there's no global-scope variant to worry about (Finding 2 is sidestepped).

**Cons.** Reverts `@Idempotent` to marker-only — the function-level annotation no longer generates anything, so the ergonomic "annotate once, get a test for free" story changes to "annotate, then also list the function in an `@IdempotencyTests` suite." The function-reference argument (`for: [pureMultiplier]`) has to survive macro argument parsing — function references aren't always expressible where the macro runs (overloads, argument labels, generic parameters). This is the biggest open risk for Candidate A.

**Prototype goal.** Determine whether Swift Testing's `@Test`-emitted-inside-`@attached(member)`-expansion avoids Finding 4's symptom, and whether the function-reference argument parses reliably for at least zero-argument functions.

### Candidate B — `@attached(extension)` on the enclosing type

Shape: user writes `@IdempotencyTests` on the `@Suite struct`; the macro emits an extension of that struct containing the `@Test` methods. Structurally similar to Candidate A but the emitted `@Test`s live in an extension, not the original type body.

```swift
@Suite
@IdempotencyTests(for: [pureMultiplier])
struct IdempotencyChecks {}

// expands to:
extension IdempotencyChecks {
    @Test func testIdempotencyOfPureMultiplier() async throws { ... }
}
```

**Pros.** Extension scope is known-good for hand-written `@Test` methods in many Swift Testing codebases. Expansion placement is fully separated from the original type's stored-property layout, which removes one of the suspected vectors for Finding 4 (property initializer ordering during the original type's synthesis).

**Cons.** Same function-reference-argument risk as Candidate A. Extensions can't introduce new stored properties, but `@Test` methods don't need stored state, so this isn't a blocker — just worth confirming Swift Testing's `@used`/`@section` properties land on the extension decl cleanly.

**Prototype goal.** Compare to Candidate A — does putting the `@Test`s in an extension rather than the type body change whether Finding 4's symptom appears?

### Candidate C — Two-macro split with a `@Test`-free peer scaffold

Shape: `@Idempotent` becomes marker-only (no expansion). A second attribute `@IdempotentTestable` is added; when applied to a zero-argument function, it emits a **helper method** — not a `@Test` — that the user wraps in their own hand-written `@Test`.

```swift
// Attribute declarations (Attributes.swift):
@attached(peer)
public macro Idempotent() = ...

@attached(peer, names: arbitrary)
public macro IdempotentTestable() = ...

// User writes:
@Suite struct IdempotencyChecks {
    @Idempotent
    @IdempotentTestable
    func pureMultiplier() -> Int { 2 * 3 }

    @Test
    func testPureMultiplierIsIdempotent() async throws {
        try await __idempotencyCheckOfPureMultiplier()  // emitted by @IdempotentTestable
    }
}

// Macro emits:
func __idempotencyCheckOfPureMultiplier() async throws {
    let first = pureMultiplier()
    let second = pureMultiplier()
    #expect(first == second)
}
```

**Pros.** Hits the Finding 4 root cause directly. The emitted peer is a plain `func` with no attributes — no `@Test`, no `@used`, no `@section`. Swift Testing's macro expansion isn't nested inside another macro's expansion, so the internal-member initialization ordering bug can't fire. The hand-written `@Test` wrapper is trivially one line, and users opt in explicitly (addressing the retrospective's note about `@Idempotent` being too automatic for production test targets). `@Idempotent` remains a cheap marker the linter reads, which is its primary job.

**Cons.** Two attributes instead of one. "Users write a one-line `@Test` wrapper" is still manual work — the marginal value of the helper over `#assertIdempotent { pureMultiplier() }` is small when the function is zero-argument. The spike's integration step has to measure whether real adopters prefer `@IdempotentTestable` + helper over just `#assertIdempotent` inside a hand-written test.

**Prototype goal.** Confirm the `@Test`-free peer compiles cleanly at type-member scope and that the resulting hand-written-`@Test` + emitted-helper pairing doesn't hit any form of Finding 4's symptom. Then judge whether the ergonomics beat `#assertIdempotent`.

### Candidate D — Freestanding declaration macro `#IdempotencyTest(for:)`

Shape: `@Idempotent` stays marker-only. A freestanding declaration macro `#IdempotencyTest(for: funcName)` emits the `@Test` wrapper at its call site.

```swift
@Suite struct IdempotencyChecks {
    @Idempotent func pureMultiplier() -> Int { 6 }

    #IdempotencyTest(for: pureMultiplier)
}
```

**Not prototyped in this spike.** Freestanding-declaration macros emitting `@Test` may still hit Finding 4's expansion-ordering symptom, and there's no simple way to predict this without a test. The spike budget is 2-3 days; picking three candidates already consumes it. Candidate D goes into the follow-on list if A, B, and C all fail.

## Recommended pre-spike prediction

Based on the round-7 findings' root-cause reading — that Finding 4 is specifically about `@Test`'s internal property synthesis running at an unexpected point during nested macro expansion — **Candidate C is most likely to work** because it eliminates the nesting entirely (no `@Test` in the macro-emitted code). A and B remain worth prototyping because if either succeeds, the ergonomics are meaningfully better (one annotation instead of two). The spike's measurement decides, not this prediction.

## Phases

Three-day spike. Each candidate gets its own day; day 3 is integration + writeup.

### Phase 0 — Prep (≈0.5 hour)

- Verify the `SwiftIdempotencyPhase7Sample/` consumer still reproduces Finding 4 by restoring a single `@Idempotent` on `currentSystemStatus` inside the `@Suite struct` and confirming the same `properties with attribute @used must be static` error appears. **This is the red baseline.** Candidates A/B/C are each deemed "works" only if they produce a green consumer scan where the baseline is red.
- Create a scratch git branch `spike-peer-macro-redesign` on the `SwiftIdempotency` macros package. Not pushed until the spike lands.
- Reset the sample's test file to the round-7 end-state (`@Idempotent` removed, mechanism documented as deferred) for a clean starting point before each candidate's prototype.

**Acceptance:** baseline confirmed red; branch created; sample reset.

### Phase 1 — Day 1, Candidate A prototype (`@attached(member)`)

- Draft a new `@IdempotencyTests(for:)` macro in `Attributes.swift` using `@attached(member, names: arbitrary)`. Argument: `[Any]` or a variadic function-reference position; whichever the SwiftSyntax argument parsing accepts cleanly for at least zero-argument function references.
- Implement the member macro in `SwiftIdempotencyMacros/IdempotentMacro.swift` (or a new file `IdempotencyTestsMacro.swift` if the spike justifies the separation). The expansion inspects the argument list, emits one `@Test func testIdempotencyOf<Name>() async throws` per listed function, each of which calls the referenced function twice and `#expect`s equality.
- Add expansion tests to `IdempotentPeerMacroTests` (or a sibling `IdempotencyTestsMacroTests`) covering the zero-argument, Void-returning, async, and throws shapes.
- **Integration check:** apply `@IdempotencyTests(for: [currentSystemStatus])` in `SampleWebhookAppTests/SampleIntegrationTests.swift` inside its `@Suite struct` and run `swift test --package-path /Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample`. Record whether Finding 4's symptom reappears.

**Acceptance (per candidate, same pattern for Phases 1-3):**

- Expansion unit tests pass inside the macros package.
- Consumer-sample test target compiles without Finding 4's errors.
- Generated test runs and passes at runtime.

**Any acceptance failure is informative** — record the exact error text and move on to the next candidate. A failed candidate still contributes evidence to the writeup.

### Phase 2 — Day 2, Candidate B prototype (`@attached(extension)`)

- Duplicate the Candidate A shape but declare the macro as `@attached(extension, names: arbitrary)`. The expansion emits an `ExtensionDeclSyntax` extending the type the macro is attached to, with the `@Test` methods inside the extension.
- Expansion-test the three same effect-specifier shapes (zero-arg, async, throws).
- Integration check against the sample, same pattern as Phase 1.

**Acceptance:** as Phase 1.

### Phase 3 — Day 3 AM, Candidate C prototype (two-macro split)

- Add `@IdempotentTestable` to `Attributes.swift` as `@attached(peer, names: arbitrary)`.
- Strip `IdempotentMacro` back to marker-only (return `[]` unconditionally), matching the other three marker macros. Add `IdempotentTestableMacro` that does the double-invocation emission — but the emitted peer is **not** `@Test`-annotated. Emit a plain `func __idempotencyCheckOf<Name>() async throws` that does double-invocation + `#expect` equality.
- Expansion tests for the three effect-specifier shapes.
- Integration check in the sample: apply both `@Idempotent` and `@IdempotentTestable` to `currentSystemStatus`, add a hand-written one-line `@Test` wrapper that calls `try await __idempotencyCheckOfCurrentSystemStatus()`. Run the sample's tests.

**Acceptance:** as Phase 1.

### Phase 4 — Day 3 PM, decision + writeup (≈2 hours)

- **Decision rule.** Prefer A if it works (single attribute, closest to the original design). Fall to B if A fails and B works. Fall to C if A and B both fail. If all three fail, record the spike as "all three candidates blocked" and the follow-on is a deeper Swift Testing / compiler investigation (or upstream bug report) outside this plan's scope.
- Write `docs/phase5-round-8/trial-scope.md`, `trial-findings.md`, and `trial-retrospective.md`. The findings doc contains per-candidate pass/fail with error text on failures. The retrospective answers: "which candidate landed, why, and what's the next unit of work now that Finding 4 is closed?"
- Update `docs/idempotency-macros-analysis.md` Phase 5 section to reflect the redesigned surface. If Candidate C lands, document the two-macro split in the proposal's rule surface.
- Delete or keep the `SwiftIdempotencyPhase7Sample/` sample depending on whether it demonstrates the redesigned surface cleanly enough to retain as validation evidence.

**Acceptance:** writeup committed; scope in the proposal reflects the shipped redesign.

## Verification end-to-end

```
# Macros package unit tests — green at each phase end
cd /Users/joecursio/xcode_projects/SwiftIdempotencyPackage
swift package clean && swift test
# Expect: all phases' expansion tests green; previously-shipped tests still green.

# Consumer sample — Finding 4 baseline reproduces before, disappears after
cd /Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample
swift package clean && swift test
# Expect (phase 0): fails with Finding 4's error when @Idempotent is restored.
# Expect (phase 1/2/3 post-candidate-land): passes.

# Linter against the sample — no regression
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample \
  --categories idempotency
# Expect: 0 diagnostics, matching round 7's post-trial state.
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftIdempotencyPackage/Sources/SwiftIdempotency/Attributes.swift` — macro declarations; modified to add the redesigned attribute(s).
- `/Users/joecursio/xcode_projects/SwiftIdempotencyPackage/Sources/SwiftIdempotencyMacros/IdempotentMacro.swift` — macro implementation; modified or split depending on which candidate lands.
- `/Users/joecursio/xcode_projects/SwiftIdempotencyPackage/Tests/SwiftIdempotencyTests/` — new expansion tests per candidate prototype.
- `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/Tests/SampleWebhookAppTests/SampleIntegrationTests.swift` — red-baseline confirmation and post-candidate integration check.
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase5-round-8/` — new deliverables folder: `trial-scope.md`, `trial-findings.md`, `trial-retrospective.md`.
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/idempotency-macros-analysis.md` Phase 5 section — updated to reflect the redesigned surface after the spike closes.

## Fallback

- **All three candidates fail** (Finding 4's symptom appears in each consumer check): record the spike as an "all candidates blocked" finding. The next unit of work is a minimal-reproducer bug report to the Swift Testing repo, referencing this spike's per-candidate error traces. `@Idempotent` ships long-term as marker-only; users rely on `#assertIdempotent` for runtime checks. This is a defensible end state — three of four mechanisms work, one is known-blocked upstream, and there's a filed issue.
- **Candidate A works but the function-reference argument parsing is unreliable** (only zero-argument-zero-generic functions parse cleanly): ship A with a documented constraint. Document the reachable function shapes in `Attributes.swift`'s doc comment. Parameterised-function work is out of scope for this spike anyway.
- **Spike budget overrun past 3 days**: stop at whichever candidate is known-working. Defer the remaining candidates to a follow-on if their hypothesised ergonomic wins still matter. Don't keep exploring when a green path is in hand.
- **Swift Testing ships a fix upstream during the spike** that closes Finding 4 for the original round-7 design: revert `@Idempotent` to the round-7 shape, document the upstream fix as the resolution, and skip the redesign. Re-run the consumer sample to confirm.

## Total estimated effort

Phase 0: 0.5 hour • Phase 1: 1 day • Phase 2: 1 day • Phase 3: 0.5 day • Phase 4: 2 hours • **~2.5 days, budget 3 with slack.** Matches the round-7 retrospective's 2-3 day estimate. The heaviest lift is Phase 1 — it includes first-time integration of the `@attached(member)` role into this package and the first confirmation or rejection of the leading candidate.

## What a clean spike unlocks

If the spike lands Candidate A or B:
- `@Idempotent` as a single annotation does both linter-marking and test-generation, as originally designed. The round-7 asterisk is fully removed. The macros package ships as "four mechanisms, all green."
- The `strict_replayable` tier work (retrospective direction 2) starts from a no-caveats base.

If the spike lands Candidate C:
- Two-attribute surface: `@Idempotent` (marker) + `@IdempotentTestable` (opt-in test generation). Slightly noisier adoption story, but the scaffold is immune to the Swift Testing interaction that blocked round 7.
- The proposal's "annotation-as-shared-interoperability-surface" framing still holds — the linter reads `@Idempotent` exactly as before; `@IdempotentTestable` is the new opt-in for test scaffolding.

If all three candidates fail:
- The macros package ships long-term in the round-7 state (three green, one deferred) with a filed upstream issue. `@Idempotent` remains marker-only in practice, and `#assertIdempotent` is the recommended runtime-check path. This is the honest end state the round-7 retrospective flagged as defensible.

April 2026.
