# pointfreeco — Trial Findings

## Run A — replayable context

**4 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

All catches are genuine "Stripe retry → duplicate email" bugs.
Every email-send call inside an annotated handler's retry window
fires; no false positives.

| Handler | Line | Callee | Inference path |
|---|---|---|---|
| `handlePaymentIntent` | 57 | `sendGiftEmail` | body inference via 2-hop chain of un-annotated callees |
| `handleFailedPayment` | 70 | `sendPastDueEmail` | body inference (calls `sendEmail` in its body) |
| `handleFailedPayment` | 75 | `sendEmail` | camelCase prefix match (`send` + `Email`) |
| `handleFailedPayment` | 94 | `sendEmail` | camelCase prefix match (in catch branch) |

All four `sendXEmail` sites are wrapped in `fireAndForget { ... }`
closures. The wrapper does not deduplicate — it just
"don't-block-the-response." On each Stripe retry, the email
re-sends. The linter correctly flags every site.

Per-handler yield:
- `stripePaymentIntentsWebhookMiddleware`: 0 — silent, only
  dispatches via `validateStripeSignature` + branch returns.
- `handlePaymentIntent`: 1 — `sendGiftEmail`.
- `stripeSubscriptionsWebhookMiddleware`: 0 — silent, only
  dispatches to `handleFailedPayment`.
- `handleFailedPayment`: 3 — all three email sends.

Two of four handlers produce catches; 4 catches across 2
non-silent handlers = 2.00 per-non-silent-handler yield. Highest
density observed of any round so far.

## Run B — strict_replayable context

**38 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (4): same four email-send catches.

**Strict-only** (34). Three clusters plus residual:

### Cluster 1: HttpPipeline DSL (12 diagnostics, ~35% of strict-only)

pointfreeco's custom `Conn`-based HTTP response-builder DSL.
Every response-construction chain produces unannotated diagnostics:

| Method | Firings |
|---|---|
| `writeStatus` | 5 |
| `respond` | 4 |
| `head` | 2 |
| `empty` | 1 |

Semantics: these are functional composition primitives
(`Conn<StatusLineOpen, Void>` → `Conn<ResponseEnded, Data>`).
They return a new Conn value; no side effects beyond allocation.
Classification should be `idempotent`.

**Fix shape:** adopter-side annotation. HttpPipeline is
pointfreeco-local, not a shared framework — a `FrameworkWhitelist`
entry would be specific to one adopter and wouldn't generalise.
The natural fix is `/// @lint.effect idempotent` (or
`@Idempotent` attribute) on the HttpPipeline declarations, or
cross-module effect annotations that the linter reads via
upward inference when it has source access.

### Cluster 2: Stripe webhook internal helpers (5 diagnostics)

| Method | Firings |
|---|---|
| `stripeHookFailure` | 3 |
| `validateStripeSignature` | 2 |

Both are pointfreeco-local helpers. `stripeHookFailure` constructs
a response + sends an error email; `validateStripeSignature` is
a pure read of the request. Adopter-responsibility annotations
(the first is non-idempotent, the second idempotent).

### Cluster 3: `fireAndForget` escape wrapper (4 diagnostics)

```swift
await fireAndForget {
    try await sendEmail(...)
}
```

`fireAndForget` itself is flagged as an unannotated callee. This
is the pattern from pointfreeco's swift-dependencies-dispatched
async fire-and-forget helper. The wrapper does not deduplicate
retries but it is "trusted" in the sense that adopter intent is
"this runs eventually, don't block."

**Fix shape:** adopter annotates `fireAndForget` as whatever
semantics they want. Most adopters would pick `observational`
(since it *intends* not to alter the response) but that's
adopter-dependent. Not a linter-side slice candidate.

### Residual (13 diagnostics)

| Method | Firings |
|---|---|
| `inj1` | 2 |
| `extraSubscriptionId` | 2 |
| `updateStripeSubscription` | 1 |
| `updateGiftStatus` | 1 |
| `String` | 1 |
| `removeBetaAccess` | 1 |
| `handleFailedPayment` | 1 |
| `fetchUser` | 1 |
| `fetchSubscription` | 1 |
| `fetchGift` | 1 |
| `either` | 1 |
| `sendEmail` | *(duplicate line in transcript)* |

Sub-patterns:

- **Database operations via swift-dependencies** (5):
  `updateStripeSubscription`, `updateGiftStatus`, `fetchUser`,
  `fetchSubscription`, `fetchGift`. The two `update*` calls are
  genuinely non-idempotent (DB writes) but don't fire in
  replayable mode because `update` is NOT in the bare
  `nonIdempotentNames` prefix list — it's Fluent-gated, and
  pointfreeco doesn't import `FluentKit`. The three `fetch*`
  calls are idempotent but aren't on any whitelist.
- **Prelude / Either helpers** (4): `inj1`, `either`,
  `String(customDumping:)`, `extraSubscriptionId` — pure functional
  plumbing, idempotent.
- **Cross-handler calls** (3): `removeBetaAccess`,
  `handleFailedPayment` called from the outer middleware. Upward
  inference has body evidence for the former (writes to GitHub
  via `removeRepoCollaborator`); adopter annotations would close
  the latter two.

## Comparison to todos-fluent

| Dimension | todos-fluent | pointfreeco |
|---|---|---|
| Handlers annotated | 3 (+1 helper) | 4 |
| Replayable catches | 4 (3 + macro-form) | 4 |
| Strict_replayable catches | 6 | 38 |
| Framework-shape | Hummingbird + FluentKit (both covered by gates) | Vapor DSL + custom HttpPipeline (no gates apply) |
| Primary adoption-gap shape | Framework primitives | Adopter-local DSLs + dependency-injected callees |

The **replayable yield is identical** (4 on each); the
**strict-mode residual is 6x higher on pointfreeco**. The gap is
structural: todos-fluent's strict-mode surface was composed of
framework primitives (Hummingbird, Fluent) that slice cleanly
into `FrameworkWhitelist` entries. pointfreeco's strict-mode
surface is composed of adopter-local callees that don't
generalise — HttpPipeline is pointfreeco's own, `fireAndForget`
is pointfreeco's own, the `@Dependency`-dispatched DB is
pointfreeco's own.

## Next-slice candidates

**Linter-side** (broadly applicable, not pointfreeco-specific):

1. **`update*` / `insert*` / `delete*` prefix-match for non-Fluent
   DB surfaces.** The current prefix list misses
   `updateStripeSubscription` / `updateGiftStatus` because `update`
   is Fluent-gated only. A non-Fluent adopter with
   swift-dependencies-dispatched DB methods (extremely common in
   Swift server ecosystem) gets no prefix-match. Shape: optional
   opt-in for "database-like" prefix semantics, or a new framework
   gate for swift-dependencies that recognises
   `@Dependency`-accessed properties.
2. **`fireAndForget` / escape-wrapper recognition.** Adopters
   across ecosystems (Vapor, AWS Lambda, Hummingbird) use
   fire-and-forget helpers. Naming conventions vary
   (`fireAndForget`, `detach`, `runInBackground`) but the shape
   is consistent. A per-ecosystem whitelist treating these as
   "trusted observational wrappers" would reduce strict-mode
   noise across multiple adopters.

**Adopter-side** (pointfreeco-specific, not slice-worthy):

- HttpPipeline DSL annotations — pointfreeco's call, not the
  linter's. Would require upstream annotations on `writeStatus`,
  `respond`, etc. declarations.
- `stripeHookFailure` / `validateStripeSignature` annotations —
  same.

**Deferred to later rounds:**

- Macro-form exercise — same reasoning as todos-fluent. pointfreeco
  doesn't consume `SwiftIdempotency`; adding the dep just for a
  measurement round is more invasive than warranted.
- `IdempotencyKey` validation — Stripe webhooks are the obvious
  carrier (pointfreeco's `paymentIntent.id` IS an idempotency
  key in the Stripe sense) but adding the strong type to a real
  codebase is a refactor, not a measurement.
