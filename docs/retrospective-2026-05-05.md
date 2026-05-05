# SwiftIdempotency Retrospective — 2026-05-05

A single-day-window addendum sitting on top of
[`retrospective-2026-05-04.md`](retrospective-2026-05-04.md).
That document closed with three "what to do next" branches; this
session executed the **new-adopter-probe** branch *twice* —
first against Apple Wallet (`vapor-community/wallet`), then
against Parse Cloud Code (`netreconlab/parse-server-swift`). Two
rounds completed, one methodology refinement landed.

## What landed in the window

- **Two linter road-test rounds**:
  - Round 19 — `wallet` (Apple Wallet Web Service Protocol).
    Trial fork `Joseph-Cursio/wallet-idempotency-trial`, branch
    `trial-wallet`. Findings under
    [`docs/wallet-package-trial/`](wallet-package-trial/).
  - Round 20 — `parse-server-swift` (Parse Cloud Code hooks).
    Trial fork `Joseph-Cursio/parse-server-swift-idempotency-trial`,
    branch `trial-parse`. Findings under
    [`docs/parse-server-swift-package-trial/`](parse-server-swift-package-trial/).
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

## Round 20 — parse-server-swift

**First Parse-shape adopter; demo-shaped corpus.**
`netreconlab/parse-server-swift` is a template/library hybrid
whose `exampleRoutes` demonstrates the Parse Cloud Code hook
idiom — 9 inline trailing closures (2 Cloud Functions, 7 Hook
Triggers) all read-only or log-only. No write-bearing callees in
any handler. The annotation went on the registration helper
(`exampleRoutes`); the inferrer walks all 9 closures.

| | |
|---|---|
| Run A | 0 issues — every handler silent |
| Run B | 49 strict-only fires across three clusters |
| Yield | 0 / 9 = **0.00** |

The 0-yield outcome was *predicted in the scope doc* — CLAUDE.md
flags the awslabs swift-aws-lambda-runtime corpus as the
canonical "demo-shaped → 0 Run A yield" pattern, and Parse
reproduced it. The round's value is not in the catch count.

**Three findings worth keeping**:

1. **First ParseSwift framework-whitelist evidence** (24 fires:
   `ParseHookResponse` ×11, `ParseError` ×4, `hydrateUser` ×3,
   `GameScore` ×2, `findAll` ×2, `options` ×1, `information` ×1).
   Parked at 1-adopter per the methodology; not promotable.
2. **`checkHeaders` cascade pattern** — 10 strict fires from a
   single adopter helper whose body inference is itself blocked
   by an underlying Vapor whitelist gap (`req.headers.first`).
   Documents that a single primitive-level whitelist addition can
   collapse a ten-fire cluster. Useful as Vapor whitelist priority
   evidence, not a new adoption-gap class.
3. **Retry-semantics documentation gap** — no authoritative source
   documents parse-server's hook 5xx retry behavior. Adopters
   annotating Parse hooks as `@lint.context replayable` are
   making an *unverifiable* judgement call about which retry loop
   they're modeling (server retry vs. application-client retry).
   This is recorded as a Parse-specific policy note in the
   trial-retrospective; not folded into `road_test_plan.md`
   (too narrow at 1-adopter).

**Annotation pattern confirmation**: the inline-trailing-closure-
via-registration-helper pattern from road_test_plan §103-117
works on the single-helper-with-many-closures shape (one
annotation, nine handlers in scope). Prior evidence (prospero)
covered the multi-helper case; this extends to the single-helper
case.

## State at close of window (delta only)

- **Linter slices**: 23 shipped (unchanged).
- **Real-bug count**: 17 → **18 shapes across 11 adopters**
  (+1 from wallet's `personalizedPass`; +1 adopter from parse,
  zero new shapes). The wallet `personalizedPass` finding remains
  unfiled (MIT-licensed, feasible, deferred at user discretion).
- **Adoption gaps named**: +1
  (`cross-function-dedup-guard-not-propagated`, 1-adopter,
  surfaced by wallet).
- **Framework whitelist evidence**: +1 framework
  (ParseSwift cluster, 1-adopter, parked).
- **Email-on-retry slice**: already shipped (SwiftProjectLint
  `ec33d32`, 2026-04-26 — a one-line suggestion-text rewrite in
  `NonIdempotentInRetryContextVisitor` naming `IdempotencyKey`
  + `@ExternallyIdempotent(by:)`). The 2026-05-04 retrospective's
  "still parked" note was stale bookkeeping; verified on
  tinyfaces at slot tip on 2026-05-05 (commit `ecae768`).
- **Documentation**: `road_test_plan.md` refined; no other doc
  changes.
- **Memory**: `MEMORY.md` index updated with the heuristic
  refinement memory, pointing to the now-canonical
  `road_test_plan.md` location.

## Pre-committed questions, answered

Each round committed four questions in its scope doc; each
trial-retrospective answers them in detail. Synthesised here:

**Wallet**:
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

**Parse**:
1. **Run A yield matches prediction?** Yes — 0/9, awslabs-shape
   confirmed. Demo-shaped corpus does not exercise the failure
   modes the linter is built to find.
2. **Annotation pattern ergonomics on single-`exampleRoutes`
   shape**: works correctly. Single annotation reaches all 9
   inline closures — extends prior multi-helper evidence
   (prospero) to the single-helper case.
3. **ParseSwift framework-whitelist cluster shape**: 24 fires
   across three sub-shapes (value-typed inits, query reads,
   user-read helper). Inaugural ParseSwift evidence; parked at
   1-adopter.
4. **Retry-semantics documentation gap**: confirmed. No
   authoritative source documents parse-server's hook 5xx
   retry behavior; adopters annotating Parse hooks are making
   an unverifiable judgement call about which retry loop they
   model. Recorded as Parse-specific policy guidance, not folded
   into road_test_plan.md.

## Cross-window patterns worth recording

### Yield does not predict round value

Two rounds, two low yields:

| Round | Yield (excl. silent) | Round value lived in |
|---|---|---|
| 19 — wallet | 1/3 = 0.33 | `.unique(on:)` rule refinement; `cross-function-dedup-guard` adoption gap |
| 20 — parse | 0/0 (undefined) | First ParseSwift cluster; `checkHeaders` cascade pattern; retry-doc gap |

Wallet had a strong ground-truth (Apple's spec mandates the
contract); parse had none (corpus is demo-shaped). Despite
opposite ground-truth strength, both produced low yields *and*
useful methodology output. **The "high yield = good round" intuition
is wrong** — what matters is whether the round produces durable
output that survives re-reading, not how many fires hit. Three
of the round-value items above are already shipped or
load-bearing in the methodology docs.

### Methodology output classification is now stable

Combining today's two rounds with the 2026-05-04 window's matool
correction and tinyfaces' `rm -rf .build` lesson:

- **Single-round failure modes** → rule footnotes
  (`.unique(on:)` refinement; `rm -rf .build` after fast-
  forwards).
- **Multi-round patterns** → worked examples in road_test_plan
  (isowords upserts, Penny bare DynamoDB, myfavquotes-api reads
  + wallet counter-example).
- **1-adopter framework whitelist evidence** → parked
  (Stripe-kit from tinyfaces; ParseSwift from parse).
- **2-adopter cross-vendor evidence** → slice-promotable
  (email-on-retry: matool + tinyfaces, shipped 2026-04-26).
- **Methodology-narrow observations** → trial-retrospective
  policy notes, not folded (`checkHeaders` cascade; Parse
  client-vs-server retry-loop disambiguation).

This classification scheme is now load-bearing across four
retrospectives. The pattern holds: **methodology improves by
accumulating specific cases that didn't fit the previous rule,
at the right place in the doc graph for the case's adopter
count.**

## Recommended opener for the next session

One adopter probe remains unexplored from the 2026-05-04
retrospective's list:

- **GraphQL mutation resolvers** (graphiti round only exercised
  queries) — known DSL-shape opacity from round 15; mutations
  may surface a different sub-shape, but the cheap prediction
  says another 0-fire round.

A second domain-novel option, surfaced by the parse round: a
**production parse-server-swift adopter** (i.e. a downstream
project depending on the package, with write-bearing handler
bodies). Would convert the parse round's 0-yield demo measurement
into yield evidence on real handlers; gated on whether such a
public adopter exists (not surveyed).

If a slice ship is warranted: no slice currently queued.
Email-on-retry shipped 2026-04-26 (verified 2026-05-05).

If triage filings are warranted: the wallet `personalizedPass`
catch is fileable (MIT-licensed upstream, clean shape, single
fix — wrap the create in a read-first or do/catch; reproducer
sketched in this session, not committed). Tinyfaces Stripe
customer orphan still gated on LICENSE-file blocker.

If winding down is warranted: same posture as the prior two
retrospectives — both workstreams in post-criteria-met mode. Two
zero-or-near-zero-yield rounds in one session is itself a
diminishing-returns signal on adopter-probe value.

## Closing note

The prior retrospective's quiet claim — *"the methodology rules
are also load-bearing"* — picked up two data points this window
rather than the one originally written.

Wallet refined `.unique(on:)` into a worked-example pair
(myfavquotes-api defensible vs. wallet real-catch). Parse
contributed differently: it didn't refine a *rule* but did
refine the *classification scheme* by adding two cases at the
"narrower than a rule" end (the `checkHeaders` cascade; the
client-vs-server retry-loop disambiguation). Both went into
trial-retrospectives, not into `road_test_plan.md` — exactly
where the classification scheme says they belong.

This is the strongest evidence yet that **the methodology graph
is itself working**. Single-round refinements landed at the right
node; 1-adopter cluster evidence stayed parked; 2-adopter
cross-vendor evidence had already shipped (email-on-retry); two
zero-or-near-zero-yield rounds produced durable output anyway.

The next round, whenever it happens, will either find a fourth
pattern that fits the existing classification scheme or surface
a case that doesn't. The honest read says fits — but the
value-of-information argument that ran two rounds today still
applies: the cost of a round is small, and the diminishing-
returns signal from two consecutive low-yield rounds is itself
information about whether to keep probing.
