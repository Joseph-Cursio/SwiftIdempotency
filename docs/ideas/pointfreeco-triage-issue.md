# Deferred idea: open a narrowly-scoped pointfreeco triage issue for finding #1

**Status.** Deferred — gated on user approval. The underlying research
is complete; the remaining move is a publicly-visible communication
action, and the user has not yet decided whether pursuing upstream
adopter bugs is in scope for this project.

## Origin

Slot 7 of the round-5 follow-up closed the runtime-path verification
question for pointfreeco's Stripe webhook handlers. See
[`../pointfreeco/slot7-runtime-verification.md`](../pointfreeco/slot7-runtime-verification.md)
for the full verification and per-site verdicts.

Headline: **the linter is catching real bugs.** None of the three
defang hypotheses (Stripe event-ID dedup, `gift.delivered` guard in
`handlePaymentIntent`, DB-level constraints on the UPDATE path) hold
for the email-send patterns. The two `update*` DB diagnostics are
defanged at the DB layer (overwrite-idempotent UPDATEs), which is
adopter-side annotation, not a business-logic concern.

Per the slot-7 recommendation in §6 of that doc, the cleanest upstream
action is a **single narrowly-scoped issue** for finding #1 only —
`sendGiftEmail` in `handlePaymentIntent` lacking a `!gift.delivered`
gate. One specific pattern, one-line fix, no speculation.

## Why it's not filed

- **User approval required.** Filing a public GitHub issue on a
  third-party repo is a publicly-visible action affecting a shared
  system (pointfreeco's issue tracker). Per the harness's "actions
  visible to others" convention, a session cannot file this without
  explicit authorization.
- **Scope uncertainty.** This project's goal has been the linter +
  macros design and validation. Whether adopter-engagement (filing
  upstream bugs surfaced by the linter) is an in-scope activity is a
  deliberate user decision, not a default. The research artifact
  stands regardless; the filing is separable.
- **One-shot, non-reversible.** A filed issue cannot be cleanly
  un-filed; editing or deleting leaves a trace. The cost of pausing
  to confirm is low.

## Shape of the issue if filed

Pinned to the exact commit analysed during slot 7
(pointfreeco @ `06ebaa5`). The filed issue should stay narrow:

- **One finding only.** `sendGiftEmail` in `handlePaymentIntent`,
  `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift`
  (see §2 of the slot-7 doc for the exact file/line reference).
- **One-line fix sketch.** Guard the email-send on
  `!gift.delivered`. Set `gift.delivered = true` either before the
  send (at-most-once) or after (at-least-once with dedup). The
  issue should name both options and defer the choice to the
  maintainer — it's an operational call about email-send policy.
- **Don't bundle findings #2–#4.** Findings #2 and #3 are correct
  flags but require judgment about intended Stripe-retry email
  policy (admin alerts, past-due reminders) — that's pointfreeco's
  call to make, and bundling dilutes the signal of #1. Finding #4
  is error-path admin-email noise.
- **Don't advocate for linter adoption in the issue.** The linter
  is the tool that found the bug; it isn't the subject. A brief
  "surfaced by an idempotency-linter prototype" line is the most
  that belongs in the issue body.
- **Honest failure mode.** If maintainers reply that Stripe
  duplicate-delivery is rare enough to ignore, that's a legitimate
  answer and still validates the linter's position ("this would
  be a bug if Stripe ever double-delivers, and the fix is cheap").

## Trigger for promotion

Promote this idea to an action when one of:

1. The user explicitly approves filing the issue.
2. A decision is made that adopter-engagement (upstream triage of
   linter-surfaced bugs on open-source projects) is a named workstream
   of this project. In that case this would become the first exemplar,
   and the shape sketched above becomes the template for future
   adopter-engagement filings.
3. An independent, unrelated pointfreeco bug report in the same area
   gets filed (by anyone) and the maintainer's reply signals
   receptiveness to a second narrow report. In that case the bar for
   filing drops — the community-norms question has already been
   answered.

## Why it's parked, not discarded

The finding itself is load-bearing for the project's story: **a
real-world bug found by the linter, verified against runtime behaviour,
with a one-line fix.** That narrative is a durable asset whether or
not the issue is ever filed. Parking the filing while keeping the
research artifact is the right separation.

## Related

- [`../pointfreeco/slot7-runtime-verification.md`](../pointfreeco/slot7-runtime-verification.md)
  — the full runtime-path verification. §6 is the recommendation this
  idea operationalises; §7 captures what the verification does *not*
  cover.
- [`../pointfreeco/trial-findings.md`](../pointfreeco/trial-findings.md)
  — the original round-5 trial results that surfaced the four
  findings.
