# pointfreeco — Slot 7 runtime-path verification

Follow-up to the round-5 trial. The research question:

> Run A flagged 6 diagnostics in pointfreeco's Stripe webhook handlers —
> are they real bugs under Stripe's retry semantics, or does production
> runtime (event-ID dedup, status guards, DB-level constraints) defang
> them before the duplicate side effect reaches the user?

Short answer: **the linter is catching real bugs.** None of the three
defang hypotheses from `next_steps.md §7` hold for the email-send
patterns. The two `update*` DB diagnostics are flagged-but-defanged at
the DB layer (overwrite-idempotent UPDATEs). Production exposure is
small because Stripe's duplicate-event-delivery is itself rare, but
where it happens, duplicate emails are sent.

Pinned context: pointfreeco @ SHA `06ebaa5` (same tip as the round-5
trial). Source at `/Users/joecursio/xcode_projects/pointfreeco`.

## 1. Hypothesis: Stripe event-ID deduplication at entry

**Not present.** `stripePaymentIntentsWebhookMiddleware` and
`stripeSubscriptionsWebhookMiddleware` both dispatch on `event.type`
without ever touching `event.id`. There is no table in the schema that
stores processed Stripe event IDs:

```
$ rg -n 'event_id|processed_events|stripe_event|webhook_events|seen.*event' pointfreeco
# only hits: livestreams.event_id column (unrelated), Stripe SDK test fixture
```

The `Event<T>` type (`Sources/Stripe/Model.swift:288`) carries `id:
StripeID<Self>`, so the ID is available on the deserialised payload —
it simply isn't consulted. Validation is signature-only
(`validateStripeSignature` in `StripeValidation.swift`).

Consequence: whenever Stripe delivers the same `event.id` twice (their
documented at-least-once guarantee), the handler re-enters from the
top. This is the central failure mode the linter is warning about.

## 2. Hypothesis: `gift.delivered` guard in the payment-intent handler

**Not present.** The `Gift` model (`Sources/Models/Gift.swift:9`)
carries `delivered: Bool`, and `updateGiftStatus`
(`Sources/Database/Live.swift:1074-1078`) flips that column:

```sql
UPDATE "gifts"
SET "stripe_payment_intent_status" = $1, "delivered" = $2
WHERE "id" = $id
```

But `handlePaymentIntent` never reads `gift.delivered` back:

```swift
// PaymentIntentsWebhook.swift:55-59
let deliverNow = gift.deliverAt == nil
if deliverNow {
  _ = try await sendGiftEmail(for: gift)
}
_ = try await database.updateGiftStatus(gift.id, paymentIntent.status, deliverNow)
```

The gate is `gift.deliverAt == nil` — a *configuration* field set at
gift-purchase time ("should this deliver immediately?"), not a
mutation flag. `updateGiftStatus` does not touch `deliverAt`, so the
gate's evaluation is stable across retries. On duplicate event
delivery, `sendGiftEmail` re-fires.

`sendGiftEmail` itself (`Sources/PointFree/Gifts/GiftEmail.swift:16`)
has no internal dedup — it's a straight `sendEmail` call with
error-notify. The `delivered` flag is written but never checked.

**Fix shape if pointfreeco wanted to adopt one:** replace
`let deliverNow = gift.deliverAt == nil` with
`let deliverNow = gift.deliverAt == nil && !gift.delivered`. Single
line, preserves the existing semantics, closes the duplicate-email
hole on Stripe's occasional double-delivery.

## 3. Hypothesis: DB-level constraints / overwrite semantics

**Holds for the two `update*` DB diagnostics — they are defanged at the
DB layer, not by business logic.**

- `updateGiftStatus`: plain UPDATE with deterministic new values
  (`stripe_payment_intent_status`, `delivered`). Re-running with the
  same inputs overwrites to the same row state. Idempotent.
- `updateStripeSubscription` (`Sources/Database/Live.swift:1084-1093`):
  UPDATE setting `stripe_subscription_status` from the stripeSubscription
  argument. Same overwrite-idempotent shape.

Neither is a unique-constraint / INSERT-with-ON-CONFLICT path, so the
idempotency comes from "the UPDATE statement is a set operation" rather
than any explicit DB-level dedup.

The linter diagnostic is semantically correct — it can't know the UPDATE
is overwrite-safe without an `@Idempotent` / `@lint.effect idempotent`
annotation on the `Database` decl. Closes cleanly as an adopter-side
annotation; flagged in round-5 findings §2 (`update*` prefix-match
landed as PR #15 on the linter) for the detection side.

## 4. Per-site verdict

Of the six round-5 replayable-mode catches, the 4 "email-send" patterns
are the ones slot 7 calls out. Verdicts:

| # | Site | Callee | Runtime mitigation? | Real bug? |
|---|------|--------|---------------------|-----------|
| 1 | `handlePaymentIntent:57` | `sendGiftEmail` | None — `delivered` is set but never read; `deliverAt` gate is stable across retries | **Yes.** Duplicate gift email on duplicate event delivery. User-visible. |
| 2 | `handleFailedPayment:70` | `sendPastDueEmail` | None — fires on every entry where `status == .pastDue` | **Partially.** Stripe's *scheduled* payment-retries are distinct `event.id`s and arguably *should* each produce a past-due email. The linter flag applies only to same-`event.id` re-delivery. |
| 3 | `handleFailedPayment:75` | Admin `sendEmail` (churn warning) | None — fires on every entry where `.pastDue + quantity >= 3` | **Partially.** Same reasoning as #2; the admin alert on each real retry is intentional, duplicate alerts on duplicate delivery are not. |
| 4 | `handleFailedPayment:94` | Admin `sendEmail` (catch branch) | None — fires on any thrown error | **Yes, but low-impact.** Duplicate admin error alerts on transient failures are noise, not user-facing bugs. |

Plus the two DB diagnostics already covered in §3 —
`updateGiftStatus` and `updateStripeSubscription` — are real flags
defanged at the DB layer (overwrite UPDATEs).

## 5. Exposure in production

Upper-bounded by how often Stripe delivers the same `event.id` twice,
and how often first-invocation 200-responses fail to reach Stripe.
Stripe's own docs acknowledge "occasional" duplicate delivery; the
industry-observed rate is low but non-zero. None of the four patterns
are in a hot path that would amplify the rate.

So: real bugs, low production firing rate, user-visible on #1,
low-impact on #2–#4. This is the shape the linter is designed to
catch — the pattern is present, the guard is missing, the runtime
doesn't coincidentally defang it, and adding the guard is a single
line of code.

## 6. Recommendation

**Open a triage issue on `pointfreeco/pointfreeco` focused narrowly on
finding #1** (`sendGiftEmail` missing `!gift.delivered` gate). One
specific, reproducible pattern with a one-line fix, no speculation
about the rest. Don't bundle the other three into the same issue —
findings #2 and #3 require judgment about intended Stripe-retry email
policy, which is pointfreeco's call to make. Finding #4 is error-path
noise. Bundling dilutes the signal of #1.

If pointfreeco's maintainers push back that Stripe duplicate delivery
is rare enough to ignore, that's the honest answer and it still
validates the linter's position: "this would be a bug if Stripe ever
double-delivers, and the fix is cheap." The linter's job is to surface
that choice to the maintainer, not to make it for them.

If pointfreeco's maintainers accept, a follow-on conversation about
event-ID dedup at the webhook entry would close the broader class
(findings #2–#4) — but that's an architectural change, not a
one-line fix, and not this issue's scope.

## 7. What this doesn't validate

- **False-positive rate.** Zero FPs on these four patterns, but the
  round-5 strict-mode residual (32 diagnostics) is majority
  adopter-local style. The "is the linter catching *only* real bugs"
  question needs a larger corpus; this slot only addresses "are the
  bugs it catches real."
- **Other ecosystems' retry-exposed handlers.** pointfreeco uses
  custom `HttpPipeline` + `swift-dependencies` + Mailgun. Results
  don't generalise to AWS Lambda SQS consumers, RabbitMQ workers,
  Kafka consumers, etc. Each needs its own runtime-path verification.
- **The `fireAndForget` escape-gate miss** documented in
  [`../ideas/fire-and-forget-escape-wrappers.md`](../ideas/fire-and-forget-escape-wrappers.md).
  That idea is a *linter-side* concern about escape-gate scope —
  orthogonal to this runtime verification. The fire-and-forget
  wrapper doesn't defang the duplicate-email risk (it just dispatches
  the email asynchronously); it also isn't silencing or amplifying
  the linter's detection on this codebase (every fire was a true
  positive anyway).
