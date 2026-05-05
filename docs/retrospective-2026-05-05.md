# SwiftIdempotency Retrospective — 2026-05-05

A single-day-window addendum sitting on top of
[`retrospective-2026-05-04.md`](retrospective-2026-05-04.md).
That document closed with three "what to do next" branches; this
session executed the **new-adopter-probe** branch, specifically
the Apple Wallet (`vapor-community/wallet`) candidate. One round
was completed and one methodology refinement landed.

## What landed in the window

- **One linter road-test round**: round 19 — `wallet`
  (Apple Wallet Web Service Protocol). Trial fork
  `Joseph-Cursio/wallet-idempotency-trial`, branch
  `trial-wallet`. Findings under
  [`docs/wallet-package-trial/`](wallet-package-trial/).
- **One methodology refinement** to `road_test_plan.md`: the
  Fluent `.unique(on:)` heuristic was tightened (commit
  `8db4c85`).
- **No new shipped versions.** Package remains at v0.3.1; no
  slice shipped; no API surface changed.

## Round 19 — wallet

**First spec-mandated retry adopter.** Every prior round inferred
`@lint.context replayable` from the framework's at-least-once
delivery contract. Wallet is the first where Apple's Wallet
Web Service Protocol *explicitly* mandates the contract — the
adopter literally hand-rolls `if r != nil { return .ok }` (line
67-68 of `PassesServiceCustom+RouteCollection.swift`) to comply
with Apple's "if registration already exists, return 200 OK"
rule.

Six handlers annotated on the Passes side. Run A: 5 diagnostics,
Run B: 44 (5 carried + 39 strict-only across six known clusters).
After SQL ground-truth pass against three `fluent-wallet`
migrations:

| Handler | Run A verdict |
|---|---|
| `registerPass` | defensible (cross-function guards) |
| `updatablePasses` | silent (pure read) |
| `updatedPass` | silent (cached read) |
| `unregisterPass` | defensible (DELETE-idempotent) |
| `logMessage` | silent (observational) |
| `personalizedPass` | **real catch** — `.unique(on: passID)` present, no read-guard, no error-catch → 500 on Apple-spec retry |

**Yield: 1 / 6 = 0.17 including silent (1 / 3 = 0.33
excluding).** The lowest-yield round to date *and* the
strongest ground-truth corpus to date. That juxtaposition is the
headline.

## The headline finding

**Spec-mandated retry-safety does not predict high catch yield.**
On a corpus where Apple's protocol mandates the dedup contract,
the linter's coarse callee-name inference produced four false
positives (Diagnostics 1-4) that the SQL ground-truth pass swept.
The framework + adopter's hand-rolled guards already deliver the
contract; the linter cannot see them across function boundaries.

This refines the test-plan's expected-value model in a useful
direction. Prior rounds (`tinyfaces`, `matool`, `unidoc`) showed
that *vendor* novelty yields high catch counts. Wallet shows that
*spec-strength* novelty does not — and that's not a failure mode
of the linter; it's a *correctness signal*. The linter does not
over-fire on adopters that handle their own retry semantics
correctly.

## Methodology refinement — Fluent `.unique(on:)`

Surfaced by `personalizedPass`. The road_test_plan's blanket rule
("`.unique(on:)` → defensible") was too coarse: the DB rejects
the duplicate, but Fluent's `try await X.create(on:)` propagates
the violation as a thrown error rather than swallowing it. So a
unique constraint *without* handler-side cooperation turns
duplicate-insert into a 5xx, which in a spec-mandated retry
context loops the retry rather than satisfying it. The constraint
is doing the wrong half of the job.

Refined rule (folded into `road_test_plan.md` §"SQL ground-truth
pass"):

> Flip a `create`-style diagnostic to defensible **only when**
> `.unique(on:)` is present *and* the handler does **one of**:
> (a) read-first, returning success on hit, or (b) catch the
> unique-violation and convert it to the spec's success status.

Both worked examples now live in the doc:
- `myfavquotes-api` — read-first (defensible).
- `wallet` — neither (real catch, despite `.unique(on:)`).

## New adoption gap surfaced

**`cross-function-dedup-guard-not-propagated`.** Three of the
five Run A diagnostics on Wallet (Diagnostics 1-3) fired because
body-level inference reads `createRegistration` in isolation and
does not propagate the upstream `if r != nil { return .ok }`
guard back across the function boundary. Sequential retry of
`registerPass` is safe in practice; the linter cannot see this
without flow-sensitive cross-function analysis.

**1-adopter so far** — parked, not promoted. The Wallet shape is
distinctive (Apple-spec hand-rolled compliance); whether the same
pattern appears in non-spec-mandated adopters is open. Watch on
the next two Vapor/Fluent rounds.

## State at close of window (delta only)

- **Linter slices**: 23 shipped (unchanged).
- **Real-bug count**: 17 → **18 shapes across 10 adopters**
  (+1 from wallet's `personalizedPass`). None filed this round
  yet — the wallet upstream is MIT-licensed and feasible to file
  against; deferred pending a triage decision.
- **Adoption gaps named**: +1
  (`cross-function-dedup-guard-not-propagated`, 1-adopter).
- **Email-on-retry slice**: still 2-adopter evidence, still
  parked.
- **Documentation**: `road_test_plan.md` refined; no other doc
  changes.
- **Memory**: `MEMORY.md` index updated with the heuristic
  refinement memory, pointing to the now-canonical
  `road_test_plan.md` location.

## Pre-committed questions, answered

The trial-scope.md committed four questions; the
trial-retrospective.md answers them in detail. Synthesised here:

1. **Cross-function guard recognition**: no, body inference
   doesn't propagate guards across function boundaries — surfaced
   the new adoption-gap name.
2. **Real-bug discovery on personalize**: yes, and the
   unique-constraint-makes-it-worse subtlety drove the
   `road_test_plan.md` refinement.
3. **Observational classification**: yes, `req.logger.notice`
   is correctly classified.
4. **Multi-target Sources/**: single-root scan covers it
   (Wallet has one `Package.swift`, three modules — different
   shape from vapor/hummingbird-examples).

## Cross-window pattern worth recording

**The road_test_plan's heuristics are themselves under
methodology pressure.** Prior rounds extended the SQL
ground-truth pass with worked examples (isowords' upserts,
Penny's bare DynamoDB, myfavquotes-api's Fluent reads). This
round refined a *rule* rather than adding a *worked example* —
the prior rule was correct in intent but coarsely stated. The
fix preserved the existing worked example
(`myfavquotes-api` still defensible) while adding the
counter-example (`wallet`).

This is the second methodology refinement in two retrospectives
(the prior one was the "rm -rf .build after linter
fast-forwards" addition from tinyfaces, commit `ec710f7`). Both
were triggered by a single round's evidence; both held under
re-reading. The pattern: **single-round refinements to
methodology are durable when the round's specific failure mode
maps cleanly to a rule statement.** Multi-round patterns get
synthesised into worked examples; single-round failure modes
get refined into rule footnotes.

## Recommended opener for the next session

The branches from `retrospective-2026-05-04.md` remain valid;
two of the three suggested adopter probes are still unexplored:

- **Parse CloudCode triggers** (`netreconlab/parse-server-swift`)
  — different framework, different retry semantics.
- **GraphQL mutation resolvers** (graphiti round only exercised
  queries) — known DSL-shape opacity from round 15; mutations
  may surface a different sub-shape.

If a slice ship is warranted: email-on-retry remains the highest-
value parked candidate (2-adopter cross-vendor evidence
unchanged).

If triage filings are warranted: the wallet `personalizedPass`
catch is fileable (MIT-licensed upstream, clean shape, single
fix — wrap the create in a read-first or do/catch). Tinyfaces
Stripe customer orphan is still the highest-impact target but
remains gated on the LICENSE-file blocker.

If winding down is warranted: same posture as the prior two
retrospectives — both workstreams in post-criteria-met mode.

## Closing note

The prior retrospective's quiet claim — *"the methodology rules
are also load-bearing"* — picked up another data point this
window. The `.unique(on:)` heuristic was load-bearing in the
sense that it would have produced a wrong "defensible" verdict
on Wallet's `personalizedPass` without the refinement. The fix
is a footnote, not a redesign — but the *footnote-shaped*
quality is the lesson. Methodology improves by accumulating
specific cases that didn't fit the previous rule, not by
re-architecting the rule.

The next round — whichever target — will either confirm this
pattern (another rule footnote) or break it (a rule rewrite).
The honest read says footnote; the value-of-information says run
the round and find out.
