# Trial Retrospective

One page. Protects the next trial from scope creep by writing down what this one cost and what tempted expansion mid-run.

## Did the scope hold?

**Yes.** The scope commitment in [`trial-scope.md`](trial-scope.md) held unbroken for all six phases. The Phase-1 linter that actually shipped consists of:

- Two new rule identifiers (`idempotencyViolation`, `nonIdempotentInRetryContext`)
- One new category (`idempotency`)
- Two new visitors (`IdempotencyViolationVisitor`, `NonIdempotentInRetryContextVisitor`)
- Two new utility types (`EffectAnnotationParser`, `EffectSymbolTable`)
- Three pattern registrars (one category, two rules)

Approximately 450 lines of production code and 350 lines of test code. Substantially smaller than the proposal's full Phase 1 scope suggested, largely because the existing `ActorReentrancyVisitor` already handled what the proposal called `actorReentrancyIdempotencyHazard`.

## Which findings tempted expansion

Three genuine temptations, each declined in-trial:

1. **OI-3 (actor-reentrancy write detection).** The failing fixture `claimBeforeSuspension_noDiagnostic` demonstrated that the existing rule flagged the proposal's canonical fix pattern. Deferred during the trial proper; **addressed in a follow-up** after the trial wrote up its findings. `collectAssignments` now recognises mutating-method calls on tracked stored properties via a narrow whitelist (`insert`, `append`, `remove`, `removeAll`, `updateValue`, `formUnion`, `subtract`, `merge`, …). Regression guards lock in the whitelist's boundary (`processedIDs.contains(id)` is still treated as a read). Subscript-set and compound-assignment claims remain open; captured in the proposal's updated OI-3 text. Re-running Run B against the runtime confirmed the change is **orthogonal** to the Category-B findings on `LambdaRuntimeClient` — those are state-machine invariant guards, not missing mutating-method writes.
2. **OI-4 (cross-file propagation).** Once the "island of annotations" UX surfaced in Phase 4 Run C, the obvious fix — an in-memory cross-file symbol table populated during pre-scan — was visible. Deferred: the proposal's roadmap explicitly puts cross-file in Phase 3. Pulling it forward would have roughly doubled the trial's total code cost and merged two distinct scope questions.
3. **OI-5 (observational tier).** The "what about `Logger.info`?" question came up during Phase 3 handler design. The demo handler deliberately omitted logging to avoid forcing a decision. Deferred: adding a new lattice tier is a grammar change; every downstream consumer (linter, future macro, `@lint.assume` file format) has to know about it.

Each of these was a real design question, and each now has a concrete open issue anchored by trial evidence rather than speculation. That is the return on the scope commitment.

## Which un-built rules would have changed the triage

- **Effect inference (roadmap Phase 2).** Would have let Phase 4 Run C produce useful signal on the un-annotated `HelloJSON` example — the linter could have inferred `handle` was effectively pure from its body and flagged the `@context replayable` annotation as strong-enough-to-be-redundant. Without inference, the annotation is a no-op on pure transformations.
- **Cross-file propagation (roadmap Phase 3).** Would have produced additional findings on the real runtime — any cross-file actor method whose state check lives in a different file than its stored property declaration is currently invisible. Based on a quick grep of `LambdaRuntimeClient`, this does not appear to be a missed true positive, but the trial cannot rule it out structurally.
- **`externallyIdempotent` tier and `IdempotencyKey` strong type (proposal's Idempotency Keys section).** Would have been unused on this target — the Lambda runtime itself does not expose idempotency-key parameters. Would be needed for any real handler that calls Stripe, SES, or a third-party API. Out of scope here; worth a separate trial against a `vapor/vapor` or `grpc/grpc-swift` handler.

## Cost summary

- **Estimated:** 4.5 days, budget 6.
- **Actual:** one focused session (~3–4 hours of model time, no calendar days). The Phase 2 fixtures took the longest, as predicted in the plan.
- **Biggest time sink:** a transient test failure in `exitWithErrorForInvalidCategory` after a stash-pop, traced to incremental-build staleness from the stash round-trip. Resolved by `swift package clean && swift build`. Lesson: stash-pop against a multi-package workspace can leave SPM's build cache in a hybrid state.

## Net output

The proposal's Phase 1 is defensible as-is for adoption. The trial produced four concrete findings against well-understood failure modes (OI-3, OI-4, OI-5, and an implicit confirmation of OI-1's premise from Run B's category-B diagnostics). None of these are surprising in retrospect. The value is that they are now recorded with evidence instead of speculation.

If a next trial runs, the natural target is a real application codebase with annotated primitives — `vapor/vapor` per the proposal's Related Work, or a small internal microservice. That would exercise `externallyIdempotent`, `IdempotencyKey`, and — if OI-5 is resolved — the proposed `observational` tier. The question that test would answer is "does the full Phase 2 roadmap justify its own complexity?"
