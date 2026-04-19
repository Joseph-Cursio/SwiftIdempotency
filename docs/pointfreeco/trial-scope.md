# pointfreeco — Trial Scope

Second adopter road-test (after `hummingbird-examples/todos-fluent`).
First round against a Vapor-ecosystem adopter and first round with
a genuinely **retry-exposed** adopter shape: Stripe webhooks are
documented to retry on their own schedule, so the `replayable`
annotation on the webhook entry points is factual, not hypothetical.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On a real Vapor-ecosystem adopter whose webhook handlers are
> genuinely Stripe-retried, what does the heuristic suite catch in
> replayable mode — and does the strict-mode residual surface
> adopter-specific patterns (custom DSLs, fire-and-forget wrappers,
> dependency-injected DB surfaces) that earlier adopter rounds
> didn't?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `040f186`
  (post-PR #14 tip — includes Fluent + Hummingbird framework gates).
- **Target:** `pointfreeco/pointfreeco` at SHA `06ebaa5` on `main`.
  Local clone `/Users/joecursio/xcode_projects/pointfreeco`. 918 Swift
  files / ~74k lines across 30+ modules; annotation targets are
  confined to `Sources/PointFree/Webhooks/`.
- **Trial branch:** `trial-vapor-pointfreeco` forked from `main`.
  Local-only, not pushed.
- **Build state:** linter does not require a buildable target;
  scan runs directly against source via SwiftSyntax. pointfreeco's
  build graph is not exercised.

## Annotation plan

Four handlers in two files, all `/// @lint.context replayable`
(then promoted to `strict_replayable` for Run B):

1. `stripePaymentIntentsWebhookMiddleware` — entry middleware for
   Stripe payment-intent events. Dispatches by `event.type`; most
   branches return an acknowledgement; `paymentIntentSucceeded`
   delegates to `fetchGift`.
2. `handlePaymentIntent` (private) — core business logic for a
   successful payment intent; calls `sendGiftEmail` when the gift
   is to be delivered immediately, plus `database.updateGiftStatus`.
3. `stripeSubscriptionsWebhookMiddleware` — entry middleware for
   Stripe subscription events. Validates signature, extracts
   subscription ID, delegates.
4. `handleFailedPayment` (private) — subscription failure handler;
   calls `database.updateStripeSubscription`, conditionally fires
   `removeBetaAccess` + `sendPastDueEmail` + `sendEmail` wrapped
   in `fireAndForget { ... }` closures.

## Scope commitment

- **Measurement only.** No linter changes this round. The linter
  doesn't need pointfreeco to build; we're reading source via
  SwiftSyntax exclusively.
- **Annotation-only source edits.** Four doc-comment lines added,
  one `sed` flip between Run A and Run B.
- **Throwaway branch, not pushed.** Matches prior-round policy.
- **Single sub-directory.** Only `Sources/PointFree/Webhooks/`
  carries annotations; the rest of pointfreeco's 918 files are
  un-annotated and produce zero diagnostics under both scans
  (the idempotency rules only fire inside an annotated context).

## Pre-committed questions for the retrospective

1. Does the `send*` prefix heuristic fire correctly on pointfreeco's
   Stripe webhook handlers? (Different codebase, different style,
   same heuristic pattern that pointfreeco was originally the
   motivating corpus for.)
2. What does pointfreeco's use of `fireAndForget { ... }` escape
   wrappers look like under the current inference? Are the inner
   calls correctly flagged despite the wrapper?
3. Does body-based upward inference reach non-idempotent conclusions
   through the private-helper chain (middleware → handler → email
   wrapper)?
4. What does the strict-mode residual look like relative to previous
   adopter rounds — are the adoption gaps Vapor-specific, adopter-
   specific (pointfreeco's custom HttpPipeline DSL), or generic
   patterns we'd expect across Swift web apps?
