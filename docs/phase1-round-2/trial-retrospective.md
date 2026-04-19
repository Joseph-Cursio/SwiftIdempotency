# Round 2 Trial Retrospective

One page. Protects round 3 (if there is one) from scope creep by writing down what round 2 cost and what tempted expansion.

## Did the scope hold?

**Yes.** Round 2's scope commitment — "pure measurement, no rule changes on the trial branch" — held across all six runs. Zero lines of production code were modified on `idempotency-trial-round-2`. Two findings tempted fixes (protocol-method collision in Run C.1; the architecture-dependent sparsity framing for Run B); both were deferred to separate follow-up commits on `idempotency-trial`, not touched during measurement.

## Which findings tempted expansion

Two genuine temptations, each declined in-trial:

1. **Signature-aware collision policy (Run C.1).** The `MemoryPersistDriver.create` annotation failed to resolve cross-file because three declarations of `create` (protocol requirement, extension default, concrete implementation) all collide on bare name and the conservative policy withdraws them. Fix is data-structure-shaped: key on `(name, arity, first_argument_label)` instead of `name`. Tempting because the fix is bounded and the code path to change is small. Deferred because round 2's scope is measurement, not evolution — the finding is only valid *because* the measurement stayed clean.
2. **Adoption-guidance paragraph for architecture-dependent rules (Run B).** Round 1's "3 findings / 1 critical file" claim does not transfer to Hummingbird, not because the rule is worse but because the architectural precondition (heavy actor use) does not hold. Tempting to add a paragraph to the proposal immediately. Deferred: the proposal is already a design doc under amendment; this note belongs in a deliberate revision, not a trial-day edit.

Both findings are recorded in [`trial-findings.md`](trial-findings.md) with supporting evidence and concrete remediation proposals. That is the return on the scope commitment.

## What would have changed if scope had been loosened

If I had pulled the signature-aware collision fix forward into round 2:

- Total code delta on the linter branch would have grown from zero to ~50–100 lines (a small symbol-table refactor plus fixture additions).
- The Run C.1 result would have flipped from zero to one diagnostic — and we would have lost the single clearest piece of round-2 evidence: that a conservative policy correctly withheld a resolution that was ambiguous by design.
- The measurement-vs-evolution boundary would have blurred, exactly as round 1's retrospective warned.

Declining the temptation preserved the artefact.

## Which un-built rules would have changed the triage

- **Effect inference.** Would have let `actorReentrancy`-shaped reasoning apply even to non-actor concurrency primitives (e.g., `NIOLockedValueBox` with a `withLockedValue { … await … }` re-entrance hazard). On Hummingbird, this would extend the rule to the 33 files that use `@Sendable` + locks rather than actors — potentially a 5–10× signal increase. Out of scope for Phase 1 regardless.
- **Protocol-requirement tracking.** Separate from the signature-aware collision fix: if the linter tracked "method X has declared effect Y on protocol P" and propagated it to conformers that don't re-declare it, protocol-oriented APIs would get cross-file resolution for free. Bigger change than signature-aware collisions and closer to effect inference. Not something to take on piecemeal.
- **`externallyIdempotent` tier / `IdempotencyKey` strong type.** Still unused here — Hummingbird is a server framework, not a business-logic host, and has no first-party calls to Stripe/SES/etc. The right codebase for that trial is a real application, not a framework. Round 3 target if it happens.

## Cost summary

- **Estimated:** 2.5 days, budget 3.5.
- **Actual:** one focused session, ~2 hours of model time. Most time went to Phase 3 and Phase 4 Run B's triage; Run D was quick because the wrapper-function design short-circuited the swift-log dependency question.
- **Biggest time sink:** diagnosing Run C.1's zero-diagnostic result. Initial hypothesis (annotation parser issue) was wrong; the actual cause (bare-name collision withdrawal) took a minute to confirm via `grep` but required reading the OI-4 follow-up's docstring to rule out a parser bug.

## Net output

**Phase 1 generalizes.** Two codebases, stylistically opposite (event-driven serverless vs. HTTP-server framework), and the linter behaves consistently: parser clean on both, structural rule correctly scoped to the architectural shape it targets, annotation-gated rules produce zero false positives on un-annotated source, and the `observational` tier absorbs logging at volume.

The one novel-finding-per-round pattern held: round 1 surfaced OI-1's Bucket B (state-machine invariant). Round 2 surfaced the protocol-method collision visibility gap. Both are real, both are bounded, both have concrete remediation paths, neither invalidates Phase 1 as shippable.

If a round 3 happens, the obvious next targets — in decreasing order of novel information per day — are:

1. **A real application codebase with live Stripe/SES calls** (e.g., `pointfreeco/pointfreeco` or a small internal microservice). This would exercise the `externallyIdempotent` tier, `IdempotencyKey` strong type, and `#assertIdempotent` macro — all of which round 2 left untouched. This is the biggest single gap in the trial record.
2. **An actor-heavy codebase that is *not* a runtime** (e.g., `vapor/vapor`'s reference-type handler internals, or a large macOS app). Would answer "does round 1's Bucket B rate transfer to non-runtime actor code?" More controlled than the `pointfreeco` trial, less new information.
3. **A codebase with explicit retry loops** (`swift-server/async-http-client`). Would stress `actorReentrancy` hardest. Likely lowest information gain per day because round 1 already established the rule's FP profile on actor-heavy code.

Round 3 should **not** be another framework. Two framework trials in a row would answer diminishing-returns questions.

## Policy note

The round-2 guardrail "no rule changes on the trial branch" worked well. Recommend carrying it forward to all future trials: pure measurement rounds produce cleaner deliverables than rounds that mix measurement with evolution, and the deferred findings become their own separate (smaller, easier-to-review) commits afterwards.
