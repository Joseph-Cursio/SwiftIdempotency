# Round 2 Trial Findings — Swift Idempotency Linter vs. `hummingbird-project/hummingbird` 2.22.0

Results from executing the post-follow-up Phase 1 linter against a second real codebase. Scope was fixed in advance by [`trial-scope.md`](trial-scope.md). This report is strictly descriptive; the retrospective is in [`trial-retrospective.md`](trial-retrospective.md); Open-Issue amendments to the proposal (if any) are linked at the end.

## Test vehicle

- **Linter:** `SwiftProjectLint` branch `idempotency-trial-round-2`, forked from `idempotency-trial @ 20c6583` with no rule changes (measurement-only).
- **Target:** `hummingbird-project/hummingbird` 2.22.0, SHA `a2ed0a0294de56e18ba55344eafc801a7a385a90`, Swift-tools-version 6.1.
- **Demo package:** `/Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo/`.
- **Annotation experiments:** local-only branch `trial-annotation-local` in the Hummingbird clone. Not pushed.
- **Baseline test run:** 1844 tests in 251 suites passed before any changes.

## Corpus shape

- 137 Swift source files across 7 modules (`Hummingbird`, `HummingbirdCore`, `HummingbirdHTTP2`, `HummingbirdRouter`, `HummingbirdTesting`, `HummingbirdTLS`, `PerformanceTest`)
- 16,481 total lines in `Sources/`
- **2 `actor`-typed declarations**: `HummingbirdCore/Server/Server.swift`, `Hummingbird/Storage/MemoryPersistDriver.swift`
- 83 `@Sendable` / `NIOLockedValueBox` / `Mutex` occurrences across 33 files — Hummingbird leans on structured concurrency + value-type isolation rather than actor-based state isolation
- 21 `logger.info/debug/warning/error/notice/trace` call sites

The actor sparsity is deliberate and material. It drives the Run B result below.

## Phase 3 — positive demonstration (before / after)

Demo package: one Hummingbird-shaped route handler annotated `/// @lint.context replayable`. New for round 2: the handler always carries a `logger.info(...)` call (stubbed via a locally-declared `DemoLogger` whose `info` is declared `@lint.effect observational`). The assertion is that the observational call must **not** produce a diagnostic regardless of which handler state is active.

### Before state — `orderService.create(order)` (`@lint.effect non_idempotent`)

```
Sources/Demo/OrderRoute.swift:25: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'handle' is declared `@lint.context replayable` but calls 'create', which is declared `@lint.effect non_idempotent`.
  suggestion: Replace 'create' with an idempotent alternative, or route the call through a deduplication guard or idempotency-key mechanism.

Found 1 issue (1 error)
```
CLI exit code: `2`. One diagnostic on line 25 (`orderService.create`), **zero on line 24** (`logger.info`). ✅ Observational tier correctly absorbs the log call.

### After state — `orderService.upsert(order)` (`@lint.effect idempotent`)

```
No issues found.
```
CLI exit code: `0`. Both the observational log call and the idempotent upsert are silent.

## Phase 4 Run A — annotation-gated rules on un-annotated Hummingbird

```
$ swift run CLI /Users/joecursio/xcode_projects/hummingbird --categories idempotency
No issues found.
```
CLI exit: `0`. Zero diagnostics, as expected. The `EffectAnnotationParser` did not misread any of Hummingbird's 137 richly-documented files as an annotation. Parser cleanliness holds on a second, larger corpus.

## Phase 4 Run B — structural `actorReentrancy` on Hummingbird

```
$ swift run CLI /Users/joecursio/xcode_projects/hummingbird --categories codeQuality --threshold warning
…
Found 414 issues (10 errors, 97 warnings, 307 info)
```

Of those 414 diagnostics, **zero are `actorReentrancy`**. `grep -i "actor reentrancy\|actorReentrancy"` on the full transcript returns no matches. The 414 diagnostics are from other codeQuality rules (`forceUnwrap`, `couldBePrivate`, `missingCancellationCheck`, `catchWithoutHandling`, etc.) unrelated to this trial.

### Triage

| Bucket | Count | Notes |
|---|---|---|
| A — true positive | 0 | |
| B — AST match, design-intent mismatch | 0 | |
| C — rule bug | 0 | |

### Interpretation

This is **not** a false negative. Hummingbird has only 2 actors in 137 files, and inspection confirms neither contains the structural pattern (guard-on-stored-property → await → mutating-write-without-intervening-write) that the rule targets.

Of particular note: `HummingbirdCore/Server/Server.swift`'s `run()` method independently uses the proposal's canonical fix pattern —

```swift
case .initial(let childChannelSetup, let configuration, let onServerRunning):
    self.state = .starting                               // ← claim the slot BEFORE the await
    do {
        let (asyncChannel, quiescingHelper) = try await self.makeServer(…)
        // We have to check our state again since we just awaited on the line above
        switch self.state {
        case .starting:
            self.state = .running(…)
```

The comment `// We have to check our state again since we just awaited on the line above` is almost verbatim the reasoning the proposal gives for introducing `actorReentrancyIdempotencyHazard`. Hummingbird's maintainers already apply this pattern deliberately. The rule correctly reads this as non-hazardous.

`MemoryPersistDriver` is similarly clean: its `create(key:value:expires:)` has a guard→write sequence (`guard self.values[key] == nil else { throw … }; self.values[key] = …`) but **no intervening await** between the guard and the write. No suspension, no reentrancy window, no diagnostic — working as specified.

### Comparison to round 1

Round 1's headline metric was "3 findings / 1 critical stateful-actor file," all Bucket B (state-machine invariant guards on `LambdaRuntimeClient.lambdaState`). The round-2 result says that metric **does not generalize as-is** — not because the rule is worse on Hummingbird, but because the architectural precondition (heavy actor use for mutable state) doesn't hold on Hummingbird. The rule's value-per-codebase is architecture-dependent: `@Sendable`-first codebases produce near-zero signal even when critical.

This is an important adoption-guidance finding, documented here so it is not lost: **`actorReentrancy` is highest-value on codebases that isolate mutable state in actors**. On codebases that use structured concurrency with lock-protected value types, it will produce few findings whether or not those codebases would benefit from idempotency analysis.

## Phase 4 Run C — cross-file resolution on annotated handler

**Two runs under this header**, because the first attempt exposed a finding worth recording separately.

### Run C.1 — annotate a protocol-declared method (`MemoryPersistDriver.create`)

On branch `trial-annotation-local`: annotated `MemoryPersistDriver.create(key:value:expires:)` as `@lint.effect non_idempotent` (correct — it throws `PersistError.duplicate` on replay). Added a new file `Sources/Hummingbird/Storage/TrialReplayableHandler.swift` containing a `@lint.context replayable` function that calls `driver.create(...)`.

**Expected:** 1 diagnostic via cross-file resolution (OI-4).
**Observed:** 0 diagnostics.

```
$ swift run CLI /Users/joecursio/xcode_projects/hummingbird --categories idempotency
No issues found.
```

### Why: protocol-method bare-name collision

`create` is declared three times in `Sources/Hummingbird/Storage/`:

- `Sources/Hummingbird/Storage/PersistDriver.swift:22` — protocol requirement `create<Object: Codable & Sendable>(key:value:expires:)`
- `Sources/Hummingbird/Storage/PersistDriver.swift:53` — protocol extension default `create(key:value:)` (two-arg variant)
- `Sources/Hummingbird/Storage/MemoryPersistDriver.swift:58` — concrete implementation `create(key:value:expires:)` (the one annotated)

The OI-4 follow-up ships a **conservative collision policy**: the bare-name symbol table withdraws any entry that collides. All three `create` declarations collide on bare name, the entry is withdrawn, and cross-file resolution skips the call. This is working-as-specified.

This is the **round-2 finding** most worth recording: **the conservative collision policy creates a systematic visibility gap on protocol-oriented APIs.** Every Hummingbird storage method (`create`, `set`, `get`, `remove`, `run`, `shutdown`) has exactly this shape — protocol requirement + extension default + concrete implementation, all sharing a bare name. A real team adopting Phase 1 would need to either:

1. Accept that protocol-method annotations don't resolve cross-file
2. Wait for a signature-aware collision policy (match on `(name, arity, first_argument_label)` instead of `name` alone)

This feeds a proposed refinement to OI-4 — see [proposal amendments](#proposal-amendments) below.

### Run C.2 — annotate unique-name free functions

To isolate whether cross-file resolution itself is working, added two new files with unique, non-overloaded names:

- `Sources/Hummingbird/Storage/TrialCallee.swift`: `public func trialPersistSideEffect(key:)` declared `@lint.effect non_idempotent`
- `Sources/Hummingbird/Storage/TrialReplayableHandler.swift` (edited): `public func trialReplayableHandler(key:)` declared `@lint.context replayable`, calling `trialPersistSideEffect(key:)`

**Expected:** 1 diagnostic.
**Observed:** 1 diagnostic.

```
Sources/Hummingbird/Storage/TrialReplayableHandler.swift:17: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'trialReplayableHandler' is declared `@lint.context replayable` but calls 'trialPersistSideEffect', which is declared `@lint.effect non_idempotent`.
  suggestion: Replace 'trialPersistSideEffect' with an idempotent alternative, or route the call through a deduplication guard or idempotency-key mechanism.

Found 1 issue (1 error)
```

Cross-file resolution mechanism works. The C.1 zero-result was entirely attributable to the collision policy, not a bug.

## Phase 4 Run D — `observational` tier under load

On the same `trial-annotation-local` branch, added `Sources/Hummingbird/Storage/TrialObservational.swift` declaring five observational primitives (`trialLog`, `trialLogDebug`, `trialLogWarning`, `trialMetricCounter`, `trialMetricGauge`) and five `@lint.context replayable` callers:

| Caller | Observational calls | Non-idempotent call | Expected diagnostics |
|---|---|---|---|
| `replayable1_LoggingHeavy` | 6 | 0 | 0 |
| `replayable2_WithWarning` | 3 | 0 | 0 |
| `replayable3_MetricsOnly` | 3 | 0 | 0 |
| `replayable4_ChainedLogging` | 5 | 0 | 0 |
| `replayable5_ShouldFlag` | 3 | 1 (`trialPersistSideEffect`) | 1 |
| **Total** | **20 observational call sites** | **1 non-idempotent edge** | **1** |

Run output:

```
Sources/Hummingbird/Storage/TrialObservational.swift:77: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'replayable5_ShouldFlag' is declared `@lint.context replayable` but calls 'trialPersistSideEffect', which is declared `@lint.effect non_idempotent`.
Sources/Hummingbird/Storage/TrialReplayableHandler.swift:17: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'trialReplayableHandler' is declared `@lint.context replayable` but calls 'trialPersistSideEffect', which is declared `@lint.effect non_idempotent`.

Found 2 issues (2 errors)
```

Two diagnostics. One is the Run D assertion (`replayable5_ShouldFlag → trialPersistSideEffect`); the other is Run C.2's `trialReplayableHandler → trialPersistSideEffect` edge still present on the same branch. Both correct. **Zero diagnostics from any of the 20 observational call sites.**

This is decisive. The shipped `observational` tier (OI-5 follow-up) absorbs high-volume logging and metrics calls inside replayable contexts without producing false positives. Round 1 could not test this — the tier hadn't shipped yet. Round 2 confirms the tier works as designed at corpus-realistic volume.

## Summary

| Run | Expected | Observed | Pass? |
|---|---|---|---|
| Phase 3 before | 1 `nonIdempotentInRetryContext`, 0 observational | 1 error on `create`, 0 on `logger.info` | ✅ |
| Phase 3 after | 0 | 0 | ✅ |
| Run A (idempotency / un-annotated) | 0 | 0 | ✅ |
| Run B (actorReentrancy) | sparse (architectural prediction) | 0 | ✅ (working-as-specified) |
| Run C.1 (protocol-method cross-file) | 1 if resolved | 0 (collision-withdrawn) | ⚠️ finding, not bug |
| Run C.2 (unique-name cross-file) | 1 | 1 | ✅ |
| Run D (observational at volume) | 1 (single non-idem edge) | 2 (one + Run C.2 carryover) | ✅ (0 false positives on 20 obs calls) |

## Delta vs. round 1

| Dimension | Round 1 (Lambda runtime) | Round 2 (Hummingbird) | Verdict |
|---|---|---|---|
| Files | ~100 | 137 | — |
| Actor count | several, incl. `LambdaRuntimeClient` state machine | 2 (`Server`, `MemoryPersistDriver`) | — |
| Concurrency idiom | actor-isolated mutable state | structured concurrency + `@Sendable` values + locks | Very different target — good |
| Run A zero-diagnostic claim | Held | Held | **Parser cleanliness generalizes** |
| `actorReentrancy` FP count | 3 (all Bucket B, same state-machine subtype) | 0 | Architecture-dependent; Hummingbird has ~no surface |
| Bucket B subtype | State-machine invariant guard | N/A (no findings) | No new B subtype surfaced |
| Cross-file resolution | Unit-tested; demo was same-file | Corpus-tested on unique names ✅; withdrawn on protocol methods | **New visibility-gap finding** |
| Observational tier | Not shipped yet | 0 FP across 20 obs calls in 5 replayable callers | **Decisive positive** |
| Canonical fix pattern observed in wild? | Discussed | `Server.run()` uses it verbatim, with matching comment | **External corroboration** |

Headline: Phase 1 generalizes to a stylistically different codebase without producing new false-positive patterns. The one surprise (protocol-method collision) is working-as-specified per OI-4's conservative policy, not a bug, and points at a concrete refinement path rather than a rule weakness.

## Proposal amendments

Suggested edits to `../idempotency-macros-analysis.md` Open Issues section. None of these are implemented on the trial branch — the scope commitment held, and these are proposals for follow-up work.

- **OI-4 (cross-file propagation)** — status upgraded from "shipped, validated on one target" to "shipped, validated on two targets with a corpus-surfaced refinement question." Add sub-issue: **bare-name collision policy is too conservative for protocol-oriented Swift APIs.** Every protocol with a default extension implementation and at least one concrete conformer produces three colliding declarations for each method; the current policy withdraws all three. Candidate refinement: collide on `(name, arity, first_argument_label)` rather than `name` alone. This is a data-structure change, not a new rule. Recommend as a Phase-1.1 follow-up, not Phase 2.
- **OI-5 (observational tier)** — status upgraded from "shipped, validated on unit fixtures" to "shipped, validated at corpus scale (20 observational call sites across 5 replayable callers produced zero false positives)."
- **New observation, OI-6 candidate (not raised as a new issue yet):** `actorReentrancy`'s value is architecture-dependent. On `@Sendable`-first codebases the rule produces little signal. This is not a bug — the rule is correctly scoped to actor isolation — but it refines the "defensible for adoption" claim. Recommend adding a one-paragraph adoption note to the proposal: "rules that are most valuable on actor-heavy codebases may produce few diagnostics on structured-concurrency-with-locks codebases, and vice versa; teams should not interpret low diagnostic counts as evidence of safety." Not urgent; informational.

## Follow-ups left open (not done on trial branch)

Per scope commitment, no rule changes were made on `idempotency-trial-round-2`. The following are follow-up candidates for separate commits on `idempotency-trial` (not on the round-2 trial branch):

1. **Signature-aware collision policy for `EffectSymbolTable`.** Blocks clean annotation of protocol-method APIs.
2. **Adoption-guidance note in the proposal.** One paragraph on architecture-dependent rule value.

Neither is a blocker for round-2 sign-off. Phase 1 remains defensible for adoption, with the additional caveat that protocol-method annotations currently don't cross-file-resolve.
