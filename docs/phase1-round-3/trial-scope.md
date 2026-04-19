# Round 3 Trial Scope Commitment

Third and final Phase-1 road-test. Companion to [`../phase1/trial-scope.md`](../phase1/trial-scope.md) and [`../phase1-round-2/trial-scope.md`](../phase1-round-2/trial-scope.md). This document is the text the trial author points at when a finding tempts scope expansion.

## Pinned target

- **Repo:** `pointfreeco/pointfreeco`
- **Tag:** none (pointfreeco does not cut release tags; this trial pins by commit SHA)
- **SHA:** `06ebaa5276485c5daf351a26144a7d5f26a84a17` (main HEAD at trial start)
- **Swift-tools-version:** 6.3
- **Local clone:** `/Users/joecursio/xcode_projects/pointfreeco` (LFS-skipped — asset files under Git LFS; this trial needs only Swift source)
- **Corpus shape (baseline facts, captured at Phase 0):**
  - **918 Swift source files** — **6.7× Hummingbird (137), 9× the round-1 Lambda runtime (~100)**
  - **74,588 total lines** in `Sources/`
  - 30+ modules including `PointFree`, `Stripe`, `Database`, `Server`, `Models`, `Mailgun`, `GitHub`
  - Real replayable contexts available at `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift` and `Sources/PointFree/Webhooks/SubscriptionsWebhook.swift` — Stripe webhook handlers, objectively retry-exposed per Stripe's documented delivery-retry policy

Both machines pin this exact SHA. Do not update mid-trial.

## Pinned linter branch

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `idempotency-trial-round-3`
- **Forked from:** `idempotency-trial-round-2 @ 20c6583` — **same tip as rounds 1-post-follow-up and round 2.** No code delta between round 2 and round 3. By design.

## Correcting the round-2 retrospective

The round-2 retrospective framed pointfreeco as a target because it "would exercise the externallyIdempotent tier, IdempotencyKey strong type, and #assertIdempotent macro." **That framing was wrong.** Those are Phase-2 deliverables; none of them exist in code. With today's Phase-1 linter, pointfreeco cannot produce signal about features that are not built.

The corrected research questions for round 3 are:

1. **Parser scaling.** Does `EffectAnnotationParser` stay silent on a 918-file Swift-6.3 corpus (vs. rounds 1–2's ~100–137-file Swift-6.0/6.1 corpora)?
2. **Real replayable-context annotation.** Can an honest annotation campaign on a real Stripe webhook handler — Stripe-retried-for-real, not synthetic — produce a useful diagnostic count? Every prior trial's annotations were on invented demo/trial code.
3. **Application-actor Bucket B subtypes.** Do application actors (caches, rate limiters, coalescers) surface Bucket-B `actorReentrancy` subtypes distinct from round 1's runtime state-machine subtype?

## Smoke-test result (recorded here because it IS Run A)

At Phase 0 the linter was run against pointfreeco's un-annotated corpus as a toolchain-compatibility check. Result: **`No issues found.`** Zero diagnostics, zero crashes, zero parse failures propagated to output. SwiftSyntax 602 tolerates Swift 6.3 source at corpus scale. This is simultaneously the toolchain spot-check AND Run A. Transcript at [`trial-transcripts/pointfreeco-runA.txt`](trial-transcripts/pointfreeco-runA.txt).

## In scope (unchanged from round 2)

- Annotation grammar: `idempotent`, `non_idempotent`, `observational` (effects); `replayable`, `retry_safe` (contexts). No additions.
- Three rules: `idempotencyViolation`, `nonIdempotentInRetryContext`, `actorReentrancy`.

## Out of scope (enforce aggressively)

Everything on rounds 1–2's out-of-scope list still applies. The Phase-2 features the round-2 retrospective mis-attributed as round-3 targets — `externallyIdempotent`, `IdempotencyKey`, `#assertIdempotent`, `@Idempotent` macro, protocol-based layer — remain out of scope. **Not implemented on this branch, not validated by this trial.**

## Round-3-specific guardrails

- **No rule changes on `idempotency-trial-round-3`.** Measurement only. Any finding → recorded as an Open Issue, not fixed. Parser-bug carve-out inherited from round 2.
- **Signature-aware collision fix is NOT pulled forward.** Round 2 surfaced the protocol-method bare-name collision gap. Pulling the fix forward would confound round 3's result with round 2's deferred work. Keeping the same linter means the generalization claim is meaningful.
- **Annotation experiments stay on throwaway branch `trial-annotation-local` in the pointfreeco clone.** Do not push. Do not PR anything to pointfreeco upstream — the annotations are honest, but this is a measurement exercise, not a contribution.
- **Honest annotations only.** Run C annotates functions that really are replayable / really are non-idempotent in production. If no honest annotation applies to a function, it is not annotated to manufacture a diagnostic.

## pointfreeco-specific notes

- **LFS-skipped clone.** The clone used `GIT_LFS_SKIP_SMUDGE=1` plus `-c filter.lfs.smudge=` on checkout. LFS assets (transcripts, videos, images) are not present as working-tree files; the SHA pin still refers to the full commit. The linter doesn't need LFS payloads — only Swift source.
- **Swift 6.3 tools version.** The SwiftProjectLint linter builds on Swift 6.2 with SwiftSyntax 602.0.0. SwiftSyntax 602 proved to parse pointfreeco's Swift-6.3 source in the smoke test above. Some Swift 6.3 syntax may produce per-file parse warnings during individual rule visitation; any such warnings are recorded in the trial artefacts, not treated as rule failures.
- **Point-Free's `HttpPipeline` middleware shape.** pointfreeco uses a custom `Conn<StatusLineOpen, Void> → Conn<ResponseEnded, Data>` middleware signature. Phase-1 linter rules operate on function names and annotations, not on middleware generic types — the shape is neutral to the rules.

## Known gaps the trial will expose but cannot fix

- **Phase-2 features stay untested.** This trial does not validate `externallyIdempotent`, `IdempotencyKey`, `#assertIdempotent`, `@Idempotent`, or the protocol layer, because none of them exist. That is a deliberate consequence of the scope commitment, not a failure of round 3.
- **Email side effect categorization.** The webhook handler's `sendGiftEmail(for:)` is genuinely non-idempotent (duplicate email on replay), but observationally only in the "user noticed" sense. Phase 1's `non_idempotent` tier is correct for this; the richer distinction (email-at-most-once vs. DB-mutating-at-most-once) belongs in Phase 2's scoped idempotency discussion.

## Deliverables

1. [`trial-findings.md`](trial-findings.md) — counts, triage buckets, transcripts, **three-codebase delta table**.
2. Amendments to [`../idempotency-macros-analysis.md`](../idempotency-macros-analysis.md) Open Issues — only if round 3 surfaces patterns rounds 1–2 did not. OI-4 collision-policy refinement case strengthens if protocol-name collisions recur. New Bucket-B subtype under OI-1 if found.
3. [`trial-retrospective.md`](trial-retrospective.md) — one page. Answers: (a) is Phase 1 shippable after three trials? (b) was the round-2 retrospective's framing of pointfreeco useful or wasteful? (c) if Phase 2 starts next, what open questions does it inherit from this trial?

## Cost budget

~2.5 days. Same as round 2. Run C (honest annotation of a real webhook handler) is the biggest time investment and the single phase most likely to produce unexpected results.
