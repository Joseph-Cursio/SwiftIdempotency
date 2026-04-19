# Trial Scope Commitment

This trial road-tests the idempotency design proposal (`docs/idempotency-macros-analysis.md`) against a real Swift codebase. It builds only **Phase 1** of the proposal's phased roadmap. This document is the text the trial author points at when a finding tempts scope expansion.

## Pinned target

- **Repo:** apple/swift-aws-lambda-runtime
- **Tag:** 2.8.0
- **SHA:** `553b5e3716ef8e922e57b6f271248a808d23d0fb`
- **Local clone:** `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime`

Both machines pull this exact tag. Do not upgrade mid-trial.

## Pinned linter branch

- **Repo:** Joseph-Cursio/SwiftProjectLint
- **Branch:** `idempotency-trial`
- **Forked from main at:** `70ba1a5` (Expand novelty section with detailed breakdown of three contributions)

## Pinned demo package

- `/Users/joecursio/xcode_projects/swift-lambda-idempotency-demo/` — created in Phase 3. Depends on `swift-aws-lambda-runtime` 2.8.0.

## In scope (Phase 1 only)

Three rules total, two new:

- `idempotencyViolation` — new. `/// @lint.effect idempotent` function calls a `/// @lint.effect non_idempotent` function.
- `nonIdempotentInRetryContext` — new. `/// @context replayable` or `/// @context retry_safe` function calls a `non_idempotent` function.
- `actorReentrancy` — **already ships** in SwiftProjectLint. The trial benchmarks the existing rule against the proposal's `actorReentrancyIdempotencyHazard` spec. No new code.

Supporting components (new):

- `EffectAnnotationParser` — reads `/// @lint.effect <tier>` and `/// @lint.context <kind>` from doc-comment leading trivia.
- `EffectSymbolTable` — per-file `[FunctionName: (DeclaredEffect?, ContextEffect?)]`.
- `IdempotencyVisitor` — single-pass AST traversal, extends `BasePatternVisitor`.

Annotation grammar limited to:

- Effects: `idempotent`, `non_idempotent`. Nothing else.
- Contexts: `replayable`, `retry_safe`. Nothing else.

## Out of scope (explicit)

If the trial surfaces a need for any of the following, it is recorded as a new Open Issue in `idempotency-macros-analysis.md` and **not** implemented during the trial:

- Effect inference of any kind (body-structure analysis, composition rules)
- Cross-file propagation (the proposal's roadmap Phase 3; out of trial scope)
- Tiers beyond `idempotent` / `non_idempotent`: no `pure`, no `transactional_idempotent`, no `externally_idempotent`, no `unknown`
- Contexts beyond `replayable` / `retry_safe`: no `once`, no `dedup_guarded`
- Strict mode / unannotated-function warnings
- Scoped idempotency: `idempotent(by:)`
- `@lint.assume`, `@lint.unsafe`, suppression grammar, grammar versioning
- `@Idempotent` macro, `IdempotencyTestable`, `IdempotencyKey` strong type, `#assertIdempotent`
- Protocol-based layer (`IdempotentOperation` etc.)
- Retry pattern detection (loops, task groups, SwiftUI `.task`) — the critique specifically recommends demoting this; not included

## Known gap the trial will expose but cannot fix

The `non_idempotent` tier conflates "mutates persistent state" with "has any observable side effect." Logging and metrics are non-idempotent under a strict reading; no one treats them as retry hazards. Phase 4 will likely surface this as the headline false-positive pattern. The fix is a new lattice tier (`observational`?) — that is a grammar change and belongs in the proposal's next iteration, not this trial.

## Deliverables

1. [`trial-findings.md`](trial-findings.md) — counts, triage buckets, transcripts.
2. Amendments to [`../idempotency-macros-analysis.md`](../idempotency-macros-analysis.md) Open Issues section only.
3. [`trial-retrospective.md`](trial-retrospective.md) — one page, did the scope hold, what tempted expansion.
