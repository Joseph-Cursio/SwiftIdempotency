# SwiftIdempotency Tutorial

Build a payment-webhook handler from zero, layering on all four
SwiftIdempotency tiers along the way. By the end you'll have a small
package that compile-rejects unstable keys, declares its effects to
the linter, and verifies idempotency at test time both by return value
and by observed side effects.

This tutorial is one coherent thread. For a wider tour of the package
(other frameworks, integrations, design boundaries) see
[USER_GUIDE.md](USER_GUIDE.md). For a signature-by-signature reference,
see [REFERENCE.md](REFERENCE.md).

> **Quick framing.** Idempotency means "safe to repeat." A car-remote
> lock button is idempotent — pressing it twice doesn't lock the car
> harder. A classroom light switch isn't — pressing it again might
> turn lights on or off depending on state. We're building the lock
> button: a webhook handler that's safe to retry. See
> [USER_GUIDE.md §Idempotency in everyday life](USER_GUIDE.md#idempotency-in-everyday-life)
> for the longer framing.

## What we're building

A Stripe-style webhook handler. Stripe sends `payment_intent.succeeded`
events; on retry deliveries (network blips, processing timeouts) the
*same* event id arrives more than once. Our handler must:

1. Accept a `PaymentIntent` event.
2. Record the charge in a repository — exactly once per event id.
3. Return a `ChargeResult` to the caller.

We'll build it incrementally:

- [Setup](#setup)
- [Step 1: A naive handler that's not retry-safe](#step-1-a-naive-handler-thats-not-retry-safe)
- [Step 2: Take an `IdempotencyKey` (Tier 1)](#step-2-take-an-idempotencykey-tier-1)
- [Step 3: Annotate with `@ExternallyIdempotent` (Tier 2)](#step-3-annotate-with-externallyidempotent-tier-2)
- [Step 4: Verify with `#assertIdempotent` (Tier 3)](#step-4-verify-with-assertidempotent-tier-3)
- [Step 5: Verify side effects with `IdempotentEffectRecorder` (Tier 4)](#step-5-verify-side-effects-with-idempotenteffectrecorder-tier-4)
- [Recap and next steps](#recap-and-next-steps)

## Setup

Create a fresh package and add SwiftIdempotency:

```bash
mkdir PaymentTutorial && cd PaymentTutorial
swift package init --type library
```

Edit `Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PaymentTutorial",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Joseph-Cursio/SwiftIdempotency.git",
            from: "0.3.0"
        ),
    ],
    targets: [
        .target(
            name: "PaymentTutorial",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "PaymentTutorialTests",
            dependencies: [
                "PaymentTutorial",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
                .product(
                    name: "SwiftIdempotencyTestSupport",
                    package: "SwiftIdempotency"
                ),
            ]
        ),
    ]
)
```

`SwiftIdempotencyTestSupport` is only added to the *test* target — that's
where `assertIdempotentEffects` lives. The main module needs only
`SwiftIdempotency`.

Verify it builds:

```bash
swift build
```

## Step 1: A naive handler that's not retry-safe

Replace `Sources/PaymentTutorial/PaymentTutorial.swift` with:

```swift
import Foundation

// The shape of a Stripe webhook event we care about.
public struct PaymentIntent: Sendable {
    public let id: String          // e.g. "evt_abc123" — stable across retries
    public let amount: Int
    public let customerId: String

    public init(id: String, amount: Int, customerId: String) {
        self.id = id; self.amount = amount; self.customerId = customerId
    }
}

// What we record when a charge succeeds.
public struct ChargeRecord: Sendable, Equatable {
    public let chargeId: String
    public let amount: Int
    public let customerId: String
}

// What the handler returns to the caller.
public struct ChargeResult: Sendable, Equatable {
    public let chargeId: String
    public let status: String
}

// The repository we record into.
public protocol ChargeRepository: AnyObject, Sendable {
    func recordCharge(_ record: ChargeRecord) async throws
}

// First, naive version — just records the charge.
public actor PaymentHandler {
    let repo: ChargeRepository

    public init(repo: ChargeRepository) {
        self.repo = repo
    }

    public func handle(event: PaymentIntent) async throws -> ChargeResult {
        let chargeId = UUID().uuidString  // ⚠️ fresh per call
        let record = ChargeRecord(
            chargeId: chargeId,
            amount: event.amount,
            customerId: event.customerId
        )
        try await repo.recordCharge(record)
        return ChargeResult(chargeId: chargeId, status: "succeeded")
    }
}
```

This handler is **not idempotent**. On a retried delivery of the same
`PaymentIntent`, it generates a fresh `UUID()`, calls `recordCharge`
again, and produces a duplicate row in the repository. The customer
gets charged twice.

The bug is invisible from the outside: the handler returns
`ChargeResult` with a fresh `chargeId` each time, so even a returning
caller can't tell the second call duplicated state. We'll fix this in
stages.

## Step 2: Take an `IdempotencyKey` (Tier 1)

The fundamental problem in Step 1 is `UUID()` inside the handler. We
need a *stable* identifier across retries — one that's the same on the
first delivery and any retry deliveries Stripe sends.

The `PaymentIntent.id` field is exactly that: Stripe guarantees it's
stable across retried deliveries of the same event. So we can use it
as the charge id.

But we don't want to pass it around as a `String` — anyone could pass a
fresh `UUID().uuidString` and silently break idempotency. Make it a
type the compiler enforces.

Update `handle`:

```swift
import Foundation
import SwiftIdempotency

// ... (PaymentIntent / ChargeRecord / ChargeResult / ChargeRepository unchanged) ...

public actor PaymentHandler {
    let repo: ChargeRepository

    public init(repo: ChargeRepository) {
        self.repo = repo
    }

    public func handle(
        event: PaymentIntent,
        idempotencyKey: IdempotencyKey
    ) async throws -> ChargeResult {
        let record = ChargeRecord(
            chargeId: idempotencyKey.rawValue,
            amount: event.amount,
            customerId: event.customerId
        )
        try await repo.recordCharge(record)
        return ChargeResult(
            chargeId: idempotencyKey.rawValue,
            status: "succeeded"
        )
    }
}
```

Two changes: `handle` now takes an `IdempotencyKey`, and the `chargeId`
comes from that key's `rawValue` instead of `UUID()`.

The compile-time payoff: the call site can no longer pass any old
string. Try this in a scratch test:

```swift
let handler = PaymentHandler(repo: someRepo)
let event = PaymentIntent(id: "evt_abc123", amount: 100, customerId: "cus_42")

// ❌ Compile error: cannot convert value of type 'String' to expected
// argument type 'IdempotencyKey'.
_ = try await handler.handle(event: event, idempotencyKey: "evt_abc123")

// ❌ Compile error: cannot convert value of type 'UUID' to expected
// argument type 'IdempotencyKey'.
_ = try await handler.handle(event: event, idempotencyKey: UUID())

// ✅ Stable: derived from the event's stable id.
_ = try await handler.handle(
    event: event,
    idempotencyKey: IdempotencyKey(fromAuditedString: event.id)
)
```

`PaymentIntent` isn't `Identifiable` (its `id` is a `String`, not the
synthesised `Identifiable.ID`), so we use `fromAuditedString` and
audit the source explicitly. If `PaymentIntent` were `Identifiable`,
`IdempotencyKey(fromEntity: event)` would also work.

`swift build` should still succeed.

## Step 3: Annotate with `@ExternallyIdempotent` (Tier 2)

The handler's idempotency is *conditional*: it's idempotent **only**
when the caller passes a stable key. That's exactly what
`@ExternallyIdempotent(by:)` declares.

Add the annotation:

```swift
import SwiftIdempotency

public actor PaymentHandler {
    let repo: ChargeRepository

    public init(repo: ChargeRepository) {
        self.repo = repo
    }

    @ExternallyIdempotent(by: "idempotencyKey")
    public func handle(
        event: PaymentIntent,
        idempotencyKey: IdempotencyKey
    ) async throws -> ChargeResult {
        // ... unchanged ...
    }
}
```

The `by: "idempotencyKey"` argument is the *external* parameter label
exactly as written in the function signature.

What this gets you, even without a linter:

- **Self-documenting contract** — readers know at a glance that this
  function depends on a key being routed correctly.
- **Future linter coverage** — when SwiftProjectLint sees this function,
  its `missingIdempotencyKey` rule verifies call sites pass a stable
  value (rejecting `UUID()` / `Date()` patterns).

Without a linter the annotation is silent at runtime; it's just a
marker macro that expands to nothing. Adding it is safe and free.

`swift build` should still succeed.

## Step 4: Verify with `#assertIdempotent` (Tier 3)

We *say* the handler is idempotent when called twice with the same
key. Let's verify it.

Create `Tests/PaymentTutorialTests/PaymentTutorialTests.swift`:

```swift
import Foundation
import Testing
import SwiftIdempotency
import SwiftIdempotencyTestSupport
@testable import PaymentTutorial

// In-memory repo used in tests. Records every charge it receives.
final class InMemoryChargeRepo: ChargeRepository {
    private(set) var charges: [ChargeRecord] = []
    private let lock = NSLock()

    func recordCharge(_ record: ChargeRecord) async throws {
        lock.lock(); defer { lock.unlock() }
        charges.append(record)
    }
}

@Test("handle returns the same ChargeResult on a second invocation with the same key")
func handleIsIdempotentByReturn() async throws {
    let repo = InMemoryChargeRepo()
    let handler = PaymentHandler(repo: repo)
    let event = PaymentIntent(id: "evt_abc123", amount: 250, customerId: "cus_42")
    let key = IdempotencyKey(fromAuditedString: event.id)

    let result = try await #assertIdempotent {
        try await handler.handle(event: event, idempotencyKey: key)
    }

    #expect(result.status == "succeeded")
    #expect(result.chargeId == "evt_abc123")
}
```

Run it:

```bash
swift test
```

The test passes. `#assertIdempotent` invokes the closure twice and
asserts that both invocations return equal `ChargeResult` values. They
do, because `chargeId` comes from the stable `IdempotencyKey` rather
than a fresh `UUID()`.

If you want to *see* the failure shape, temporarily revert
`handle` to use `UUID().uuidString` for `chargeId`. Re-run — the test
aborts via `precondition` on the second call with:

```
#assertIdempotent: closure returned different values on re-invocation — not idempotent
```

Restore the `IdempotencyKey`-based version before continuing.

### Wait — what about the duplicate write?

Our test passed. But run this in your head:

- First `handler.handle` call: appends one `ChargeRecord` to
  `repo.charges`. Returns `ChargeResult(chargeId: "evt_abc123", ...)`.
- Second `handler.handle` call: appends *another* `ChargeRecord`.
  Returns the same `ChargeResult(chargeId: "evt_abc123", ...)`.

The two return values are equal. `#assertIdempotent` is happy. But
`repo.charges` now has **two** rows. The handler is *not* idempotent
at the observable-state level — the customer is still being charged
twice.

This is exactly the gap `#assertIdempotent` cannot close. Time for
Tier 4.

## Step 5: Verify side effects with `IdempotentEffectRecorder` (Tier 4)

Conform `InMemoryChargeRepo` to `IdempotentEffectRecorder` so it
reports *what it observed*, not just what it stored:

```swift
import SwiftIdempotency

final class InMemoryChargeRepo: ChargeRepository, IdempotentEffectRecorder {
    private(set) var charges: [ChargeRecord] = []
    private let lock = NSLock()

    // Required by IdempotentEffectRecorder.
    var effectCount: Int {
        lock.lock(); defer { lock.unlock() }
        return charges.count
    }

    func recordCharge(_ record: ChargeRecord) async throws {
        lock.lock(); defer { lock.unlock() }
        charges.append(record)
    }
}
```

`IdempotentEffectRecorder` requires:

- `effectCount: Int` — how many state-changing operations the recorder
  has seen. Reads don't count; only writes / sends / publishes.
- `snapshot()` — returns an `Equatable` snapshot. The default uses
  `Snapshot = Int` and returns `effectCount`, which is what we want
  here.

Add an effect-observation test:

```swift
@Test("handle does not record a duplicate charge on retry")
func handleIsIdempotentByEffect() async throws {
    let repo = InMemoryChargeRepo()
    let handler = PaymentHandler(repo: repo)
    let event = PaymentIntent(id: "evt_abc123", amount: 250, customerId: "cus_42")
    let key = IdempotencyKey(fromAuditedString: event.id)

    try await assertIdempotentEffects(recorders: [repo]) {
        _ = try await handler.handle(event: event, idempotencyKey: key)
    }
}
```

Run it:

```bash
swift test
```

The test **fails**. `assertIdempotentEffects` runs the body twice;
after the first call `effectCount == 1`, after the second call
`effectCount == 2`. The two snapshots differ, so the helper aborts
via `precondition`:

```
assertIdempotentEffects: handler is not idempotent.
Recorder InMemoryChargeRepo snapshot changed across the second invocation.
    baseline (pre-body):        0
    after first invocation:     1
    after second invocation:    2
The second invocation must be a no-op relative to the first.
```

We've found the bug. The handler returns the same `ChargeResult` on
both calls, but it writes to the repo on both calls. Tier 3 missed it
because the return values were equal. Tier 4 caught it because the
*effect* doubled.

### Fix the handler

Make the handler check the repo before recording. Update
`PaymentHandler` and `ChargeRepository`:

```swift
public protocol ChargeRepository: AnyObject, Sendable {
    func recordCharge(_ record: ChargeRecord) async throws
    func chargeExists(chargeId: String) async throws -> Bool
}

public actor PaymentHandler {
    let repo: ChargeRepository

    public init(repo: ChargeRepository) {
        self.repo = repo
    }

    @ExternallyIdempotent(by: "idempotencyKey")
    public func handle(
        event: PaymentIntent,
        idempotencyKey: IdempotencyKey
    ) async throws -> ChargeResult {
        let chargeId = idempotencyKey.rawValue

        // Idempotent guard: skip the write on retry.
        if try await repo.chargeExists(chargeId: chargeId) {
            return ChargeResult(chargeId: chargeId, status: "succeeded")
        }

        let record = ChargeRecord(
            chargeId: chargeId,
            amount: event.amount,
            customerId: event.customerId
        )
        try await repo.recordCharge(record)
        return ChargeResult(chargeId: chargeId, status: "succeeded")
    }
}
```

Update `InMemoryChargeRepo` to satisfy the new requirement, and notice
that we **only** count writes — reads must not bump `effectCount`:

```swift
final class InMemoryChargeRepo: ChargeRepository, IdempotentEffectRecorder {
    private(set) var charges: [ChargeRecord] = []
    private let lock = NSLock()

    var effectCount: Int {
        lock.lock(); defer { lock.unlock() }
        return charges.count
    }

    func recordCharge(_ record: ChargeRecord) async throws {
        lock.lock(); defer { lock.unlock() }
        charges.append(record)
    }

    // READ — does NOT increment effectCount.
    func chargeExists(chargeId: String) async throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return charges.contains(where: { $0.chargeId == chargeId })
    }
}
```

Run `swift test` again. Both tests pass. The handler is now idempotent
at both the return-value level (Tier 3) and the observable-effect
level (Tier 4).

### Confirming the fix

You can sanity-check by reading the repo state directly after the
test body:

```swift
@Test("handle records exactly one charge across two retried invocations")
func handleRecordsOnceOnRetry() async throws {
    let repo = InMemoryChargeRepo()
    let handler = PaymentHandler(repo: repo)
    let event = PaymentIntent(id: "evt_abc123", amount: 250, customerId: "cus_42")
    let key = IdempotencyKey(fromAuditedString: event.id)

    _ = try await handler.handle(event: event, idempotencyKey: key)
    _ = try await handler.handle(event: event, idempotencyKey: key)

    #expect(repo.charges.count == 1)
}
```

Pair this with `assertIdempotentEffects` for general retry coverage,
plus `#expect`-style state checks for the specific invariants you
care about.

## Recap and next steps

You now have a small package that:

- **Tier 1**: rejects `UUID()` and bare strings at the call site via
  `IdempotencyKey`.
- **Tier 2**: declares `@ExternallyIdempotent(by: "idempotencyKey")`,
  ready for SwiftProjectLint to enforce.
- **Tier 3**: verifies return-value equality with `#assertIdempotent`.
- **Tier 4**: verifies observable side effects with
  `IdempotentEffectRecorder` and `assertIdempotentEffects`.

You also learned the core lesson: **return-equality is necessary but
not sufficient**. Pair `#assertIdempotent` with effect observation any
time the handler's return value doesn't fully reflect its side effects.

### Where to go from here

- Replace `InMemoryChargeRepo` with **Fluent ORM** —
  see [`USER_GUIDE.md`§Integrating with Fluent ORM](USER_GUIDE.md#integrating-with-fluent-orm)
  for `init(fromFluentModel:)` and the post-save vs create-handler
  patterns.
- Replace it with **SwiftData** —
  see [`USER_GUIDE.md`§Integrating with SwiftData](USER_GUIDE.md#integrating-with-swiftdata)
  for the `@Model`-with-`id` clean path and the business-named-UUID
  workarounds.
- Wrap the handler in a **Vapor or Hummingbird route** —
  see [`USER_GUIDE.md`§Migrating inline-closure handlers](USER_GUIDE.md#migrating-inline-closure-handlers)
  for the extraction pattern that lets attribute macros attach.
- Lift it into an **AWS Lambda** runtime —
  see [`USER_GUIDE.md`§Integrating with AWS Lambda](USER_GUIDE.md#integrating-with-aws-lambda).
- Look up specific symbols in [`REFERENCE.md`](REFERENCE.md).

For working sample packages that compile and test, see the
[`examples/`](examples/) directory in this repo.
