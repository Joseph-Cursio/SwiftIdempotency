# WebhookHandlerSample

A minimal end-to-end example of consuming `SwiftIdempotency`'s
`IdempotencyKey` strong type from downstream code.

The sample lives at `examples/webhook-handler-sample/` and depends on
the root `SwiftIdempotency` package via a local path dependency, so
running it exercises the real public API — not a stub.

## What this sample demonstrates

A Stripe-style webhook handler that translates a `PaymentIntent` event
into a `ChargeRequest`. The request carries an `IdempotencyKey` derived
from the event's stable `id`, so retried webhook deliveries produce the
same key and the downstream Stripe call dedupes.

The handler is deliberately pure — it returns a value-typed
`ChargeRequest` rather than calling out to Stripe — so the tests can
assert shape without any network leg.

Core files:

- `Sources/WebhookHandlerSample/StripeWebhookHandler.swift` — the
  `PaymentIntent` / `ChargeRequest` / `StripeWebhookHandler` types.
- `Tests/WebhookHandlerSampleTests/WebhookHandlerTests.swift` — three
  positive-path tests plus a **commented-out block** of compile-time
  rejection examples at the bottom.

## The type safety story

Positive path: `IdempotencyKey(fromEntity: event)` reads the stable
`event.id` and produces a key that's identical across retries. The
derivation is visible at the call site — a reviewer can confirm the
source is stable in one glance.

Negative path: the test file's trailing comment block shows three
patterns the type deliberately rejects at compile time. Uncomment any
of them to see the compiler refuse it:

1. `IdempotencyKey(UUID())` — no unlabeled UUID initialiser.
2. `IdempotencyKey = "evt_abc123"` — no `ExpressibleByStringLiteral`.
3. `IdempotencyKey()` — no `init()`.

Each rejection routes the caller to `fromEntity` (preferred) or
`fromAuditedString` (audit-labelled escape hatch).

## Running

```bash
cd examples/webhook-handler-sample
swift test
```

The package uses a path dependency on `../..`, so the tests reflect
the current state of the root `SwiftIdempotency` package you're sitting
on — no version pin to drift.

## Scope

This sample covers `IdempotencyKey` end-to-end in a consumer context.
It does **not** cover `@Idempotent` / `@NonIdempotent` /
`@Observational` / `@ExternallyIdempotent` / `@IdempotencyTests` /
`#assertIdempotent`. Those are exercised by the root package's own
test target and by the adopter road-tests under `docs/<slug>/`.

## Relationship to the linter

The type system catches the common compile-time case — raw `UUID()`,
string literals, default construction. Adopters can still smuggle an
unstable value in through `IdempotencyKey(fromAuditedString: UUID().uuidString)`.
That escape-hatch pattern is exactly what `SwiftProjectLint`'s
`missingIdempotencyKey` rule is designed to flag at the call site.
Type safety handles the common case; the linter handles the audit.
