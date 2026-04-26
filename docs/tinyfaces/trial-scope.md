# TinyFaces — Trial Scope

Seventeenth adopter road-test. **First Stripe-using adopter** —
exercises the canonical payment / billing-lifecycle shape. The
canonical idempotency shape Stripe ships with — the
`Idempotency-Key` header — is whose use-case the
`SwiftIdempotency.IdempotencyKey` type was named for, but no prior
round has tested an actual Stripe-using adopter.

This round also gives a 2nd-adopter datapoint for matool's Cognito-
on-retry shape (an external SaaS API call that has user-visible
side effects on each invocation).

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On a production Vapor + Fluent + StripeKit web app
> (free-stock-avatars-with-paid-licensing), do the canonical Stripe
> shapes — webhook re-delivery, customer-create-on-checkout,
> portal-session-create, find-or-create subscription — fire under
> `@lint.context replayable` placed on the controller method?
> Specifically: does the `if customerId == nil { stripe.customers.create }`
> pattern surface as a real-bug catch (parallel to matool's Cognito
> `adminCreateUser`)? Does the `find-or-create Subscription()`
> pattern in `checkoutCompleted` surface separately from the upsert
> patterns DynamoDB / Postgres `ON CONFLICT` audits flip to
> defensible?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `0ca8a12`
  (same SHA as matool / graphiti / grpc-swift-2 rounds; 2 pre-
  existing CLI input-validation test failures in
  `exitWithErrorForInvalidCategory` are unrelated to rule behavior
  — `--categories idempotency` is a valid category, so the
  validation path is not on the scan path).
- **Upstream target:** `maximedegreve/TinyFaces` @ `db3f2b6` on
  `master` (last upstream push 2024-02-08). Vapor 4 + Fluent
  (PostgreSQL) + StripeKit web app. **Real production app** —
  hosts the public TinyFaces stock-avatars service used by
  designers; Stripe surface is the paid commercial-license
  flow. 550 stars; single-contributor; 2 years stale.
- **Architecture:** Vapor 4 router → controllers (method-reference
  `use:` binding, so annotation target is the handler `func` decl
  per `road_test_plan.md` §"Handler-binding shape determines
  annotation target"). Controllers call:
  - `request.stripe.customers.create(...)` — creates a Stripe customer
  - `request.stripe.sessions.create(...)` — Stripe Checkout session
  - `request.stripe.portalSession.create(...)` — Stripe customer portal
  - `User.save(on: request.db)` — Fluent upsert by primary key (defensible)
  - `Subscription()` + `.save(on:)` — Fluent insert (potential dup-row race)
  - `SendInBlue().sendEmail(...)` — transactional email via Brevo
  - `request.cache.set(...)` — Vapor session cache (TTL-bounded)
- **Fork:** `Joseph-Cursio/TinyFaces-idempotency-trial`, hardened
  per road-test recipe.
- **Trial branch:** `trial-tinyfaces`, forked from upstream
  `db3f2b6`. Fork-authoritative.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required.
- **Repo layout:** single SPM package; scan target is repo root.
- **License:** none in repo. Read-only static scan is fine; PR-
  filing on any real-bug catch is gated on user contacting
  maintainer first.

## Annotation plan

Six handlers across three controllers, selected for shape diversity.

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Sources/App/Controllers/StripeWebhookController.swift:7` | `index(request:)` | **WEBHOOK ENTRY.** Stripe webhook re-delivery is canonical retry context. Dispatches via `switch (event.type, event.data?.object)` to four sub-handlers. Tests deep-chain inference. |
| 2 | `Sources/App/Controllers/StripeWebhookController.swift:46` | `subscriptionUpdate(request:subscription:)` | **DEFENSIBLE-BY-DESIGN CONTROL.** Lookup-by-stripeId → set fields → `.save()`. Expected: fires Run A, audit confirms safe (target row is fixed by `stripeId`; replay produces same final state). |
| 3 | `Sources/App/Controllers/StripeWebhookController.swift:62` | `portalRedirect(request:)` | **EXTERNAL API SIDE EFFECT.** Calls `request.stripe.portalSession.create(...)` — creates a fresh portal session on every invocation. **2nd-adopter test for matool's Cognito-shape generalisation** (external SaaS API call with per-invocation side effect). |
| 4 | `Sources/App/Controllers/StripeWebhookController.swift:120` | `checkoutCompleted(request:session:)` | **HIGH-VALUE CATCH CANDIDATE.** `User.createIfNotExist(...)` + `Subscription()` create-if-missing without unique-constraint check. Tests whether the explicit-idempotent helper (`createIfNotExist`) is recognised as safe, and whether the find-or-create-without-unique-constraint pattern surfaces as a real-bug race. |
| 5 | `Sources/App/Controllers/LicenseController.swift:55` | `commercialCalculate(request:)` | **TRIPLE-SIDE-EFFECT.** `if customerId == nil { request.stripe.customers.create(...) }` + `user.save` + `request.stripe.sessions.create(...)`. **Direct payment-flow idempotency surface** — the canonical "Stripe customer creation on retry" bug shape. The richest single handler in this round. |
| 6 | `Sources/App/Controllers/AuthenticationController.swift:16` | `sendMagicEmail(request:)` | **MAGIC-LINK AUTH WITH EMAIL.** Lookup or create user + cache-store auth-code + send email via Brevo (`SendInBlue`). Novel auth shape — distinct from Cognito (matool) and OIDC (Uitsmijter). |

Deliberately excluded:

- `StripeWebhookController.invoiceUpdate` — structurally identical
  to `subscriptionUpdate`; would not differentiate verdicts.
- `AuthenticationController.confirm` — auth-code check + login;
  expected silent, no shape evidence.
- `LicenseController.commercial` / `commercialLicenseDoc` /
  `nonCommercial` — pure view renders, no shape evidence.
- Admin/Avatar/Dashboard/Data/DataAI/Home controllers — read paths
  or admin CRUD; the 6 above already provide strong diversity and
  staying tight respects the 30-diagnostic audit cap.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` (Run A) and
  `/// @lint.context strict_replayable` (Run B) on each handler
  `func`. No logic edits, no imports, no new types.
- **Audit cap.** 30 diagnostics per mode (template default).
- **Data-layer audit required.** Per `road_test_plan.md` DB-heavy
  adopter rule, every write-style verdict gets re-checked against
  the actual SQL / Stripe API semantics. For Fluent
  `subscription.save(on:)` calls, check the Subscription migration
  for `.unique(on: "stripeId")` before reading raw SQL. For Stripe
  API calls, check the Stripe API contract (does the SDK inject
  `Idempotency-Key`? does the endpoint dedupe by some natural
  key?).

## Pre-committed questions

1. **Stripe customer-create on retry (`commercialCalculate`).**
   Does the `if customerId == nil { request.stripe.customers.create(...) }`
   pattern fire as non-idempotent in replayable mode? **Hypothesis:
   yes — this is the canonical payment-flow shape and a 2nd-adopter
   datapoint that should match matool's Cognito-`adminCreateUser`
   verdict (same shape: external SaaS API call with user-visible
   side effect on each invocation, no built-in dedup).**

2. **Webhook re-delivery (`StripeWebhookController.index`).** Does
   the Stripe webhook entry fire under replayable, with the deep-
   chain inferrer walking through the `switch` into the four
   sub-handlers? **Hypothesis: yes, fires; audit verdict per
   sub-handler — `subscriptionUpdate` / `invoiceUpdate` defensible,
   `checkoutCompleted` catch.**

3. **`createIfNotExist` recognition.** `User.createIfNotExist(db:email:stripeCustomerId:)`
   is an explicitly-idempotent helper the adopter wrote. Does the
   linter recognise the helper's body as safe (the function will
   either return an existing row or create one), or does it fire
   on the helper's `Subscription()` create-branch in
   `checkoutCompleted`? **Hypothesis: linter fires on
   `checkoutCompleted` because the find-or-create-then-mutate
   pattern is structurally identical to the create-on-retry shape
   the heuristic targets — even though the *intent* is idempotent,
   the body's `Subscription()` constructor is non-idempotent under
   replayable inference.**

4. **Magic-link email-on-retry (`sendMagicEmail`).** Does the auth
   handler fire as non-idempotent because of the `SendInBlue().sendEmail(...)`
   call? **Hypothesis: yes — and the verdict is real-bug-or-
   defensible by adopter design intent: magic-link UX often
   *intentionally* re-sends on a retry (so the user gets a fresh
   code), but a webhook-driven retry from a load-balancer would
   double-send. Verdict depends on whether the adopter has a
   dedup window upstream — if not, real-bug catch.**

## Predicted outcome

Run A yield prediction: 4 catches / 6 handlers = 0.67 (excluding
the 2 silent — `subscriptionUpdate` defensible, `index`
dispatcher; the other 4 fire as non-idempotent).

Real-bug shape prediction: **2 new shapes**
(`stripe.customers.create` on retry + find-or-create-Subscription
race), and **1 cross-adopter generalisation** (Cognito-shape →
Stripe-portal-create / Stripe-customer-create — pushes the
external-SaaS-API-on-retry slice from 1-adopter to 2-adopter
evidence).
