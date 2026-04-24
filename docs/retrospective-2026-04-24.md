# SwiftIdempotency Retrospective — 2026-04-24

A synthesis across the full arc of shipped work: 10 production
adopter package-integration trials, 22 shipped linter slices, and
the design conversations that shaped both. Written as a close-out
document, not a per-round findings note — the individual round
docs under `docs/*-package-trial/` and `docs/phase*-round-*/` are
the primary source material.

## The two deliverables

This repo's original scope statement (see
`docs/idempotency-macros-analysis.md` §"Scope: What Belongs in
This Repo") split the work into two artefacts:

1. **SwiftIdempotency package** (this repo) — `@Idempotent`,
   `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`,
   `@IdempotencyTests`, `#assertIdempotent`, `IdempotencyKey`, plus
   the Option B `IdempotentEffectRecorder` / `assertIdempotentEffects`
   surface.
2. **SwiftProjectLint rules** (separate repo
   `Joseph-Cursio/SwiftProjectLint`) — doc-comment-annotation-driven
   static analyzer: `@lint.context <replayable|strict_replayable>`,
   the framework whitelist, the heuristic effect inferrer,
   receiver-type resolver, prefix-lexicon matching, tuple-equality
   structural rule.

Both are production-shipping today (SwiftIdempotency at v0.3.1;
SwiftProjectLint at slot-22 tip `a1024ac`).

## Shipped SwiftIdempotency versions

| Version | Ship date | Headline |
|---|---|---|
| 0.1.0 | 2026-04-23 | First SPI-eligible release. `@Idempotent` / `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent(by:)` attribute macros; `@IdempotencyTests` extension macro; `#assertIdempotent` freestanding macro; `IdempotencyKey` strong type. Three consumer samples exercise the full user-facing surface. Apache-2.0. SPI submission filed as `SwiftPackageIndex/PackageList#13283`. |
| 0.2.0 | 2026-04-23 | Added opt-in `SwiftIdempotencyFluent` library with `IdempotencyKey.init<M: Model>(fromFluentModel:)` routing through FluentKit's `requireID()`. Closes the Fluent adopter friction surfaced in the hellovapor package trial (Model not Identifiable, Optional ID rejecting CustomStringConvertible). Non-Fluent adopters pay zero — gated on opt-in to the new product. |
| 0.3.0 | 2026-04-23 | Option B shipped. `IdempotentEffectRecorder` protocol + `assertIdempotentEffects` helper in `SwiftIdempotencyTestSupport`. Three pre-ship refinements from the Penny trial landed in one session: R1 `failureMode: IdempotencyFailureMode` parameter (adds `.issueRecord` alongside default `.preconditionFailure`), R2 `associatedtype Snapshot: Equatable = Int` for richer-than-count state, R3 protocol moved from TestSupport to main `SwiftIdempotency` target for observability conformers. Six consumer samples in `examples/`. |
| 0.3.1 | 2026-04-23 | Patch: relaxed swift-syntax pin from `exact: "602.0.0"` to `"602.0.0"..<"604.0.0"`. Surfaced by Penny bug-sweep trial pinning vs. DiscordBM's `@UnstableEnum` swift-syntax-603 requirement. Both 602 and 603 verified 74/74 green. |

## Linter slice history

22 shipped slices, numbered sequentially. Each has `docs/rules/*.md`
spec in the SwiftProjectLint repo plus per-slot road-test transcripts
in this repo.

| Slot | Ship date | Shape | Evidence bar met |
|---|---|---|---|
| 2 | pre-session | `.init(...)` member-access form gap | purely structural |
| 4 | pre-session | Escape-wrapper recognition (pointfreeco-specific, closed) | 1-adopter → held |
| 5 | **deferred** | Perf fix on the inference loop | no stressing corpus |
| 6 | shipped | Macro-form validation (all 4 attribute macros) | N/A |
| 7 | pre-session | pointfreeco findings verification | N/A |
| 8 | pre-session | swift-nio remeasurement | N/A |
| 9 | pre-session | AWS Lambda adopter road-test | N/A |
| 10 | pre-session | Lambda response-writer framework whitelist | 1-adopter + structural |
| 11 | pre-session | Housekeeping | N/A |
| 12 | pre-session | Linter crash on duplicate file basenames | 1-adopter crash fix |
| 13 | PR #21 | Prefix-lexicon gap for server-app verbs | 1-adopter (isowords) |
| 14 | PR #22 | `HttpPipeline` framework whitelist | 2-adopter (isowords + pointfreeco) |
| 15 | pre-session | Housekeeping from isowords retrospective | N/A |
| 16 | PR #23 | Hummingbird Router DSL whitelist | 2-adopter (prospero + hummingbird-examples) |
| 17 | PR #24 | Vapor routing DSL whitelist | 2-adopter (luka-vapor + hellovapor) |
| 18 | PR #25 | Cross-framework `parameters.get` whitelist | 2-adopter (prospero + HelloVapor) |
| 19 | PR #26 | FluentKit `import Fluent` alias | 1-adopter precision uplift (hellovapor) |
| 20 | direct-to-main | `tuple-equality-with-unstable-components` rule | structural, 0-fire corpus baseline (13 → 17 adopters) |
| 3 | **deferred** | Property-wrapper receiver resolution | no adopter collision |
| **21** | **PR #27 (this session)** | **Vapor `app.register(collection:)` whitelist** | **3-adopter (HelloVapor + Uitsmijter + plc-handle-tracker)** |
| **22** | **PR #28 (this session)** | **Swift Concurrency `Task.sleep` whitelist** | **4-adopter (hummingbird-examples + Uitsmijter + HomeAutomation + Vernissage)** |

**No named slice is currently queued.** Seven 1-adopter candidates
remain parked awaiting second-adopter evidence.

## Adopter corpus — 10 production Option B trials

All 10 adopters carry SwiftIdempotency 0.3.1 pinned in a test target
and demonstrate the `IdempotentEffectRecorder` surface on a
canonical shape from their own code. Each trial is test-target-only;
no production-code changes; non-contribution-fork convention
preserved across all 10.

| # | Adopter | Shape class | Framework stack | Trial branch | Option B refactor LOC |
|---|---|---|---|---|---|
| 1 | `vapor/penny-bot` | Lambda handler | AWS Lambda + SotoDynamoDB + DiscordBM | `bug-sweep` | ~35-50 |
| 2 | `pointfreeco/isowords` | HTTP handler | PointFree HttpPipeline | `trial-isowords` | N/A (linter only) |
| 3 | `samalone/prospero` | HTTP handler | Hummingbird | `trial-prospero` | N/A (linter only) |
| 4 | `kicsipixel/myfavquotes-api` | HTTP handler | Hummingbird + FluentKit | `trial-myfavquotes` | N/A (linter only) |
| 5 | `kylebshr/luka-vapor` | HTTP handler | Vapor | `package-integration-trial` | ~20 |
| 6 | `sinduke/HelloVapor` | HTTP handler | Vapor + FluentKit | `package-integration-trial` | ~10 (post-v0.2.0) |
| 7 | `VernissageApp/VernissageServer` | ActivityPub inbox | Vapor + FluentKit + Soto + Redis + JWT + SwiftExif + SwiftGD | `package-integration-trial` + `bug-sweep` | ~10-15 |
| 8 | `kphrx/plc-handle-tracker` | vapor/queues AsyncJob | Vapor + FluentKit + vapor/queues | `package-integration-trial` | ~10-15 |
| 9 | `JulianKahnert/HomeAutomation` | APNs push delivery | Vapor + APNSwift + MySQL Fluent + TCA + swift-distributed-actors | `package-integration-trial` | ~5-8 |
| 10 | `uitsmijter/Uitsmijter` | OAuth2 code redemption | Vapor + JWT + swift-crypto + swiftkube/client + SwiftPrometheus + Soto + JXKit | `package-integration-trial` | ~0 (already spec-compliant) |

**27 green Option B tests** across all trials (Penny 8 + Vernissage 9
+ plc-handle-tracker 3 + HomeAutomation 3 + Uitsmijter 4).
**10-for-10 shape coverage** on `IdempotencyKey` /
`@ExternallyIdempotent(by:)` / `IdempotentEffectRecorder`.

## Cross-adopter shape patterns — what we actually learned

### External idempotency key shapes, ranked by adopter clarity

1. **RFC-mandated token field** — Uitsmijter's OAuth2 `code`
   parameter (RFC 6749 §4.1.2). Spec makes the shape unambiguous.
2. **Named UUID in the payload** — plc-handle-tracker's
   `Payload.historyId: UUID`. Explicitly modelled by the adopter.
3. **Public protocol parameter with doc-commented semantics** —
   HomeAutomation's `NotificationSender.sendNotification(title:message:id:)`,
   where `id` is documented as "a stable id used as
   `apns-collapse-id` and `threadIdentifier`".
4. **URL field on the incoming activity** — Vernissage's
   `activity.id`. Not modelled as a dedicated field but has
   protocol-level stability guarantees (ActivityPub spec).
5. **Request parameters inferred from content** — Penny / isowords /
   prospero / myfavquotes-api. Adopter picks a combination of
   request fields (user ID + target ID + verb) to synthesize a key.

The **cleanliness of the external key is a direct predictor of
adopter-side refactor cost.** Uitsmijter paid ~0 LOC because the
cleanup was already done; Penny paid 35-50 LOC because the key had
to be synthesized and wired through multiple service layers.

### Side-effect class coverage

Across the 10 adopters, the Option B surface was exercised on:

- Database writes (Postgres + MySQL Fluent, DynamoDB via Soto)
- Redis writes (session storage, dedup caches, lock-keys)
- HTTP requests out (Discord webhooks, external APIs, Tibber, APNs)
- Queue job dispatches (vapor/queues, implicit Lambda re-delivery)
- Cryptographic signing (JWT issuance)
- Kubernetes CRD status updates (swiftkube/client)
- Observability emissions (Prometheus counters, swift-log)
- File-storage operations (S3 PUT via Soto)
- AsyncStream consumption (HomeKit event processing)
- Email delivery (Vernissage signup welcome)

The default `Snapshot = Int` handled all of these. Custom
`Snapshot = [String]` was exercised once (Vernissage bug-sweep
avatar-upload S3 keys) to prove the opt-in precision mechanism
works.

### Multi-effect-per-invocation bodies don't destabilise the recorder

HomeAutomation's N-device-token APNs fan-out (3 effects per send)
and Uitsmijter's 4-distinct-side-effect OAuth2 redemption body
both pass `assertIdempotentEffects` cleanly. The recorder's
snapshot is taken around the *whole body*, not per-call, so
heterogeneous-effect bodies work out of the box.

### Adopter pre-engineering is a positive signal, not a negative one

HomeAutomation's `NotificationSender` was already extracted as a
`Sendable` protocol with documented semantics. Uitsmijter's
`authCodeStorage.get(...,remove: true)` was already
spec-compliant. In both cases, **the trial's value shifted from
"here's how to fix your code" to "here's how to test-assert your
existing reasoning"** — which is actually the more valuable
long-term framing, because it turns into regression tests that
catch future accidental un-doings.

## Option B API evolution — the Penny-to-Uitsmijter arc

The Option B surface went through three refinements between the
Penny bug-sweep prototype and the v0.3.0 ship (R1/R2/R3 documented
in the Penny retrospective). Subsequent adopter rounds held the
v0.3.0 shape with zero friction:

- **Vernissage (2026-04-23)** — first external adopter. No friction
  across inbox + 3 bug-sweep shapes.
- **plc-handle-tracker (2026-04-24)** — first AsyncJob shape. No
  friction.
- **HomeAutomation (2026-04-24)** — first pre-extracted adopter
  protocol. No friction.
- **Uitsmijter (2026-04-24)** — first RFC-mandated shape, first
  stdlib-heavy dep graph, first Kubernetes-API adopter. No friction.

**Four consecutive zero-friction fresh-signal rounds** closes the
Option B API-stability question. The selection criterion was
explicitly retired (phase-2 memory updated 2026-04-24) from
"obscure single-contributor" to "domain/shape novelty" since the
original obscurity heuristic had served its purpose.

## Sweep methodology — a cheap path from 1-adopter to ship-eligibility

Before 2026-04-24, slice promotion followed the road-test pattern:
annotate 3-6 handlers, run replayable + strict_replayable scans,
capture transcripts, compare. ~2-3 hours per adopter per slice.

The 2026-04-24 trial-adopter lint sweep demonstrated a
**cheaper path**: bare-scan + grep + verification annotation + two-run
scan. Total time per slice: ~60 minutes (30 for sweep, 30 for
verification).

- **Sweep step** (~30 min per adopter, parallelisable) — bare scan
  the adopter with slot-tip CLI, grep the source for each parked
  1-adopter candidate's receiver-method pattern, count match sites.
  Any candidate matching 2+ adopters promotes to ship-eligible.
- **Verification step** (~30 min per slice) — annotate one function
  per shape in the trial fork, scan at both pre-ship and post-ship
  SwiftProjectLint tips, confirm the predicted diagnostic delta
  exactly matches the slot definition.

This worked for slot 21 (`app.register`) and slot 22 (`Task.sleep`)
because both were receiver-method-shape-narrow. It wouldn't scale
to slices that require behavioural testing (e.g., structural rules
like slot 20's tuple-equality) — those still need the full
road-test or synthetic fixtures.

**Recommendation for future rounds:** sweep after every
package-integration trial batch; promote + ship + verify in a
single session whenever 2+ adopter evidence materialises for a
parked candidate. Skip the full road-test for mechanically-narrow
slices; use it for structural rules and branch-sensitive inference
changes.

## What's parked, what's closed, what's live

### Parked — awaiting evidence, not effort

- **Seven 1-adopter linter candidates** (`Route.description`,
  `addMiddleware`, `queryParameters.require` sibling-pair,
  `withSpan`, Bcrypt, `AppMetrics.push`, Axiom `emit`). None have
  surfaced on a second adopter across 11 post-candidate-filing
  rounds. Honest read: several of these are probably adopter-specific,
  not universal.
- **Slot 5 (perf fix)** — no adopter has stressed the wall-clock
  budget. Every scanned corpus has completed in seconds.
- **Slot 3 (property-wrapper receiver resolution)** — no adopter
  has surfaced a same-name method collision with differing tiers.
- **Prometheus counter-family whitelist** — 1-adopter (Uitsmijter),
  structurally distinct from SPI-Server's `AppMetrics.push`.
- **Deferred macro work** — `#assertIdempotentEffects` freestanding
  macro (free function is clearer); hybrid `assertIdempotent(returning:,
  effects:)` (adopters can compose two calls); parameterised
  `@IdempotencyTests` expansion (no concrete factory pattern to
  copy from). None of these have adopter pull.

### Closed this session

- Penny cross-bug-shape coverage (bug-sweep trial validates all
  four Penny shapes).
- Slot 21 (Vapor `app.register(collection:)`) — PR #27, verified
  end-to-end.
- Slot 22 (Swift Concurrency `Task.sleep`) — PR #28, verified
  end-to-end.

### Live — no queue items

The macro package + the linter are both in a post-criteria-met,
post-pattern-stabilised state. There is no named next-slice; no
open adopter friction; no pending API question. The next session
will start from a clean slate.

## Recommended opener for the next session

If a new adopter probe is warranted: select by domain/shape
novelty, not obscurity. Unexplored candidates: Apple Wallet pass
issuance (`vapor-community/wallet`), Parse CloudCode triggers
(`netreconlab/parse-server-swift`), GraphQL mutation resolvers.

If triage PRs are warranted: 8 parked real-bug findings (Penny×4,
isowords×2, myfavquotes-api×1, luka-vapor×1) remain unfiled. Two
filed this session window: HelloVapor #1 + prospero #8.

If winding down is warranted: this retrospective is the natural
close-out document; no urgent next-step exists.

## Key documents (for future reference)

- `docs/idempotency-macros-analysis.md` — primary design proposal.
- `docs/next_steps.md` — session-level handoff note (latest state).
- `docs/penny-package-trial/trial-retrospective.md` — Option B API
  R1/R2/R3 design rationale.
- `docs/release-notes/v0.{1,2,3,3.1}.0.md` — per-release notes.
- `docs/trial-adopter-lint-sweep-2026-04-24.md` — sweep methodology
  and slot-21/22 promotion evidence.
- `docs/uitsmijter-package-trial/slot-21-22-verification/verification-findings.md`
  — end-to-end verification of the session's two shipped slices.

## Closing note

The original analysis document proposed doc-comment annotations as
the interoperability surface between humans, the linter, and
macros — three consumers reading the same token. After 10 adopter
trials and 22 shipped slices, the framing holds: Uitsmijter's
`/// @lint.context` annotations work identically to Penny's,
despite the adopters having nothing else in common. The
three-consumer invariant is the load-bearing design choice; the
rest is the slow work of cataloguing shapes.
