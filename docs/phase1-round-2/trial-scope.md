# Round 2 Trial Scope Commitment

This is the round-2 companion to [`../phase1/trial-scope.md`](../phase1/trial-scope.md). It road-tests the **post-follow-up Phase 1 linter** (round 1 + OI-3/OI-4/OI-5 follow-ups) against a second, stylistically different Swift codebase. This document is the text the trial author points at when a finding tempts scope expansion.

## Pinned target

- **Repo:** `hummingbird-project/hummingbird`
- **Tag:** `2.22.0`
- **SHA:** `a2ed0a0294de56e18ba55344eafc801a7a385a90`
- **Swift-tools-version:** 6.1
- **Local clone:** `/Users/joecursio/xcode_projects/hummingbird`
- **Corpus shape (baseline facts, captured at Phase 0):**
  - 137 Swift source files across 7 modules (`Hummingbird`, `HummingbirdCore`, `HummingbirdHTTP2`, `HummingbirdRouter`, `HummingbirdTesting`, `HummingbirdTLS`, `PerformanceTest`)
  - 16,481 total lines in `Sources/`
  - 2 `actor`-typed declarations (`HummingbirdCore/Server/Server.swift`, `Hummingbird/Storage/MemoryPersistDriver.swift`) — **sparse by design**; the codebase leans on `@Sendable` and value types (83 `@Sendable`/`NIOLockedValueBox`/`Mutex` occurrences across 33 files) rather than actor isolation
  - 21 `logger.info/debug/warning/error/notice/trace` call sites — enough to stress the `observational` tier meaningfully

Both machines pin this exact SHA. Do not upgrade mid-trial.

## Pinned linter branch

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `idempotency-trial-round-2`
- **Forked from:** `idempotency-trial @ 20c6583` (the round-1 post-follow-up tip: "Idempotency rules now resolve across files")

## Pinned demo package

- `/Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo/` — created in Phase 3 as a sibling package to the round-1 Lambda demo. Depends on Hummingbird 2.22.0. The round-1 Lambda demo stays frozen as its own reference.

## Research questions

Round 1 answered "does Phase 1 produce a tolerable false-positive rate on a well-maintained codebase?" Round 2 answers three sharper questions:

1. **Does `actorReentrancy`'s Category-B noise profile transfer to an HTTP-server codebase?** Round 1 = 3 findings / 1 critical stateful-actor file, all the same state-machine-invariant subtype. Prediction: Hummingbird's sparse actor count + `@Sendable` preference will produce **very few** `actorReentrancy` findings (possibly zero). A zero result is itself informative — it says the rule is architecture-specific.
2. **Does the shipped `observational` tier correctly absorb logging/metrics calls at realistic volume?** OI-5 has only been validated on unit fixtures; round 2 Run D is its first corpus-scale test.
3. **Does OI-4 cross-file resolution fire on a genuinely multi-file, multi-module layout?** Round 1's demo had callee and caller in the same file — cross-file was unit-tested, not corpus-tested.

## In scope (unchanged from round 1 + the tier that shipped)

Three rules total, all already built in round 1:

- `idempotencyViolation` — `@lint.effect idempotent` function calls a `@lint.effect non_idempotent` function
- `nonIdempotentInRetryContext` — `@lint.context replayable` / `@lint.context retry_safe` function calls a `non_idempotent` function
- `actorReentrancy` — structural, unchanged since round 1

Annotation grammar:

- Effects: `idempotent`, `non_idempotent`, **`observational`** (shipped as OI-5 follow-up on round 1's branch; the round-2 trial validates it)
- Contexts: `replayable`, `retry_safe`

## Out of scope (unchanged; enforce aggressively)

Everything on round 1's out-of-scope list still applies. In particular: no effect inference, no new lattice tiers, no new contexts, no strict mode, no scoped idempotency, no `@lint.assume` / `@lint.unsafe`, no `@Idempotent` macro, no `IdempotencyTestable`, no `IdempotencyKey`, no `#assertIdempotent`, no protocol layer, no retry-pattern detection.

## Round-2-specific guardrails

- **No rule changes on the trial branch.** Round 1's retrospective flagged that pulling fixes forward mid-trial conflates "does this rule work?" with "how should this rule evolve?". Round 2 is a **pure measurement exercise**. Any issue surfaced → recorded as an Open Issue in the proposal, not fixed on `idempotency-trial-round-2`. One carve-out: a parser bug producing false annotation reads on un-annotated source (Run A non-zero). Same policy as round 1.
- **Branch-local annotation experiments stay local.** Runs C and D modify Hummingbird source on a throwaway branch (`trial-annotation-local`) — do **not** push that branch, do not fork upstream. Only the linter branch is pushed.
- **No merge back into `idempotency-trial` until the full round completes.** If round 2 surfaces a parser bug that is the one carve-out, fix on `idempotency-trial-round-2`, land separately after the write-up.

## Hummingbird-specific notes that shape the runs

- **No `Examples/` directory in-repo.** Hummingbird ships separately at `hummingbird-project/hummingbird-examples`. This changes round 1's Run C plan (which annotated `Examples/HelloJSON`): round 2's Run C annotates a handler inside the **main source tree** on a throwaway branch instead. The mechanism being tested — cross-file resolution — is identical.
- **Actor sparsity.** Two actors in 137 files means `actorReentrancy` is likely to produce 0-1 findings. Structurally expected. The round-1 "3 / 1 critical stateful-actor file" ratio does **not** directly compare; the meaningful round-2 comparison is "findings per actor-containing file," not "findings per critical file." Both ratios are recorded for transparency.
- **`RequestContext` protocol, not class.** Hummingbird handlers take a `RequestContext` generic, not an actor. Annotation placement in Phase 3's demo handler mirrors this — the handler is a free function or closure over a `RequestContext`, not a method on an actor.

## Known gaps the trial will expose but cannot fix

- **Rule sparsity on `@Sendable`-first codebases.** If `actorReentrancy` fires zero times on Hummingbird, that is not a false-negative bug — the rule is scoped to actor isolation by design. A codebase that avoids actors avoids the rule. This is expected behaviour, but it's worth recording as evidence for the OI-1 discussion about rule scope.
- **Observational tier name collisions.** If Hummingbird (or a dependency) defines a local `info` / `debug` function unrelated to logging, the symbol-table bare-name collision policy will withdraw the entry and log no diagnostic. This is the OI-4 "conservative collision" behaviour working as designed; any occurrences are recorded for visibility, not as a bug.

## Deliverables

1. [`trial-findings.md`](trial-findings.md) — counts, triage buckets, transcripts, **delta table vs. round 1**.
2. Amendments to [`../idempotency-macros-analysis.md`](../idempotency-macros-analysis.md) Open Issues section — only if round 2 surfaces patterns round 1 did not. OI-5's "shipped" status may be upgraded to "validated on two targets."
3. [`trial-retrospective.md`](trial-retrospective.md) — one page.

## Cost budget

~2.5 days (vs. 4.5 for round 1; no linter/fixture work this round). Phase 4 Run B + Run D triage is the biggest time investment.
