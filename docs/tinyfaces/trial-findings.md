# TinyFaces — Trial Findings

Seventeenth adopter road-test. **First Stripe-using adopter.** See
[`trial-scope.md`](trial-scope.md) for the research question and
pre-committed predictions.

## Run A — replayable

`swift run CLI /tmp/tinyfaces-scan --categories idempotency --threshold info`,
linter `0ca8a12`, target `db3f2b6` (trial branch `trial-tinyfaces`
@ `85e642a`). Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**6 fires across 4 of 6 annotated handlers. 3 distinct real-bug shapes
after data-layer audit.**

### Per-diagnostic table

| # | Location | Callee | Verdict | Notes |
|---|----------|--------|---------|-------|
| A1 | `StripeWebhookController.swift:7` | `index` | silent | **Adoption gap** — switch-dispatch deep-chain miss (see Run B §3). |
| A2 | `StripeWebhookController.swift:46` | `subscriptionUpdate` | silent | **Correctness signal — defensible-by-design.** Fixed-row update by `stripeId` lookup; replay produces same final state. Silence is correct. |
| A3 | `StripeWebhookController.swift:80` | `create` (`portalSession.create`) | **defensible** | Stripe portal session is short-lived (~5 min) and per-request by design. Fires on `create` prefix; data-layer audit: no user-visible side effect, no orphaning beyond Stripe's session quota. |
| A4 | `StripeWebhookController.swift:143` | `createIfNotExist` (User) — leads to `Subscription()` create | **CORRECT CATCH (real bug)** | Find-or-create race on `Subscription` row. `CreateSubscription` migration declares NO `.unique(on: "stripe_id")` constraint (`Sources/App/Migrations/CreateSubscription.swift`); concurrent webhook re-delivery can produce duplicate Subscription rows for the same Stripe subscription. Filing-worthy. |
| A5 | `LicenseController.swift:98` | `create` (`stripe.customers.create`) | **CORRECT CATCH (real bug)** | `if customerId == nil { stripe.customers.create(email:) }` — on retry, second invocation also sees `customerId == nil` (first transaction not yet committed), creates a duplicate Stripe customer. `User` migration's `.unique(on: "stripe_customer_id")` saves the local DB but leaves an **orphaned Stripe customer** on Stripe's side (still billable for any session attached). Filing-worthy. |
| A6 | `LicenseController.swift:104` | `create` (`stripe.sessions.create`) | **defensible** | Stripe Checkout Session is short-lived (24h default) and intentionally per-attempt. Fires on `create` prefix; data-layer audit: no user-visible side effect, sessions self-expire. |
| A7 | `AuthenticationController.swift:39` | `sendEmail` (existing-user branch) | **CORRECT CATCH (real bug)** | Calls `SendInBlue().sendEmail(...)` — sends a transactional email via Brevo on every invocation. On a load-balancer retry, the user receives **two magic-link emails with two different codes** (different `code` value generated each call). User-initiated re-send is fine; LB-retry is the canonical retry context this rule targets. Filing-worthy. |
| A8 | `AuthenticationController.swift:46` | `sendEmail` (new-user branch) | **CORRECT CATCH (real bug)** | Same shape as A7 but on the new-user branch. Plus: precedes `User.save` with no `.unique(on: "email")` constraint on `users` migration — concurrent LB-retry could create two User rows with the same email. Same root cause as A7; counts as the same shape. |

(A1 + A2 are silent handlers, not in the 6-fire count. A4 is one diagnostic but a deep-chain trace through `User.createIfNotExist` → `Subscription()`. The "6 fires" total breaks down as 4 distinct fires + 2 doubled fires (A5/A6 and A7/A8).)

### Yield

- **6 catches / 6 handlers = 1.00** including silent.
- **6 catches / 4 non-silent handlers = 1.50** excluding silent.
- **3 distinct real-bug shapes / 6 handlers = 0.50** (real-bug rate per handler).

### Real-bug shape inventory (after data-layer audit)

1. **Subscription find-or-create race without unique constraint**
   (A4). `CreateSubscription` migration is missing `.unique(on: "stripe_id")`.
   Same family as prospero PR #8 / hellovapor PR #1. **Filing
   candidate.**
2. **Stripe customer orphan on retry without `Idempotency-Key`**
   (A5). `if customerId == nil { stripe.customers.create(...) }`
   has no idempotency-key wrapping; retry creates a duplicate
   Stripe-side customer that may be orphaned post-race. **Filing
   candidate — and direct test of `SwiftIdempotency.IdempotencyKey`
   value proposition.**
3. **Magic-link email double-send on LB retry** (A7+A8). Same
   shape family as matool's Cognito `adminCreateUser` —
   external email API call on every invocation, no idempotency
   guard. **Pushes the email-on-retry-without-idempotency-key
   slice from 1-adopter to 2-adopter evidence** (vendor-
   independent: matool used Cognito, TinyFaces uses Brevo).
   **Filing candidate.**

## Run B — strict_replayable

Trial branch `trial-tinyfaces` @ `6e51ae3` (annotations flipped).
Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**67 fires (Run A's 6 + 61 strict-only).** Above the 30-cap; per
`road_test_plan.md` audit, decomposed by class without per-
diagnostic verdicts.

### Carried from Run A

All 6 Run A `[Non-Idempotent In Retry Context]` fires reproduce
identically. Verdicts unchanged.

### Strict-only (61 fires)

All 61 are `[Unannotated In Strict Replayable Context]` —
strict mode's "every callee must carry an explicit
`@lint.effect` annotation" rule. Decomposition:

| Cluster | Count | Examples | Verdict shape |
|---------|-------|----------|---------------|
| **C1. Vapor / Foundation primitives** | ~22 | `Response(status:)`, `request.redirect(to:)`, `request.view.render(...)`, `request.content.decode(...)`, `JSONDecoder()`, `Data(buffer:)`, `Int(_:)`, `print(_:)` | **Framework whitelist gap.** All of these are effect-free framework constructors / observational primitives. Should be globally idempotent / observational by framework whitelist. Not filing-worthy; framework-whitelist slice candidate. |
| **C2. Fluent query-builder reads + writes** | ~14 | `query`, `filter`, `first`, `get`, `save`, `requireID`, `find` | Reads (`query` / `filter` / `first` / `find`) covered by slice 13 in replayable mode but un-annotated under strict. Writes (`save`) are correctly fire-worthy under strict. Mixed cluster: slice 13 generalisation candidate (idempotent annotation in strict), `save` cluster correctly fires. |
| **C3. Adopter helpers called from annotated entry** | ~7 | `subscriptionUpdate`, `invoiceUpdate`, `checkoutCompleted`, `sendEmail`, `getEmailUsername`, `commercial`, `activeSubscriptions` | **Annotation-form gap.** These are sibling handlers in the same controller — annotated with `@lint.context` but not `@lint.effect`. Strict mode wants effect annotations, not context annotations. Adopter education / docs gap, not a linter slice. |
| **C4. Stripe API calls (Run A's catches)** | ~5 | `create`, `createIfNotExist`, `retrieve`, `verifySignature` | The Run A `create` catches reproduce. `retrieve` (`stripe.sessions.retrieve`) is a read — should be idempotent. `verifySignature` is a pure crypto check — should be idempotent. **Stripe-kit framework-whitelist slice candidate.** |
| **C5. Constructors / enum cases / local types** | ~9 | `User(...)`, `Subscription()`, `CommercialContext(...)`, `.checkoutSession(...)`, `.invoice(...)`, `.subscription(...)` | **Constructor + enum-case detection gap.** Calls to type initialisers and pattern-match enum cases are flagged but should be effect-free. Linter-side fix: skip `MemberAccessExpr` patterns where the receiver is a known type. |
| **C6. Auth / validation primitives** | ~4 | `request.auth.require`, `request.auth.login`, `request.cache.set`, `request.cache.get`, `Validatable.validate` | Vapor session/auth surface. Mixed: `require`/`login` should be idempotent (load session); `cache.set` is a write but TTL-bounded. Adopter-side annotation candidate, not a linter slice. |

**No new adoption-gap slices** in Run B. The 61 strict-only fires
all map to existing decomposition shapes from prior rounds:
framework-whitelist gaps (C1, C4, C6), strict-mode annotation
chain-back (C3), and constructor/enum-case detection (C5).

## Predicted vs actual

| Prediction (from scope §"Predicted outcome") | Actual |
|----------------------------------------------|--------|
| Run A yield: 4 catches / 6 handlers = 0.67 (with 2 silent) | **6 catches / 6 = 1.00** (with 2 silent — close enough; Stripe customers/sessions both fire as 2 separate diagnostics). |
| 2 new shapes + 1 cross-adopter generalisation | **3 new shapes + 1 cross-adopter generalisation.** Stripe-customer-orphan and Subscription-dup-row both novel; magic-link-email is cross-adopter (Brevo) datapoint for matool's Cognito email-on-retry shape. |
| `index` switch-dispatch fires via deep chain | **Negative.** `index` silent — deep-chain inference does NOT walk into the switch sub-handlers. Adoption gap candidate (slice 23 — see below). |
| `subscriptionUpdate` defensible-by-design (silent or fires) | **Silent — correctness signal.** The linter's `find-by-stripeId-then-mutate-fixed-row` pattern is correctly classified as idempotent without explicit annotation. |

## Comparison to prior rounds

- **vs matool (round 16):** matool's email-on-retry shape (Cognito
  `adminCreateUser`) is now 2-adopter via Brevo `sendEmail`.
  Promotes the cross-adopter slice from 1-adopter speculation to
  2-adopter slice candidate (different vendor SDKs, identical
  retry semantics — both are external SaaS APIs that send email
  with no built-in dedup unless caller wraps with idempotency
  key).
- **vs hellovapor (round 13) / prospero (round 9):** Both filed
  PRs flagged missing `.unique(on:)` constraints (PR #1 / PR #8).
  TinyFaces' `CreateSubscription` is the third instance of the
  same shape — confirms the cross-adopter pattern of "Vapor +
  Fluent + external-ID-as-stripe-style-foreign-key without
  composite unique" as a stable real-bug shape across the
  Vapor/Fluent ecosystem.
- **vs penny-bot (round 6):** Both adopters use external SaaS
  APIs that send messages on retry (Discord webhooks vs Stripe
  sessions vs Brevo emails). All three would benefit from
  `IdempotencyKey`-wrapped helper macros in adopter code.

## Linter slice candidates (named, not yet filed)

1. **Switch-dispatch deep-chain inference** (slice candidate). The
   `StripeWebhookController.index` shape — a webhook entry that
   dispatches via `switch (event.type, event.data?.object)` to
   four sibling handlers in the same class — does not propagate
   the non-idempotent inference upward. Fix direction: teach
   `EffectSymbolTable.runInferencePass` to walk `SwitchExprSyntax`
   case bodies as direct callees, not as nested expressions.
2. **Stripe-kit framework whitelist** (slice candidate). Add
   `request.stripe.*` namespace to
   `idempotentReceiverMethodsByFramework` (commit `040f186`):
   `verifySignature` (idempotent), `sessions.retrieve` (idempotent),
   `customers.retrieve` (idempotent), and the `.create` /
   `.createIfNotExist` family (correctly non-idempotent — already
   firing). Single-adopter for now; 2nd-adopter trigger if a
   future Vapor + Stripe round shows the same shape.

## Real-bug filing queue

Three Filing-worthy catches identified:

1. **TinyFaces — `CreateSubscription` missing `.unique(on: "stripe_id")`.**
   Same family as `samalone/prospero#8` and `sinduke/HelloVapor#1`.
   Per [`ideas/pointfreeco-triage-issue.md`](../ideas/pointfreeco-triage-issue.md)
   filing pattern.
2. **TinyFaces — `commercialCalculate` Stripe customer orphan
   without `Idempotency-Key`.** Direct demonstration of the
   `SwiftIdempotency.IdempotencyKey` use case. Fix is to wrap
   `request.stripe.customers.create(...)` in a Stripe
   idempotency-key (Stripe SDK supports this).
3. **TinyFaces — `sendMagicEmail` LB-retry double-email.**
   Either dedup by request hash + window, or move email-send
   behind an idempotency-keyed queue.

License caveat: **TinyFaces has no LICENSE file.** Filing PRs is
fine technically (a PR is a contribution, not a derivative
work redistribution), but the maintainer's response posture
to a non-contribution-fork-originated PR is unknown — last
upstream push was 2024-02. Proposed approach: open one PR
with the most-impactful finding (Stripe customer orphan, since
it directly hits the `IdempotencyKey` story), wait for response;
file the other two only if the first lands.
