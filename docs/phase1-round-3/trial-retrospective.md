# Round 3 Trial Retrospective

One page. The third and final Phase-1 road-test's retrospective. The main question it needs to answer: is Phase 1 shippable after three trials?

## Did the scope hold?

**Yes.** Zero code changes on `idempotency-trial-round-3`. The signature-aware collision fix from round 2 was **not** pulled forward (declined for the second time — each time preserves the generalization claim). Every finding was recorded, none were fixed in-trial.

## Answering round 3's framing question

The round-3 plan opened by correcting the round-2 retrospective's framing of pointfreeco: it had claimed pointfreeco would exercise Phase-2 features (`externallyIdempotent`, `IdempotencyKey`, `#assertIdempotent`). None of those features exist in code, so the claim was unexecutable. The corrected framing asked three honest Phase-1 questions: parser scaling, real-code annotation, and application-actor Bucket-B subtypes.

**Was the correction worth it?** Yes, decisively. The actual Phase-1 questions pointfreeco answered are meaningfully different from what the round-2 retrospective proposed:

- **Parser scaling (corrected question):** 0 diagnostics on 918 Swift-6.3 files. Clean result, real adoption-readiness signal.
- **Real-code annotation (corrected question):** 1 diagnostic on honestly-annotated production Stripe webhook chain. **The strongest single piece of "this is useful" evidence in the entire trial record.**
- **Application-actor Bucket-B (corrected question):** Unanswerable because pointfreeco has zero actors. But this itself is a meaningful data point — confirming the three-trial pattern that `actorReentrancy` is runtime-specific.

If the round-3 plan had uncritically executed on round-2's Phase-2 framing, it would have produced a confused report about features that don't exist. The correction wasn't pedantic; it was load-bearing.

**Lesson:** a retrospective's speculative next-steps are not binding. Re-interrogate them before acting.

## Which findings tempted expansion

Two tempted, both declined:

1. **Signature-aware collision fix.** Same as round 2. Round 3 didn't re-trigger the policy (the uniquely-named `sendGiftEmail` avoided it), but the temptation to pull the fix forward remains because every additional round without the fix is a round that can't test protocol-oriented APIs end-to-end. Still declined — three rounds of the same linter is the only way to make the "Phase 1 generalizes" claim defensible.
2. **Transitive context propagation.** Run C needed three annotations on the webhook call chain. Adding a minimal "if a `@context replayable` function calls a private helper that is reachable only from it, the helper inherits the context" rule would reduce Phase 1's annotation burden by ~60% on webhook-shaped code. Genuinely small design space, genuinely useful. Declined because "call graph reachability analysis" is exactly what Phase 2's effect inference is — adding a subset of it during a Phase-1 measurement trial would confound the trial's own result and land the first slice of Phase 2 code outside Phase 2's scope.

Both rejections were close-run calls. Recording them here means they become their own properly-scoped follow-up decisions instead of silently-merged trial-branch drift.

## Is Phase 1 shippable for adoption?

**Yes, with three qualifications that the proposal should absorb before adoption.**

The positive case, three-codebase-confirmed:

- Parser cleanliness holds at 918 files / Swift 6.3. No false positives on un-annotated source in any of three corpora.
- Annotation-gated rules produce the expected diagnostic on synthetic demos (three shapes tested) AND on real production code (Stripe webhook chain in round 3).
- Cross-file resolution works, including across directory boundaries in real code.
- `observational` tier does not generate false positives on logging calls in replayable contexts across multiple codebase architectures.
- `actorReentrancy` produces zero false positives across three rounds; the three true findings (round 1's state-machine-invariant guards) were informative Bucket-B results, not bugs.

The qualifications:

1. **Protocol-method cross-file resolution is blocked by collision policy.** OI-4 carryover from round 2. A Phase-1.1 fix (signature-aware collision keys) is a bounded data-structure change; recommend landing it as the first small post-trial commit.
2. **Annotation granularity is Phase 1's biggest adoption friction.** Run C surfaced it: real webhook chains need annotations on helper functions, not just entry points. No fix in Phase 1; this motivates Phase 2's effect inference directly.
3. **`actorReentrancy`'s value is architectural.** Round 3 made this three-trial definitive. One-paragraph adoption note in the proposal — OI-6 — should ship with Phase 1, not be deferred.

## Which un-built rules would have changed the triage

- **Effect inference / context propagation (Phase 2).** Would have reduced round 3's Run C annotation count from 4 to 2 (just `stripePaymentIntentsWebhookMiddleware` + `sendGiftEmail`; the two private helpers would inherit via call-graph reachability). Phase 1's "island of annotations" UX is exactly this gap.
- **`externallyIdempotent` tier + `IdempotencyKey` strong type (Phase 2).** Round 3 offered concrete motivation: `sendGiftEmail` is non-idempotent *today* because it sends an email directly. A Phase-2-shaped fix would annotate it `@lint.effect externallyIdempotent(key: IdempotencyKey)`, require the key at the call site, and let the linter prove the key is routed to Mailgun's idempotency-key header. That's the kind of fix real Stripe/SES integrators actually make. **Phase 2 is earned** — there is now real evidence the features solve a real problem.
- **Signature-aware collision (Phase 1.1).** Would have let `MemoryPersistDriver.create` from round 2 resolve cross-file, reducing the OI-4 carryover to a footnote.

## Cost summary

- **Estimated:** 2.5 days, budget 3.5.
- **Actual:** one focused session, ~90 minutes of model time.
- **Biggest time sink:** pointfreeco's LFS clone failure. Resolved with `GIT_LFS_SKIP_SMUDGE=1` plus `-c filter.lfs.smudge=` on checkout. First-time-gotcha worth remembering — a lot of PointFree-flavoured repos use LFS for asset-heavy content.

## Net output after three rounds

**Phase 1 is validated.** Three stylistically different codebases (serverless runtime, HTTP-server framework, real application) — three corpus-clean runs on annotation-gated rules, three consistent results on the structural rule, one decisive real-code success on Run C, one decisive synthetic-volume observational-tier success on round 2's Run D.

The one novel finding per round has been:

- Round 1: OI-1's state-machine-invariant Bucket B subtype (the canonical "noisy but correct" pattern).
- Round 2: OI-4's protocol-method collision visibility gap.
- Round 3: OI-6's architectural specificity of `actorReentrancy` — confirmed rather than newly discovered, but the confirmation is the finding.

**Recommended post-trial path:**

1. Land OI-4's signature-aware collision fix as a Phase-1.1 commit.
2. Land OI-6's adoption-guidance paragraph in the proposal.
3. Proceed to Phase 2. Three-round Phase-1 validation is sufficient; a fourth trial would produce diminishing returns. The concrete motivation for Phase 2's effect inference and `externallyIdempotent` tier that round 3 surfaced is stronger evidence for beginning Phase 2 than for running Phase 1 again.

## Policy note for Phase 2

The round-2 guardrail "no rule changes on the trial branch" worked a second time on round 3 — **keep this policy for all future trials, no exceptions.** Each time it held, it produced cleaner deliverables. Each time scope-expansion was tempted and declined, the deferred finding became its own properly-scoped commit instead of confounding a measurement. This is the single procedural win of this trial record worth carrying into Phase 2 work.
