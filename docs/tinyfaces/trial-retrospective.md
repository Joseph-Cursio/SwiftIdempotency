# TinyFaces — Trial Retrospective

Reflective notes after running the seventeenth adopter round.
See [`trial-scope.md`](trial-scope.md) and
[`trial-findings.md`](trial-findings.md) for the measurements.

## Did the scope hold?

Yes, in full.

- **Source-edit ceiling held.** Annotations only — 6 doc-comment
  insertions across 3 files. No imports, no logic edits.
- **Audit cap held.** 6 Run A diagnostics (under the 30 cap, full
  per-diagnostic verdicts). Run B exceeded 30 (61 strict-only
  fires) → decomposed by 6 named clusters per the template's
  "exceeds 30" recipe.
- **Data-layer audit completed.** Both Fluent migrations read
  (`CreateSubscription`, `CreateUser`); `User.createIfNotExist`
  helper body inspected; Stripe API semantics checked against
  Stripe-kit's documented behaviour.

One scope-adjacent observation: **the linter's pre-existing test
failures.** Two `exitWithErrorForInvalidCategory()` failures at
the pinned linter SHA (`0ca8a12`) were noted in scope as
unrelated to rule behaviour and confirmed unrelated to the scan
path. The matool round (round 16) used the same SHA and called
it "green" — that wording is loose. Worth re-verifying on future
rounds rather than carrying forward as ambient.

## Pre-committed questions

### Q1. Stripe customer-create on retry (`commercialCalculate`)

**Hypothesis: yes, fires.** **Actual: yes, fires** (Run A
diagnostic A5).

The `if customerId == nil { request.stripe.customers.create(email:) }`
shape fires on the `create` callee-name prefix as expected. Data-
layer audit confirms a real-bug consequence: under concurrent
LB-retry, the `User.unique(on: "stripe_customer_id")` constraint
prevents local-DB duplicate-row, but Stripe's side ends up with
**an orphaned customer record** that the merchant is responsible
for managing (and potentially billable for any sessions linked
to it). This is the canonical use case for Stripe's
`Idempotency-Key` header — and a direct demonstration of the
`SwiftIdempotency.IdempotencyKey` value proposition.

**Cross-adopter status:** matool's Cognito-`adminCreateUser` was
1-adopter for "external SaaS API call with user-visible side
effect on each invocation, no built-in dedup." TinyFaces'
Stripe-customer-create is a **structurally distinct** shape
(no user-visible side effect; orphan-resource is the issue,
not duplicate-action). They sit in the same family ("external
SaaS API on retry without idempotency-key") but are different
sub-shapes. Promotion to 2-adopter slice is **borderline** —
the abstraction "external SaaS API call without idempotency
key" covers both, but the consequence (email vs orphan) is
different.

### Q2. Webhook re-delivery (`StripeWebhookController.index`)

**Hypothesis: yes, fires; deep-chain walks into sub-handlers.**
**Actual: NO — `index` is silent (Run A diagnostic A1).**

The dispatcher routes via `switch (event.type, event.data?.object)`
to four sibling handlers (`checkoutCompleted`, `invoiceUpdate`,
`subscriptionUpdate`). Each sub-handler is itself non-idempotent
(by both the linter's verdict on `subscriptionUpdate` being
silently safe and the Run A catches on `checkoutCompleted` and
the Stripe-create calls). But the deep-chain inferrer does not
propagate the non-idempotent tier from sub-handler back up to
`index`.

**Adoption gap surfaced.** Named in
[`trial-findings.md`](trial-findings.md) §"Linter slice candidates"
as **switch-dispatch deep-chain inference**. Fix direction: teach
`EffectSymbolTable.runInferencePass` to walk `SwitchExprSyntax`
case bodies as direct callees of the enclosing function, not as
nested expressions.

This shape is likely common in webhook-receiving Vapor / Hummingbird
adopters. Worth a slice; trigger condition is "first 2nd-adopter
round that exhibits the same switch-dispatch shape on a webhook
entry" — likely any future Stripe / GitHub / Slack / Discord
webhook adopter will surface it.

### Q3. `createIfNotExist` recognition

**Hypothesis: linter fires on `checkoutCompleted` despite the
helper's idempotent intent.** **Actual: yes, fires** (Run A
diagnostic A4).

The diagnostic is correctly worded: the heuristic infers
`non_idempotent` from "callee-name prefix `create` (in
`createIfNotExist`)." So the linter recognises the prefix but
does not treat the suffix as a safety modifier.

**This is the right behaviour by design.** The helper is named
"createIfNotExist" but its body still contains `User(...)` +
`save(on:)` — and that body is non-idempotent under concurrent
retry (the `find` returns nil for both racers, both create, then
the unique constraint resolves the conflict at insert time).
The linter is correctly conservative: prefix-match catches the
shape, and the data-layer audit determines whether the unique
constraint at the DB layer makes it safe.

In TinyFaces' case, **`User` migration declares `.unique(on:
"stripe_customer_id")` but NOT `.unique(on: "email")`** — and
`createIfNotExist` queries by email. So the linter's catch is
correct: the helper's name suggests idempotency, but the body
isn't safe under concurrent same-email retry.

### Q4. Magic-link email-on-retry (`sendMagicEmail`)

**Hypothesis: yes, fires; verdict depends on dedup window.**
**Actual: yes, fires** (Run A diagnostics A7+A8). **Verdict:
real-bug catch** for LB-retry, defensible for user-initiated
re-send.

The retry context this rule targets is **load-balancer / reverse-
proxy retry on a flaky upstream response** — exactly the case
where two different `code` values get sent to the same email
address from a single user-initiated POST. The
`AuthenticationCode.tries` counter doesn't help here because the
two codes are stored against **two different session UUIDs**
(`UUID().uuidString` is generated fresh per call inside
`sendEmail`), so the user's session-cookie binds to whichever
session arrived second — and the first email's code becomes
unrecoverably stale.

This is the **2nd-adopter datapoint** for the email-on-retry
shape, after matool's Cognito `adminCreateUser`. The vendor
differs (Brevo via `SendInBlue` SDK vs AWS Cognito), the consequence
differs (transactional email vs invitation email), but the
underlying shape is identical: external email-sending API call
on every invocation, no idempotency guard at the call site.

**Cross-adopter slice promotion:** the email-on-retry shape moves
from 1-adopter speculative to 2-adopter slice candidate.

## Counterfactuals — what would have changed the outcome

1. **If `CreateSubscription` had declared `.unique(on: "stripe_id")`,**
   diagnostic A4 would flip from real-bug catch to defensible-by-
   data-layer-design (Fluent → Postgres `UNIQUE` constraint
   prevents the dup-row race). This is exactly the intervention
   `samalone/prospero#8` proposed for ActivityPattern. The pattern
   keeps recurring across Vapor/Fluent adopters: external-foreign-
   key columns shipped without `.unique(on:)`.

2. **If TinyFaces wrapped Stripe customer creation with an
   `Idempotency-Key` header,** diagnostic A5 would flip to
   defensible-by-design. Stripe's API natively supports this;
   `vapor-community/stripe-kit` exposes it via the request
   options. The fix is a 1-line change at the call site —
   exactly the diff a `SwiftIdempotency.IdempotencyKey`-aware
   helper macro could automate.

3. **If `index` had not used switch-dispatch and instead inlined
   the sub-handler bodies,** the Run A yield on `index` would
   match Run A's other handlers (would fire on `User(...)` /
   `Subscription()` / `save` / `create` chains). The silence
   on `index` is purely a linter inference shape, not an
   adopter-design issue.

## Cost summary

- **Estimated:** 1.5-2 hours per the road-test template (pre-flight
  + annotate + 2 scans + audit + 4 docs).
- **Actual:** ~1 hour for the scan + audit + docs path. Pre-flight
  added ~10 minutes for the linter fast-forward (local main was
  38 commits behind origin/main).

## Policy notes

1. **"Linter on a known-green tip" wording is loose.** The matool
   round called `0ca8a12` "green" while two CLI-input-validation
   tests fail. For this round it was confirmed not on the scan
   path (the failure is in unknown-category rejection;
   `--categories idempotency` bypasses the bug). But future rounds
   shouldn't carry this forward as ambient. Proposed
   `road_test_plan.md` clarification: pre-flight should explicitly
   confirm test failures are on a non-scan path, not just count
   them.

2. **Local linter checkout drift.** Local main was 38 commits
   behind origin/main (PRs #11-#29 had merged on origin without
   local being pulled). Worth a one-line pre-flight: `git fetch
   && git status` to confirm local is at-or-past the SHA pinned
   in scope.

3. **License-absent target filing posture.** TinyFaces has no
   LICENSE file and last upstream push was 2024-02. Proposed
   posture (folded into findings doc): file the highest-impact
   PR first (Stripe customer orphan), wait for maintainer
   response, file the other two only if the first lands.

4. **2-adopter slice promotion is judgement-dependent.** matool's
   Cognito-`adminCreateUser` and TinyFaces' Stripe-customer-create
   sit in the same shape family but have different consequences
   (email vs orphan). Both fall under "external SaaS API on
   retry without idempotency key", but at the slice level the
   abstraction is too generic to act on. The narrower
   "email-on-retry" shape (matool Cognito + TinyFaces Brevo) is
   the cleaner 2-adopter promotion.

## Data committed

- [`trial-scope.md`](trial-scope.md) — research question, pinned
  context, annotation plan, pre-committed questions.
- [`trial-findings.md`](trial-findings.md) — Run A per-diagnostic
  table, Run B 6-cluster decomposition, real-bug filing queue.
- [`trial-retrospective.md`](trial-retrospective.md) — this file.
- [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
  — Run A linter output.
- [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
  — Run B linter output.

Trial fork: `Joseph-Cursio/TinyFaces-idempotency-trial` @
`trial-tinyfaces` branch (current tip `6e51ae3`).
