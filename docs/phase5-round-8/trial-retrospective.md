# Round 8 Trial Retrospective

Single spike to close round-7 Finding 4. Landed cleanly on one of three candidates. Short retrospective.

## Did the scope hold?

**Yes, with a mid-spike design pivot inside Candidate A.** The plan budgeted three candidates across three days. Candidate A's first form (`@IdempotencyTests(for: [funcRef, ...])`) hit two unforeseen frictions — the function-reference argument wouldn't resolve, and qualifying with the type name produced a circular-reference error. Both were structural, not incidental. The in-spike pivot to a scan-members form was a cleaner design regardless and fell inside the "three in-candidate iterations" cap the scope doc allowed. Candidate A's revised form still failed Finding 4, which was the actual measurement.

Candidate C was skipped after Candidate B succeeded, per the plan's Fallback clause ("don't keep exploring when a green path is in hand"). Not a scope contraction — the plan explicitly permitted the early stop.

## Answers to the four pre-committed questions

### (a) Which candidate landed, and what was the measured symptom on the rejected ones?

**Candidate B — `@attached(extension)` — landed.** The generated `@Test`s live in a fresh extension decl separated from the original struct's member layout, which sidesteps Swift Testing's property-initialiser ordering check.

Candidate A's scan-members form reproduced the exact round-7 Finding 4 error signature (three errors: `cannot use instance member within property initializer`, `@used must be static`, `@section must be static`). The role change from peer to member doesn't help; what matters is whether the emitted `@Test` lands inside the attached type's own member block.

### (b) Did the candidate require in-spike shape-changes beyond the plan's pre-committed design?

**Two**, both inside Candidate A's budget:

- **Friction 1: function-reference argument doesn't resolve.** `currentSystemStatus` as a bare argument reference outside a method body has no scope to resolve into. Plan had warned this was the "biggest open risk" for Candidate A.
- **Friction 2: type-qualified reference is cyclic.** `SampleIntegrationTests.currentSystemStatus` cycles through the attribute's own attached-type resolution.

Both pointed at the same conclusion: the member macro shouldn't take function references as arguments. Pivoted to scan the attached type's member block directly for `@Idempotent`-marked zero-arg functions. Clean, single-attribute, no argument parsing.

That pivot carried forward into Candidate B unchanged — the scan logic is shared between the two role-conformances. So Candidate B inherited a cleaner shape than the plan originally drafted for it.

### (c) What's the next unit of work now that Finding 4 is closed?

**Direction 2 from the round-7 retrospective — `strict_replayable` context tier.** The round-7 retrospective ordered the work as (1) close Finding 4, (2) strict tier, (3) third corpus. (1) is now done. (2) is a feature addition that benefits from `@Idempotent` being a cheap single-attribute annotation, which it is now (marker-only, no compile-time cost beyond parsing).

A minor ancillary ahead of (2): the linter needs one line updated so `@IdempotencyTests` is a recognised attribute name (distinct from `@Idempotent`). Not scope-worthy on its own, bundle into the next linter touch.

### (d) Is the `SampleWebhookAppTests` sample still useful, or should round-8 artefacts subsume it?

**Keep it.** The sample is the only place the end-to-end integration of macros + linter is exercised outside unit tests — that's where Finding 4 was discovered, and where it's now shown closed. Round 8 didn't change that value proposition. The sample's round-7 "deferred" comment block was replaced with a round-8 "landed" block; otherwise structure is unchanged.

It remains local-only (not a published example). If it ever ships publicly, it's the right shape to become `SwiftIdempotency/Examples/IntegrationTests/` inside the macros package. No urgency.

## What would have changed the outcome

- **Pre-spike architecture reading of Swift's macro expansion pipeline.** The plan's prediction ordered candidates as "C most likely, A second, B third" — reasoning from the assumption that any `@Test` emitted by another macro inside a struct would hit Finding 4. The actual result was B, because extension expansion happens at a different point in type layout. A half-hour of reading `swift-syntax`'s expansion-order docs would have reversed the prediction order. The spike still took roughly the same time — A and B share most of their scan logic — but the intuition was off.
- **Recognising earlier that function references can't cross the attribute boundary.** Candidate A's two frictions are both variants of "attribute arguments are evaluated outside the type body." A pre-spike read of SE-0397 (attached macros) would have flagged this. Plan acknowledged the "biggest open risk" abstractly but didn't name the precise failure mode.

## Cost summary

- **Estimated:** 2-3 days (plan's original budget).
- **Actual:** ~1 hour of model time. Round-7 sample already existed, the red baseline took five minutes to reproduce, the macros package was well-organised for swapping the `IdempotencyTestsMacro` implementation under one attribute declaration. No toolchain work, no extra scaffolding.
- **Biggest time sink:** writing the per-candidate in-spike iteration honestly (friction 1 → pivot → friction 2 resolved by pivot → Candidate A measurement → Candidate B one-line role change → green). About 15 minutes of that 1 hour on Candidate A's pivot; the rest was split across writing tests, the findings doc, and rewrites of the sample's comment block.

## Policy notes

- **Three-candidate pre-commitment was valuable even though only two were prototyped.** Having C in writing meant Candidate B's success was a measurable early stop, not a "we didn't bother." The plan's Fallback clause gave explicit permission to stop.
- **The "scan members of attached type" pattern is probably reusable.** Other attached macros that generate per-member companion decls (tests, wrappers, registrations) probably want the same shape. Worth naming in the macros package's README.
- **Swift Testing's `@Test` interaction with outer macros is understood enough now to file upstream as a clarification request.** Not a bug — the property-initialiser check is the compiler enforcing a safety invariant — but the interaction with nested macros is undocumented and surprising. Worth a Swift Forums post or an Evolution doc note so the next adopter doesn't re-derive it.

## Net output after eight rounds

- **Six rule-measurement rounds (1-6)** validated linter precision across two corpora and four code styles.
- **Round 7** measured macros-package mechanisms; three shipped green, one deferred (Finding 4).
- **Round 8** closed the deferred mechanism. All four mechanisms now ship green.

The proposal's Phase 5 section is now accurate without an asterisk. The macros package ships as "four mechanisms, all green, integration-verified against a real consumer sample." Any future work is feature addition, not backlog cleanup.

## Recommended path after round 8

1. **`strict_replayable` context tier** — the round-7 retrospective's direction 2. Pair-of-PRs slice (linter-side rule + proposal-side doc). ~3-5 days.
2. **Third-corpus validation** — direction 3. Now that macros are integration-proven, pick a Vapor app or internal microservice and measure adoption friction end-to-end. Cost depends on corpus.
3. **Swift Forums writeup of the nested-`@Test` finding** — half-day. Valuable for community knowledge even if the round-8 redesign worked around it.

My pick: **(1) first, then (2).** Same ordering the round-7 retrospective proposed; round 8 didn't change the value calculus.

## Data committed

- `docs/phase5-round-8/trial-scope.md` — this trial's contract
- `docs/phase5-round-8/trial-findings.md` — per-candidate measurements
- `docs/phase5-round-8/trial-retrospective.md` — this document
- `docs/claude_phase_5_peer_macro_redesign_plan.md` — plan (written pre-spike)

Macros package edits on branch `spike-peer-macro-redesign`, ready to merge to `main` once reviewed. Sample package updated in place (no git history). No linter changes this round.
