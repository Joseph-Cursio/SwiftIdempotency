# OptionBSample

End-to-end consumer demonstration of `SwiftIdempotency`'s **Option B**
surface — `IdempotentEffectRecorder` + `assertIdempotentEffects` —
shipped in v0.3.0.

The sample lives at `examples/option-b-sample/` and depends on the
root `SwiftIdempotency` package via a local path dependency, so
running it exercises the real protocol + helper — not a stub.

## What this sample demonstrates

`#assertIdempotent` (Option C) compares return values. It's blind when
the handler returns `HTTPStatus.ok`, `Bool`, `Void`, or any other
trivial type regardless of side effects. Option B fills the gap by
observing what the handler **does** — mock dependencies conform to
`IdempotentEffectRecorder`, and `assertIdempotentEffects` runs the
body twice and asserts no recorder saw new effects on the retry.

Three call sites, covering the shapes adopters need:

| Scenario | Demonstrates |
|---|---|
| Dedup-guarded handler (default `failureMode`) | Passes — second invocation gated out, snapshot unchanged. |
| Ungated handler (`failureMode: .issueRecord`) | Reports via `Issue.record` without aborting, captured by `withKnownIssue`. |
| Dedup-guarded handler with custom `Snapshot` type | Passes with a richer `[String]` call-log snapshot instead of the default `Int`. |

Core files:

- `Sources/OptionBSample/OrderCreatedHandler.swift` — two handlers
  sharing the same trivial `Bool` return type: one dedup-guarded
  (correct), one ungated (the bug Option B catches).
- `Tests/OptionBSampleTests/OptionBTests.swift` — three `@Test` calls
  exercising the matrix above. Mocks conform to
  `IdempotentEffectRecorder` directly on the repository protocol.

## Mock shape

A test double doubles as both the repository abstraction and the
effect recorder:

```swift
final class MockOrderRepository: OrderRepository, IdempotentEffectRecorder, @unchecked Sendable {
    private(set) var effectCount = 0
    private(set) var inserted: [Order] = []

    func insert(_ order: Order) async throws {
        inserted.append(order)
        effectCount += 1
    }
}
```

The protocol lives in the main `SwiftIdempotency` target (not
`SwiftIdempotencyTestSupport`), so production instrumentation — retry
observability, metrics shims — can conform without a TestSupport
dependency. Only `assertIdempotentEffects` requires importing
`SwiftIdempotencyTestSupport`.

## Richer `Snapshot` types

`IdempotentEffectRecorder` has an associated `Snapshot: Equatable`
that defaults to `Int`. Override with any `Equatable` type to catch
non-idempotency invisible to counts alone (e.g. retries that re-order
operations, leaving total count unchanged but call order diverged):

```swift
final class CallLogOrderRepository: OrderRepository, IdempotentEffectRecorder {
    typealias Snapshot = [String]

    private(set) var insertedOrders: [String] = []
    var effectCount: Int { insertedOrders.count }

    func insert(_ order: Order) async throws {
        insertedOrders.append("\(order.id)@\(order.totalCents)")
    }

    func snapshot() -> [String] { insertedOrders }
}
```

## Failure modes

- `.preconditionFailure` (default) — `Swift.preconditionFailure(_:file:line:)`.
  Aborts the process; matches `#assertIdempotent`'s Option C behavior
  and works outside a Swift Testing context.
- `.issueRecord` — `Testing.Issue.record(_:sourceLocation:)`. Fails
  the enclosing `@Test` without aborting, so failure-path tests can
  be exercised via `withKnownIssue { }`. The sample's negative-case
  test uses this mode.

## Running

```bash
cd examples/option-b-sample
swift test
```

The package uses a path dependency on `../..`, so the tests reflect
the current state of the root `SwiftIdempotency` package you're
sitting on — no version pin to drift.

## Scope

This sample covers Option B end-to-end in a consumer context.
Companion samples cover the other surfaces:

- `examples/assert-idempotent-sample/` — `#assertIdempotent` (Option C).
- `examples/idempotency-tests-sample/` — `@IdempotencyTests`.
- `examples/webhook-handler-sample/` — `IdempotencyKey`.
- `examples/fluent-sample/` — `IdempotencyKey(fromFluentModel:)`.
- `examples/swiftdata-sample/` — `IdempotencyKey(fromEntity:)` on SwiftData `@Model`.

The four attribute macros (`@Idempotent` / `@NonIdempotent` /
`@Observational` / `@ExternallyIdempotent`) are exercised by the root
package's own test target and by the adopter road-tests under
`docs/<slug>/`.

## Relationship to `#assertIdempotent`

The two are complementary, not competing:

| Your handler's return value | Use |
|---|---|
| Meaningful `Equatable` (typed model, value type, number) | `#assertIdempotent` |
| Trivial (`Void`, `Bool`, `HTTPStatus.ok`) | `assertIdempotentEffects` |
| Meaningful **and** there are side effects | Both |

Option B validation for adopter codebases was done via the Penny bot
package-integration trial — see
[`docs/penny-package-trial/`](../../docs/penny-package-trial/) for
the trial artifacts that informed the v0.3.0 API shape.
