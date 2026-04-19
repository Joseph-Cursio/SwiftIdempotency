# pointfreeco — Trial Findings

## Run A — replayable context

**6 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).
Post-PR-15 — the `update`-as-bare-prefix slice added 2 catches
(`updateGiftStatus`, `updateStripeSubscription`) that the
Fluent-only `update` gate missed on pointfreeco's non-Fluent DB.

| Handler | Line | Callee | Inference path |
|---|---|---|---|
| `handlePaymentIntent` | 57 | `sendGiftEmail` | body inference via 2-hop chain of un-annotated callees |
| `handlePaymentIntent` | 59 | `updateGiftStatus` | camelCase prefix match (`update` + `GiftStatus`) |
| `handleFailedPayment` | 56 | `updateStripeSubscription` | camelCase prefix match (`update` + `StripeSubscription`) |
| `handleFailedPayment` | 70 | `sendPastDueEmail` | body inference (calls `sendEmail` in its body) |
| `handleFailedPayment` | 75 | `sendEmail` | camelCase prefix match (`send` + `Email`) |
| `handleFailedPayment` | 94 | `sendEmail` | camelCase prefix match (in catch branch) |

Every call that would duplicate-act on Stripe retry is flagged:
- Email sends (4) — duplicate emails to users and admins.
- DB updates (2) — duplicate writes. Usually idempotent in
  practice if the update payload is deterministic and the DB
  semantics are "overwrite," but the linter can't know the
  DB's concurrency guarantees, so flagging is correct.

All four `sendXEmail` sites are wrapped in `fireAndForget { ... }`
closures. The wrapper does not deduplicate — it just "don't-block-
the-response." On each Stripe retry, the email re-sends.

Per-handler yield:
- `stripePaymentIntentsWebhookMiddleware`: 0 — silent, only
  dispatches via `validateStripeSignature` + branch returns.
- `handlePaymentIntent`: 2 — `sendGiftEmail`, `updateGiftStatus`.
- `stripeSubscriptionsWebhookMiddleware`: 0 — silent, only
  dispatches to `handleFailedPayment`.
- `handleFailedPayment`: 4 — three email sends + one DB update.

Two of four handlers produce catches; 6 catches across 2
non-silent handlers = 3.00 per-non-silent-handler yield. Highest
density observed of any round so far.

## Run B — strict_replayable context

**38 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (6): the 4 email-send catches plus the
2 `update*` catches. Total count unchanged by PR #15, but two
catches that previously fired as "unannotated in strict" now
fire as "non-idempotent in retry" — same rule as replayable
mode, better-characterised.

**Strict-only** (32). Three clusters plus residual:

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

### Residual (11 diagnostics)

Post-PR-15, two of the previous residual entries (`updateStripeSubscription`,
`updateGiftStatus`) now fire as non-idempotent in both modes and
count against Run A instead. Residual shrinks accordingly.

| Method | Firings |
|---|---|
| `inj1` | 2 |
| `extraSubscriptionId` | 2 |
| `String` | 1 |
| `removeBetaAccess` | 1 |
| `handleFailedPayment` | 1 |
| `fetchUser` | 1 |
| `fetchSubscription` | 1 |
| `fetchGift` | 1 |
| `either` | 1 |

Sub-patterns:

- **Database reads via swift-dependencies** (3): `fetchUser`,
  `fetchSubscription`, `fetchGift`. Idempotent but not on any
  whitelist — no current `fetch*` prefix heuristic exists.
- **Prelude / Either helpers** (5): `inj1` x2, `either`,
  `String(customDumping:)`, `extraSubscriptionId` x2 — pure
  functional plumbing, idempotent.
- **Cross-handler calls** (3): `removeBetaAccess`,
  `handleFailedPayment` called from the outer middleware. Upward
  inference has body evidence for `removeBetaAccess` (writes to
  GitHub via `removeRepoCollaborator`); adopter annotations would
  close the rest.

## Comparison to todos-fluent

| Dimension | todos-fluent | pointfreeco |
|---|---|---|
| Handlers annotated | 3 (+1 helper) | 4 |
| Replayable catches | 4 (3 + macro-form) | 6 |
| Strict_replayable catches | 6 | 38 |
| Framework-shape | Hummingbird + FluentKit (both covered by gates) | Vapor DSL + custom HttpPipeline (no gates apply) |
| Primary adoption-gap shape | Framework primitives | Adopter-local DSLs + dependency-injected callees |

The **replayable yield is higher on pointfreeco** post-PR-15
(6 vs 4). The **strict-mode residual is 6x higher on pointfreeco**
— the gap is structural: todos-fluent's strict-mode surface was
composed of framework primitives (Hummingbird, Fluent) that slice
cleanly into `FrameworkWhitelist` entries. pointfreeco's strict-
mode surface is composed of adopter-local callees that don't
generalise — HttpPipeline is pointfreeco's own, `fireAndForget`
is pointfreeco's own, the `@Dependency`-dispatched DB is
pointfreeco's own.

## Next-slice candidates

**Linter-side** (broadly applicable, not pointfreeco-specific):

1. ~~**`update*` prefix-match for non-Fluent DB surfaces.**~~
   **Landed as PR #15.** `update` moved to the bare
   `nonIdempotentNames` list; pointfreeco's 2 `update*`
   database calls now fire in both replayable and strict modes.
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
