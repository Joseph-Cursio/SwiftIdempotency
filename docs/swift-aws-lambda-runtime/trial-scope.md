# swift-aws-lambda-runtime — Trial Scope

Fifth adopter road-test. First event-driven-framework target;
first from the AWS ecosystem; first exercise of the
fork-authoritative workflow from a cold start (the workflow was
rewritten mid-stream during the TCA round and walked through
retroactively there).

Per `../../CLAUDE.md`'s validation recommendation the originally
chosen target was `apple/swift-aws-lambda-runtime` for its
SQS/SNS handlers: "every SQS/SNS handler is objectively
`@lint.context replayable`, so annotation correctness is
unambiguous." That target path drifted in the interim — the
authoritative repo is now `awslabs/swift-aws-lambda-runtime`
(migrated apple → swift-server → awslabs) — and the v2.x example
corpus has **no SQS/SNS examples**. The S3 event notification
path provides the same "objectively replayable" guarantee via a
different AWS primitive (S3 Event Notifications are at-least-once
delivery by construction), so it substitutes for the SQS/SNS
positive control in this round. The CLAUDE.md drift is folded
into the retrospective's policy-notes section.

See [`../road_test_plan.md`](../road_test_plan.md) for the
template.

## Research question

> "On an AWS Lambda event-driven adopter, do the
> `LambdaRuntime { (event, context) in … }` trailing-closure and
> protocol-method (`LambdaHandler.handle`,
> `StreamingLambdaHandler.handle`,
> `LambdaWithBackgroundProcessingHandler.handle`) handler shapes
> fire correctly under `@lint.context replayable`, and — **the
> cross-framework question** — does the `@lint.framework`
> whitelist infrastructure shipped in PR #18 generalise cleanly
> beyond its originating framework without shape changes?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at
  `5698683` (post-PR #18 merge tip — TCA send-closure-parameter
  framework whitelist). PR #19 (closure-typed stored properties
  as effect declarations) remains open; it is TCA-`@DependencyClient`
  specific and not exercised by any of the Lambda handlers
  selected below, so leaving it out of the baseline does not
  bias this round.
- **Upstream target:** `awslabs/swift-aws-lambda-runtime` @
  `f3bd0ae` on `main` (v2.8.0-era tip, Apr 2026).
- **Fork:** `Joseph-Cursio/swift-aws-lambda-runtime-idempotency-trial`
  forked from upstream, hardened per road-test recipe.
- **Trial branch:** `trial-lambda`, forked from fork-main at
  `f3bd0ae`. Fork-authoritative — scans run against a fresh clone
  of the fork, not the ambient checkout.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required on the adopter.

## Annotation plan

Six handlers across six example packages, chosen for shape
diversity. All six are objectively in a replayable retry context
(Lambda's runtime retries a failed async invocation; S3 event
notifications are at-least-once; event-driven AWS contexts are
canonically redelivery-exposed) so annotation correctness is
unambiguous:

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Examples/S3EventNotifier/Sources/main.swift:20` | `LambdaRuntime { (event: S3Event, context) in … }` | Trailing-closure, async throws. S3 event — at-least-once by construction. Body has no external side effects; positive-control for the silent-handler signal. |
| 2 | `Examples/BackgroundTasks/Sources/main.swift:36` | `BackgroundProcessingHandler.handle(_:outputWriter:context:)` | Protocol method (`LambdaWithBackgroundProcessingHandler`). Calls `outputWriter.write(...)` **before** `Task.sleep` — the canonical response-then-work shape. **Slot 4 cross-adopter candidate:** if any part of this surfaces the same escape-wrapper pattern `fireAndForget` does on pointfreeco, slot 4 lights up with a second data point. |
| 3 | `Examples/S3_Soto/Sources/main.swift:23` | `handler(event: APIGatewayV2Request, context:)` | Top-level `func`. Calls external AWS service (`s3.listBuckets()`). Idempotent read — should stay silent. |
| 4 | `Examples/MultiSourceAPI/Sources/main.swift:27` | `MultiSourceHandler.handle(_:responseWriter:context:)` | Streaming protocol method. Two conditional decode branches both terminate in `responseWriter.write` + `responseWriter.finish`. Branch-join inference stress test. |
| 5 | `Examples/APIGatewayV2/Sources/main.swift:19` | `LambdaRuntime { (event: APIGatewayV2Request, context) -> APIGatewayV2Response in … }` | Trailing-closure, sync non-throwing (minimal shape). Smoke test. |
| 6 | `Examples/Testing/Sources/main.swift:27` | `MyHandler.handler(event:context:)` | Struct method (not protocol). Base64 decode + business-code `uppercasedFirst()`. Two-branch return. |

Shape coverage:

- **Trailing closure:** #1, #5.
- **Top-level `func`:** #3.
- **Struct method:** #6.
- **Protocol method:** #2 (`LambdaWithBackgroundProcessingHandler`), #4 (`StreamingLambdaHandler`).
- **Branch-heavy:** #4, #6.
- **Crosses-the-boundary (calls external service):** #3 (AWS S3 via Soto), plus #1 which should do so but currently doesn't (`// Here you could, for example, notify an API…` is an instructive comment: the annotation declares a replayable context that the adopter is aware of, but the body hasn't been written yet).

Deliberately excluded to keep scope tight:

- `HummingbirdLambda/Sources/main.swift:23` — already-whitelisted
  framework (`router.get { … }` is covered by commit `040f186`).
  Adds Hummingbird re-validation, not new evidence. Include as
  a stretch if time permits the secondary confirmation signal.
- `ServiceLifecycle+Postgres/Sources/Lambda.swift:107`
  (`prepareDatabase`) — manually dedup-guarded (swallows
  duplicate-key `PSQLError`). Genuinely interesting but sits in
  a prelude service, not a Lambda invocation — outside the
  strict "handler" shape this round is measuring.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each handler. No logic
  edits, no imports, no new types.
- **Audit cap.** 30 diagnostics max per mode (template default).
  If strict-replayable exceeds 30, decompose the excess into
  named clusters without per-diagnostic verdicts.

## Pre-committed questions

1. **Cross-framework validation of PR #18.** Does the
   `@lint.framework` whitelist infrastructure generalise without
   shape changes to a second framework (AWS Lambda Runtime +
   Soto AWS SDK)? If yes, the infrastructure is load-bearing
   and can be extended to future frameworks via config only. If
   no, name the specific gap and score a follow-up slice.

2. **Slot 4 second data point.** Does handler #2 (`BackgroundTasks`,
   response-then-background-work shape) surface the same
   escape-wrapper pattern that `fireAndForget` did on pointfreeco?
   Two independent data points would unblock slot 4 of
   `../next_steps.md`. One-only keeps it on hold. Zero means
   the shape is pointfreeco-specific and slot 4 downgrades.

3. **Protocol-method handler shape coverage.** The prior four
   rounds were dominated by closure handlers. Do protocol-method
   handlers (`LambdaHandler.handle`,
   `StreamingLambdaHandler.handle`, etc.) fire correctly under
   `@lint.context replayable` placed on the method, or is the
   annotation-placement heuristic closure-biased in a way that
   only surfaces on this round's shape?

4. **Fork-authoritative workflow rough edges.** The protocol was
   rewritten mid-TCA round and has only been walked through
   retroactively. Running fresh end-to-end — harden the fork,
   branch, push annotations, re-clone for scans — should expose
   any steps where the template assumes prior state or misses a
   sequencing dependency. Any findings fold back into
   `../road_test_plan.md`.
