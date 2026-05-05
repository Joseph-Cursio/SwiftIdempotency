# SwiftIdempotency Retrospective — 2026-05-04

A 10-day-window synthesis sitting on top of
[`retrospective-2026-04-24.md`](retrospective-2026-04-24.md). That
document is the close-out for the full arc through 10 Option B
adopter trials and 22 shipped linter slices; this one only covers
what changed since.

## What landed in the window

- **Five new linter road-test rounds** (rounds 14–18): grpc-swift-2,
  graphiti, matool, tinyfaces, unidoc.
- **One new Option B trial** (round 11 of the package-integration
  series): hummingbird-auth-jwt.
- **One shipped linter slice**: slot 23 — switch-dispatch deep-chain
  inference (`SwiftProjectLint#35`).
- **One adopter spike**: `swift-property-based` adopted into both
  repos as a test-target dependency; nine property tests live across
  the two repos. Surfaced one Phase-3 backlog item.
- **User-facing doc series**: `USER_GUIDE.md` (1038 LOC),
  `TUTORIAL.md` (572 LOC), `REFERENCE.md` (2720 LOC) — net +4.3k LOC
  of consumer-facing documentation, separating prose from the
  authoritative `idempotency-macros-analysis PRD.md`.
- **Internal hygiene pass**: marker-macro direct-invocation tests
  (+132 LOC), `__idempotencyInvokeTwice` runtime tests (+111 LOC),
  `identifier_name` lint fixes, force-unwrap → `#require` cleanup,
  access-modifier tightening.
- **No new shipped versions.** Package remains at v0.3.1; no API
  surface changed in-window.

## Linter rounds 14–18

All five were measured at SwiftProjectLint slot-tip with the
trial-fork-authoritative road-test workflow. Each surfaced ≥1
real-bug shape; one (unidoc) triggered a slice promotion.

| # | Round | Date | Stack | First-of-kind | Real-bug shapes | Slice impact |
|---|---|---|---|---|---|---|
| 14 | grpc-swift-2 | 2026-04-25 | gRPC + protobuf | First gRPC | `RPCWriter.write` (2 fires); SwiftProtobuf bare-init (5 fires) | 1-adopter parks |
| 15 | graphiti | 2026-04-25 | GraphQL DSL | First GraphQL | (none — DSL field-binding invisible to body inferrer) | Negative evidence on slot 3 trigger |
| 16 | matool | 2026-04-25 | AWS Lambda + Cognito | First **production-app** Lambda | `adminCreateUser` × 2 (DistrictController.post + .postReissue) | 1-adopter park; **closed CLAUDE.md FP-rate gap** for Lambda |
| 17 | tinyfaces | 2026-04-26 | Vapor + Stripe + Brevo | First Stripe-using adopter | Stripe customer orphan; magic-link email-on-retry; checkout-session reissue (3 shapes total — 6/6 yield, **best round to date**) | Stripe-kit whitelist parked at 1-adopter; **email-on-retry promoted to 2-adopter slice candidate** (matool + tinyfaces, vendor-independent) |
| 18 | unidoc | 2026-04-26 | Vapor + MongoDB + capped collections | First **MongoDB-backed adopter** | RepoFeed duplicate-on-retry (capped-collection bounded); OAuth code-exchange / user-create UI inconsistency | **Slot 23 trigger** (2-adopter switch-dispatch deep-chain with myfavquotes-api precedent); enum-case-pattern FP parked at 1-adopter |

**Real-bug count at end of window**: 17 shapes across 9 of the 18
linter-rounds (Penny ×4, isowords ×2, prospero ×1, myfavquotes-api
×1, luka-vapor ×1, hellovapor ×1, matool ×2, tinyfaces ×3,
unidoc ×2). Two filed pre-window (HelloVapor #1, prospero #8); none
new this window.

### The matool retrospective correction

Worth recording because it's a class of subtlety the methodology
hadn't surfaced before: the matool Run-A's `adminCreateUser` fires
were initially scored as 4/6 catches, but on second pass the actual
retry-mechanism mapping changed the count to 2 real-bug catches
after the data-layer audit, with the other 2 reclassified as
defensible. The retrospective doc was corrected in commit `8ad8b04`.
Adopter-side fork was deleted by the author on request before the
linter PR could be filed (commit `b9879d1`). The corrective edit is
the visible artefact; the methodology lesson is **scoring needs the
data-layer audit, not just the call-graph audit**, on Lambda
handlers — at-least-once retry mechanics interact with the SDK's
own dedup, and not all "fires" map to user-visible duplicates.

## Slot 23 — switch-dispatch deep-chain inference

Triggered by 2-adopter evidence on 2026-04-26 (myfavquotes-api
precedent + unidoc fresh signal). Investigation showed the original
slot framing was wrong: not a switch-traversal bug but a
storage-gate bug. The pre-fix `entriesBySignature[sig] == nil`
guard suppressed upward inference for any signature already in the
table — including signatures with only a `@lint.context` annotation
and no `@lint.effect`. Sub-handlers annotated `@lint.context
replayable` had their body's non-idempotent classification
correctly computed but never stored, so callers saw nothing.

One-line fix (`entriesBySignature[sig]?.effect == nil`).
Field-verified on the unidoc trial: dispatcher
`WebhookOperation.load(with:)` regained 2 fires (lines 75 + 82) on
the `handle(...)` calls via 2-hop upward inference through the
switch arms. Shipped as PR #35 on the same day the slot was
promoted.

**Methodology takeaway**: the sweep-then-verify pattern from the
prior retrospective held — the slot sat parked at 1-adopter (just
myfavquotes-api) for 12 rounds before unidoc surfaced the second
adopter. Resisting the urge to ship at 1-adopter was correct: when
unidoc finally fired, the verification step caught that the
implementation was simpler than the original framing assumed.

## Round 11 — hummingbird-auth-jwt (Option B)

**First Hummingbird-shape Option B trial.** Test-target-only
integration against `hummingbird-project/hummingbird-examples/auth-jwt`.
Three trial tests pass on the same `swift test` invocation that
runs auth-jwt's two pre-existing tests; zero frictions in the
SwiftIdempotency public surface itself.

| Question | Answer | Doc impact |
|---|---|---|
| Q1 — does the recorder mock idiomatically over Fluent? | Partial: the `IdempotentEffectRecorder` conformance is unchanged from Penny, but Fluent's `Model.query(on: db)` static-method shape forces a `UserRepositoryProtocol` extraction. Production Hummingbird DI codebases get Option B for free; example-shape code needs the refactor. | USER_GUIDE Hummingbird subsection should mention this presupposition |
| Q2 — does Option B handle "throw on retry"? | Yes for snapshot mechanism (`effectCount == 1` after both calls). No for end-to-end helper without a swallow-conflict `do/catch` wrapper around the body. | USER_GUIDE pattern recipe needed |
| Q3 — does Option C give a useful diagnostic on `login`? | Accurate but actionably ambiguous on `Date()`-in-payload returns. Doesn't lead the reader to `@NonIdempotent`. | Diagnostic-message improvement parked |
| Q4 — refactor cost for full adoption? | 30–40 LOC for protocol extraction + DI rewiring. Higher than Penny's per-handler estimate (~15–25 LOC) because auth-jwt is example-shaped, not DI-shaped. | None |

**Four frictions surfaced** — all in the trial's mock authoring
layer, none in `SwiftIdempotency`'s own surface:

1. `NSLock.unlock()` unavailable in async contexts (Swift 6
   strict-concurrency × Foundation).
2. `Sendable` + mutable stored properties on
   `IdempotentEffectRecorder` conformer — resolved with
   `@unchecked Sendable`, matching auth-jwt's own `final class
   User: Model, @unchecked Sendable` pattern.
3. Unused `if let existing = ...` binding warning.
4. Unnecessary `try` on rethrowing `assertIdempotentEffects` with
   non-throwing body.

**Carry-overs to the documentation surface** (deferred to the next
session): `@unchecked Sendable` mock pattern is undocumented;
"throw on retry" shape needs an explicit pattern recipe;
`#assertIdempotent`'s failure message could nudge toward
`@NonIdempotent` for "non-idempotent by design" cases.

**No fork pushed this round.** Trial deliverable is the scope +
findings docs plus inline code; no upstream-PR pressure on this
round (purely additive integration, no source modifications).

## swift-property-based adoption

Surfaced 2026-04-24 in the prior session window's tail; the
findings doc lives at
[`property-based/trial-findings.md`](property-based/trial-findings.md).
Nine property tests now live across the two repos:

- **7 lattice-law tests** on `SwiftProjectLint`'s
  `UpwardEffectInferrer.leastUpperBound` — exercised the lattice
  semantics that were previously only example-tested.
- **2 wrap-pattern demonstrations** on `#assertIdempotent` —
  green-path adoption of the pattern; the package itself didn't
  need to change to absorb PBT.

**One backlog item surfaced** (Phase 3): `#assertIdempotent` fails
via `precondition`, terminating the test process. On a failing
`propertyCheck` iteration the process dies before PropertyBased's
shrinker can minimise the counter-example — property-based users
get the raw random input rather than a shrunk one. Fix direction is
a `failureMode: IdempotencyFailureMode` parameter mirroring the
existing `assertIdempotentEffects` R1 surface (issueRecord vs.
preconditionFailure). Trigger is the first PBT wrap pattern that
surfaces a failing property where the raw random input isn't
immediately diagnostic.

This is **the third refinement-class item that the Penny R1/R2/R3
arc didn't anticipate** — different surface, same shape: a
test-target consumer that wants a non-fatal failure path. Worth
remembering for future API-shape decisions.

## User-facing doc series

The single 1850-line `idempotency-macros-analysis.md` was renamed
to `idempotency-macros-analysis PRD.md` (commit `4446a06`) to make
its role explicit, and three consumer-facing docs were authored:

- **`USER_GUIDE.md`** (1038 LOC) — narrative introduction, when to
  reach for each tool, foundational concepts (atomic vs.
  unconditional idempotency, partial failure / retry contract),
  framework-integration sections.
- **`TUTORIAL.md`** (572 LOC) — guided walkthrough of the four
  attribute macros + `#assertIdempotent` + Option B over a single
  worked example.
- **`REFERENCE.md`** (2720 LOC) — exhaustive API reference: every
  public type, every parameter, every failure mode, every
  expansion shape. Authoritative for "what does this attribute do?"
  questions.

The previous shape — README pointing at the PRD for everything —
forced readers into a 1850-line design proposal to look up
parameter names. The new layout splits **PRD** (proposal,
historical) from **REFERENCE** (current API), with **USER_GUIDE**
and **TUTORIAL** as on-ramps.

**This is the largest documentation delta since the package was
created.** The trigger was the hummingbird-auth-jwt trial flagging
that the `@unchecked Sendable` mock pattern + the throw-on-retry
recipe both needed a place to live that wasn't the PRD. Rather
than expand the PRD, the doc series gave them a home.

README cross-links updated (commit `1403a70`); stale Option B text
fixed in the same commit.

## Internal hygiene

Four commits in-window touched the package's own code (no API
changes):

- **`a7bee6f`** — rename short identifiers to satisfy
  `identifier_name` (3+ char minimum from global preferences).
- **`7cc3a8f`** — runtime coverage tests for
  `__idempotencyInvokeTwice` (+111 LOC). Closed a coverage hole
  from the swift-testing-pro review.
- **`df3f473`** — direct-invocation coverage for marker macro
  bodies (+132 LOC). Same review.
- **`ebe19ea`** — tighten access modifiers + replace force-unwrap
  with `#require`.

Test count grew from the prior end-of-window total. No regressions;
all green throughout.

The `road_test_plan.md` doc gained a small but meaningful update
(commit `ec710f7`): "rm -rf .build after linter fast-forwards".
Stale build cache was misleading a round in the tinyfaces
investigation; the corrective documentation is the visible
artefact.

## Cross-window patterns worth recording

### Email-on-retry as a 2-adopter slice candidate

The matool round catches Cognito's `adminCreateUser` (which sends
an invitation email by default when `messageAction == nil`); the
tinyfaces round catches Brevo's `SendInBlue.sendEmail` for
magic-link auth. **Different vendors, identical shape**: external
email API called inside a `replayable` handler with no
caller-supplied dedup key, both produce user-visible duplicate
emails on LB retry.

This is the first cross-vendor 2-adopter promotion since the
HttpPipeline / Vapor / Hummingbird router DSL slices, and it
ratifies the test-plan's predicted "shapes that cross vendor
boundaries are the highest-value 2-adopter triggers" axiom.

Slice direction (parked, not yet shipped): extend
`idempotentReceiverMethodsByFramework` to recognise common
email-API send-method shapes (`sendEmail`, `adminCreateUser`,
`sendTransactional`, etc.) under their framework imports, route to
non-idempotent verdict with a suggestion specifically pointing at
`IdempotencyKey` / `@ExternallyIdempotent(by:)`.

### Resistance to 1-adopter ships paid off twice in-window

Slot 23 sat at 1-adopter (myfavquotes-api) for 12 rounds. When
unidoc fired the second-adopter trigger on 2026-04-26, the
verification pass caught that the original slot framing was wrong:
not a switch-traversal bug but a storage-gate bug. **Had the slot
shipped at 1-adopter, the wrong fix would have shipped.**

Same dynamic likely applies to the seven still-parked candidates:
`Route.description`, `addMiddleware`, `queryParameters.require`
sibling-pair, `withSpan`, Bcrypt, `AppMetrics.push`, Axiom `emit`.
None has surfaced a second adopter across the in-window five
linter rounds. Honest read remains: several of these are probably
adopter-specific, not universal — and the cost of waiting is much
lower than the cost of shipping a wrong fix.

### "Test the existing reasoning" framing extends to Hummingbird

The prior retrospective recorded that **adopter pre-engineering is
a positive signal** — Uitsmijter's spec-compliant
`authCodeStorage.get` and HomeAutomation's
`NotificationSender` protocol meant the trial value shifted from
"here's how to fix your code" to "here's how to test-assert your
existing reasoning."

The hummingbird-auth-jwt trial extends this in the opposite
direction. auth-jwt's `dedupGuardedCreate` uses an existence-check
pattern (`if existingUser != nil throw .conflict`) that is
*reasoned correctly* by the human author — Option B's snapshot
mechanism passes, the second call doesn't write. But the
reasoning is **invisible without the trial test**. Adding the
test-target-only Option B harness turns the implicit reasoning
into an explicit regression gate. Same value framing as the
pre-engineered case, just at a different point on the
adopter-readiness spectrum.

## State at close of window

**Linter slices**: 23 shipped. No named slice currently queued. The
email-on-retry candidate has 2-adopter evidence and could promote
at any time; remaining 1-adopter parks listed above are honest
candidates for permanent deferral pending unanticipated evidence.

**Option B**: still v0.3.1. Eleven production adopter trials with
the v0.3.0 shape held across all of them. Hummingbird-auth-jwt is
the eleventh and the first Hummingbird example-shape adopter; it
surfaced documentation gaps (carry-overs) but no API friction.

**Documentation**: USER_GUIDE / TUTORIAL / REFERENCE separation
established. PRD renamed to clarify role. ~4.3k LOC of new
consumer-facing prose; no new code shipped.

**Adopter pull**: 17 real-bug shapes across 9 adopters; 2 filed,
15 parked. No new filings this window. The tinyfaces Stripe
customer orphan remains the highest-impact unfiled shape (gated on
TinyFaces' missing LICENSE file).

**Property-based**: adopted in test targets; Phase-3 non-fatal
`#assertIdempotent` failure-mode item parked.

## Recommended opener for the next session

If the doc-series carry-overs are the priority: extend USER_GUIDE
with a Hummingbird subsection covering the protocol-extraction
presupposition; add a "throw on retry" pattern recipe; add an
`@unchecked Sendable` mock callout to the `IdempotentEffectRecorder`
doc comment.

If a new adopter probe is warranted: domain/shape novelty, not
obscurity. Unexplored candidates (carried from the prior
retrospective): Apple Wallet pass issuance
(`vapor-community/wallet`), Parse CloudCode triggers
(`netreconlab/parse-server-swift`), GraphQL **mutation** resolvers
(graphiti round only exercised query resolvers).

If a slice ship is warranted: email-on-retry has 2-adopter evidence
sitting on the table, would close the highest-value parked
candidate.

If triage filings are warranted: 15 parked shapes, with the
tinyfaces Stripe customer orphan as the highest-impact target
(blocked on adopter LICENSE file).

If winding down is warranted: same posture as the prior
retrospective — both workstreams remain in post-criteria-met
mode; no urgent next-step exists, only optional ones.

## Key documents (added this window)

- `docs/USER_GUIDE.md` / `docs/TUTORIAL.md` / `docs/REFERENCE.md`
  (root-level repo docs).
- `docs/grpc-swift-2/`, `docs/graphiti/`, `docs/matool/`,
  `docs/tinyfaces/`, `docs/unidoc/` — round 14–18 trial folders.
- `docs/hummingbird-auth-jwt-package-trial/` — Option B round 11.
- `docs/property-based/trial-findings.md` — PBT adoption notes.

## Closing note

The prior retrospective's load-bearing observation was that
**doc-comment annotations as the three-consumer interoperability
surface holds across heterogeneous adopters**. Nothing in this
window contradicts it. What this window adds is evidence for a
quieter adjacent claim: **the methodology rules are also
load-bearing**. Resisting 1-adopter ships caught a wrong fix
(slot 23). The "is this just adopter-specific?" filter caught
several speculative slices (the seven still-parked candidates)
that would have been overfit. The "domain/shape novelty" selection
criterion produced first-of-kind evidence on Stripe (tinyfaces),
MongoDB (unidoc), and Hummingbird Option B (auth-jwt) — three
genuinely different stacks in five rounds.

The pattern for the next phase, if there is one, is: keep the
methodology, let evidence drive promotions, prefer documentation
to API-surface expansion.
