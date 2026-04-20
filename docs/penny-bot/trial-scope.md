# penny-bot — Trial Scope

Sixth adopter road-test. **First production-app target** — every
prior round was either a toy (`todos-fluent`), an inverted-layer
framework (`swift-nio`), a framework test surface (`swift-composable-
architecture`), an example corpus (`swift-aws-lambda-runtime`), or
a production app with custom plumbing (`pointfreeco`, `HttpPipeline`).
Penny is a real Swift Server Work Group Discord bot running on AWS
Lambda + SotoDynamoDB + DiscordBM + GitHub OpenAPI — the "corpus
caveat" in `../../CLAUDE.md`'s Lambda round flagged this specific
target shape (production Lambda with real business side effects) as
the next step for FP-rate evidence.

Directly extends the round-9 (`swift-aws-lambda-runtime`) evidence
base: same AWS Lambda runtime, same `APIGatewayV2Request` /
`APIGatewayV2Response` shape, same `LambdaRuntime { … }.run()` idiom.
The framework baseline is warm from slot-10 — no whitelist work
expected to ship in this round.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On a production Swift-on-Lambda adopter with real business side
> effects (DynamoDB writes, Discord HTTP, S3 config I/O, GitHub
> webhook fan-out), does the linter's `replayable` diagnostic set
> sort cleanly into correct-catch / defensible / noise — i.e., does
> the FP-rate evidence from demo corpora (round 9's Lambda-runtime
> examples: 16/6 strict residual, all resolved) hold when the
> handler bodies are genuinely side-effectful rather than
> `log + echo + one SDK read`?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at
  `bc3c05e` (post-PR #20 tip — `Type.init(...)` member-access
  normalisation). `swift test` green: 2270/275 suites.
- **Upstream target:** `vapor/penny-bot` @ `main` at
  `ac9391916b7d96537709b72269d5757e49163ab5` (2026-04-18;
  `main` was pushed 2026-04-20 with unrelated deploy-CI commits —
  pinning to the 04-18 SHA anchors the code shape).
- **Fork:** `Joseph-Cursio/penny-bot-idempotency-trial` — not yet
  created. Pre-flight step; see "Pre-flight" below.
- **Trial branch:** `trial-penny-bot`, forked from fork-main at
  `ac93919`. Fork-authoritative — scans run against a fresh clone
  of the fork, not an ambient checkout.
- **Build state:** not built. SwiftSyntax-only scan, no SPM
  resolution required. Penny declares `swift-tools-version:6.3`
  (cutting-edge) — irrelevant to the scan, relevant to any future
  macro-form exercise.
- **Package shape:** single root `Package.swift`. The 8 Lambda
  targets live as siblings under `Lambdas/` with a shared
  `LambdasShared` target — not nested SPM packages, so the
  road-test plan's "multi-package corpora" recipe does **not**
  apply here. A single top-level scan covers the whole corpus.

## Annotation plan

Five handlers across five Lambda targets, chosen for shape
diversity across the real-business-side-effects axis this round
exists to measure. All five run under AWS Lambda's at-least-once
invocation contract, so `@lint.context replayable` is objectively
correct on each:

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Lambdas/GHHooks/GHHooksHandler.swift` | `handle(_:)` | **GitHub webhook fan-out.** Decodes APIGateway webhook → verifies signature → decodes `GHEvent` → delegates to `EventHandler.handle()` (Discord message posts, DynamoDB message-lookup writes via `DynamoMessageRepo`). Error path posts to Discord `botLogs` channel — itself a replayable-context side effect. Canonical "replayable fan-out" shape. |
| 2 | `Lambdas/Users/UsersHandler.swift` | `handle(_:)` | **DynamoDB CRUD dispatcher.** Switches on a 5-case `UserRequest` (addCoin / getOrCreateUser / getUser / linkGitHubID / unlinkGitHubID) → delegates to sub-handlers that call `InternalUsersService` (DynamoDB writes). Mix of idempotent reads and non-idempotent writes in one entry point — branch-join stress. |
| 3 | `Lambdas/Sponsors/SponsorsLambda.swift` | `handle(_:)` | **GitHub sponsor webhook → workflow trigger.** Receives sponsor events, calls `getWorkflowToken()` + `requestReadmeWorkflowTrigger()` (triggers a GitHub Actions workflow — externally visible non-idempotent side effect). Classic "webhook-to-action" shape. |
| 4 | `Lambdas/Faqs/FaqsHandler.swift` | `handle(_:)` | **S3 config CRUD.** Manages FAQ entries via `S3FaqsRepository`. Config-write shape: add/update/delete operations on a JSON-in-S3 store. Distinct from DynamoDB CRUD (no per-item conditional writes). |
| 5 | `Lambdas/GHOAuth/OAuthLambda.swift` | `handle(_:)` | **OAuth callback.** Exchanges GitHub OAuth `code` for access token (`getGHAccessToken`) → fetches user (`getGHUser`) → links Discord↔GitHub account. The `code` is a natural `IdempotencyKey` candidate — first real-adopter exposure of the `by:` parameter shape in production context. |

Shape coverage:

- **Webhook / replayable-by-construction entry:** #1, #3, #5.
- **DB write (DynamoDB):** #2.
- **DB write (S3 JSON config):** #4.
- **Pure read dispatched from branch:** #2's `getUser` sub-handler.
- **Natural `IdempotencyKey` candidate:** #5 (OAuth code), #1 (`x-github-delivery` header), #3 (GitHub webhook delivery ID) — if #5 goes smoothly, #1 and #3 are stretch candidates.
- **Workflow-trigger external side effect:** #3.

Deliberately excluded from the primary five:

- **`Lambdas/AutoPings/AutoPingsHandler.swift`** and
  **`Lambdas/AutoFaqs/AutoFaqsHandler.swift`** — shape-duplicate with
  `Faqs` (S3-JSON config CRUD, different schemas). Include as a
  stretch if time permits a coverage-completeness check.
- **`Sources/Penny/**`** — the long-running Discord bot service
  itself. Different runtime shape (single-process `ServiceGroup`
  rather than Lambda per-event). Out of scope for a Lambda-focused
  round. May surface shape-collision data (pre-committed question 4).
- **`Lambdas/GitHubAPI/`** — OpenAPI-generated client, no
  `@main`/`handle` shape to annotate.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each of the five handlers.
  No logic edits, no imports, no new types. `IdempotencyKey`
  experimentation (pre-committed Q3) uses the macro's
  attribute-form equivalents and stays non-invasive — if that
  requires a package dependency on `SwiftIdempotency`, the
  adoption experiment moves to a separate follow-up round rather
  than contaminating this measurement.
- **Audit cap.** 30 diagnostics max per mode (template default).
  If strict-replayable exceeds 30, decompose the excess into
  named clusters without per-diagnostic verdicts.

## Pre-committed questions

1. **FP-rate on production business logic.** On a codebase with
   real business side effects (Dynamo/S3 writes, Discord HTTP,
   GitHub API calls), does the diagnostic set sort cleanly into
   correct-catch / defensible / noise, or does production code
   expose a new category of false positive the demo corpora
   didn't reach? Answer drives the "battle-tested to obscure"
   transition in `project_validation_phase2.md`.

2. **Slot-10 regression check.** The Lambda response-writer
   whitelist (`outputWriter.write`, `responseWriter.write`,
   `responseWriter.finish`) shipped against awslabs' demo corpus.
   Does it hold on Penny's production code, or does Penny expose
   a whitelist gap in `idempotentReceiverMethodsByFramework`
   gated on `AWSLambdaRuntime` / `DiscordBM` / `Soto*` imports?
   Any gap gets scored as a fresh framework-whitelist slice.

3. **`IdempotencyKey` natural-adoption signal.** Handlers #1, #3,
   and #5 each have a natural `IdempotencyKey` candidate (webhook
   delivery IDs, OAuth code). Is the `@ExternallyIdempotent(by:)`
   shape a natural fit for the adopter's existing type structure,
   or does the macro require restructuring the request-decoding
   path? First real-adopter stress of the public `IdempotencyKey`
   type.

4. **Cross-target shape collisions.** Penny has `Sources/Penny/`
   alongside the Lambdas. Do the method-name collisions that
   slot 3 (property-wrapper receiver-type resolver) was designed
   for actually surface here — e.g., `UsersHandler.handle(_:)`
   vs. a service-side `SomeOtherThing.handle(_:)` that happens
   to share a signature? The slot-3 trigger criterion is "first
   annotated-corpus round where two different types each declare
   a signature with the same `name(labels:)` and different tiers"
   (see `../next_steps.md §3`). Monitor for it; if seen, reopen
   slot 3.

## Pre-flight

Remaining steps before annotation begins:

1. Create fork `Joseph-Cursio/penny-bot-idempotency-trial` from
   `vapor/penny-bot`; harden per road-test recipe
   (`--enable-issues=false --enable-wiki=false
   --enable-projects=false`); set description to
   "Validation sandbox for SwiftIdempotency road-tests. Not a
   contribution fork."
2. Create branch `trial-penny-bot` on the fork at `ac93919`.
3. Prepend README banner flagging the fork as non-contribution;
   switch default branch to `trial-penny-bot`.
4. Fresh-clone the fork into
   `/Users/joecursio/xcode_projects/penny-bot-trial` for the
   annotation + scan work. The upstream shallow clone at
   `/tmp/penny-survey/penny-bot` used for this scope doc is a
   survey artifact only — discard after scope is frozen.

The fork creation is the single publicly-visible action in this
round. Gated on user approval of this scope doc.
