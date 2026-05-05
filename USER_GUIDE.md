# SwiftIdempotency User Guide

A task-oriented guide to using SwiftIdempotency in real codebases. If you
want a step-by-step walkthrough that builds one thing end-to-end, read
[TUTORIAL.md](TUTORIAL.md) first. If you want signature-by-signature
documentation of every public symbol, see [REFERENCE.md](REFERENCE.md).
This guide sits between those two — it explains *when* to reach for
each tool and how the pieces compose.

## Contents

- [Idempotency in everyday life](#idempotency-in-everyday-life)
- [The four-level enforcement strategy](#the-four-level-enforcement-strategy)
- [Foundational concepts](#foundational-concepts)
- [Mental model: four tiers of safety](#mental-model-four-tiers-of-safety)
- [Choosing the right tier](#choosing-the-right-tier)
- [Tier 1: `IdempotencyKey` for compile-time enforcement](#tier-1-idempotencykey-for-compile-time-enforcement)
- [Tier 2: Annotation attributes for the linter](#tier-2-annotation-attributes-for-the-linter)
- [Tier 3: Test scaffolding for return-equality checks](#tier-3-test-scaffolding-for-return-equality-checks)
- [Tier 4: Effect observation for trivial-return handlers](#tier-4-effect-observation-for-trivial-return-handlers)
- [Integrating with Fluent ORM](#integrating-with-fluent-orm)
- [Integrating with SwiftData](#integrating-with-swiftdata)
- [Integrating with Vapor and Hummingbird](#integrating-with-vapor-and-hummingbird)
- [Integrating with AWS Lambda](#integrating-with-aws-lambda)
- [Migrating inline-closure handlers](#migrating-inline-closure-handlers)
- [Coordination with SwiftProjectLint](#coordination-with-swiftprojectlint)
- [Design boundaries](#design-boundaries)

## Idempotency in everyday life

Before the lattice and the macros, the intuition. Idempotent systems
are designed around a *desired end state*, not a *state transition*.
Three examples from outside software make the distinction concrete.

### Car door lock (idempotent)

A car remote locks the doors — even when they're already locked. The
button means "ensure locked," not "toggle lock." Pressing it a second
time is mechanically a no-op: nothing moves, nothing changes. The
driver gains confirmation without consequence — they don't have to
remember whether they already locked the car.

### Elevator button (idempotent request)

Pressing an already-lit elevator button does not summon the elevator
faster, despite a widely-held folk belief in "ele-acceleration." The
system interprets repeated presses as the same intent, not as
additional work. Repeating the action is safe and changes nothing.

### Classroom light switches (non-idempotent)

A classroom with multiple entrances and multiple switches: flipping a
switch might turn lights on, or off, depending on current state. The
caller has to remember or infer that state to predict the outcome.
Repeating the action is not safe — the same gesture produces opposite
results depending on history.

| Property | Car Lock | Elevator Button | Light Switch |
|----------|----------|------------------|--------------|
| Requires memory | ❌ No | ❌ No | ✅ Yes |
| Safe to repeat | ✅ Yes | ✅ Yes | ❌ No |
| Outcome predictable | ✅ Yes | ✅ Yes | ❌ No |
| Mental model | Ensure state ("locked") | Ensure request is registered | Toggle state |
| Repeated action effect | No additional effect | No additional effect | Reverses or changes state |
| Undo available | Not needed | Not needed | Sometimes (flip again) |
| User confidence | High | High | Low |

In simple local systems, a toggle's mistakes can often be undone by
flipping again. In distributed systems, actions are often irreversible,
delayed, or have side effects that can't be cleanly undone — sending
an email, charging a credit card, publishing to a queue. That's where
"ensure state" operations become much more valuable than toggles. The
four tiers of this package exist to make Swift code behave more like
the car lock or elevator button, and less like the classroom light
switches.

## The four-level enforcement strategy

Swift has no first-class support for idempotency as a language or
static-analysis concept. Functions that must be safe to call multiple
times — event handlers, retry-wrapped network calls, upsert
operations — carry that contract only in documentation or team
convention. Violations are silent and often expensive.

SwiftIdempotency, together with
[SwiftProjectLint](https://github.com/Joseph-Cursio/SwiftProjectLint),
implements a four-level enforcement strategy. Each level is
independently valuable and can be adopted incrementally.

### Level 1: Annotation (intent declaration)

The first level isn't trying to prove anything — it's stating intent.
Annotating a function as idempotent (or not) makes an explicit claim
about how it should behave when called multiple times. This shifts
idempotency from an implicit assumption — buried in comments or tribal
knowledge — into something visible, reviewable, and enforceable. The
level establishes a shared language: developers, reviewers, and tools
align on what a piece of code is meant to guarantee before worrying
about whether the guarantee actually holds.

### Level 2: Static analysis (reasoning about code)

Once intent is declared, the next step is to reason about whether the
code appears to honor it. Static analysis examines function bodies,
call graphs, and known effects to detect obvious violations or
inconsistencies — purely at compile time. It can't be perfect, but it
provides early feedback by catching mismatches between declared intent
and observable structure. The system acts like a skeptical reviewer:
"Given what we can see, does this claim of idempotency make sense?"

### Level 3: Runtime validation (behavioural probing)

Static reasoning has limits, especially when behaviour depends on
runtime state, external systems, or timing. Runtime validation
complements static analysis by observing how code actually behaves
when executed. Rather than proving correctness, these checks act as
probes — running functions multiple times under varying conditions to
detect obvious idempotency violations. The level bridges the gap
between theory and reality, offering empirical signals that something
may be wrong even when static analysis can't detect it.

### Level 4: Type system & composition (guarantees by construction)

The final level moves from checking behaviour to structuring code so
that correct behaviour is easier to achieve and maintain. Encoding
idempotency into types and abstractions enables the compiler — and
the design itself — to enforce constraints through composition.
Instead of repeatedly verifying that individual functions behave
correctly, you build systems where idempotency naturally emerges from
how components are combined. The most powerful level, but also the
most demanding — it requires careful API and type design so that
guarantees aren't just asserted or checked, but built into the
architecture itself.

### How the levels map to this package

The strategy spans both SwiftIdempotency and SwiftProjectLint. The
next section ("Mental model: four tiers of safety") describes what
*this package* delivers; the table below maps strategy levels to
package surface:

| Strategy level | What this package provides |
|---|---|
| Level 1: Annotation | `@Idempotent` / `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent(by:)` |
| Level 2: Static analysis | Delegated to [SwiftProjectLint](https://github.com/Joseph-Cursio/SwiftProjectLint), which reads the same annotations |
| Level 3: Runtime validation | `#assertIdempotent`, `@IdempotencyTests`, `assertIdempotentEffects` |
| Level 4: Type system | `IdempotencyKey` |

Most codebases shouldn't start with the full model. The minimum-
viable adoption path is Levels 1 and 4 on a few high-value call
sites — annotate the obvious idempotent and non-idempotent functions,
migrate the dedup-key parameters to `IdempotencyKey`, and let Levels
2 and 3 follow when concrete bugs surface that those layers would
have caught.

## Foundational concepts

Three conceptual pieces underpin everything that follows. Skim them
once; they recur throughout the integration sections and the linter
rule names.

### Idempotency is not purity

The two properties are often conflated, but the model treats them as
distinct.

- **Purity**: no side effects; same inputs always produce the same
  outputs. `f(x) == f(x)` for any `x`.
- **Idempotency**: calling multiple times produces the same *effect*
  as calling once. `f(f(x)) == f(x)`.

These overlap but are not equivalent:

```swift
// Pure but NOT idempotent
func append(to list: [Int], value: Int) -> [Int] {
    list + [value]  // deterministic, but f(f(x)) ≠ f(x)
}

// Idempotent but NOT pure
func setFlag(in db: Database, key: String) {
    db.set(key, true)  // has a side effect, but calling twice = calling once
}

// Neither
func chargeCard(amount: Int) { /* ... */ }

// Both
func compute(x: Int) -> Int { x * 2 }
```

The package — and the linter that consumes its annotations — reasons
about *effects on external state*, not about local non-determinism.
A function that uses `UUID()` internally for a log trace is not
necessarily non-idempotent; what matters is whether the
non-deterministic value escapes the function boundary.

### Observable equivalence: what "same effect" means

"Idempotent" means "calling twice produces the same effect as calling
once." That phrase only has teeth if *effect* and *same* are pinned
down.

**Working definition:**

> A function `f` is idempotent with respect to an observer `O` if, for
> any input `x`, the sequence `f(x); f(x)` leaves `O` in a state
> indistinguishable from the sequence `f(x)` alone.

Three parameters must be made concrete for any given function:

- **Observable state.** The surface the observer can inspect. For most
  business logic this is persistent storage (database rows,
  filesystem, object storage) plus outbound messages (emails,
  webhooks, queue publishes). It explicitly *excludes* internal trace
  IDs, debug logs, cache warmth, and wall-clock timestamps in audit
  rows that are present for forensics rather than semantics.
- **Equivalence relation.** Usually structural equality on the
  observable surface. Weaker relations are legitimate when documented
  — e.g., "equal modulo the `updated_at` column," "equal modulo log
  line ordering." The relation is part of the contract, not a
  universal constant.
- **Observer scope.** Who is watching. End users and downstream
  services are in scope; an internal APM agent counting function
  invocations is not.

There is no single global definition of equivalence. Each
`@Idempotent` annotation should be *reviewable* against this frame: a
reader should be able to ask "what's the observable state, what's the
equivalence relation, who's the observer?" and get a defensible
answer. When the answer is non-obvious, document it in the function's
doc comment.

For the externally-idempotent tier (`@ExternallyIdempotent(by:)`),
the observer is typically the external system's deduplication layer,
and the equivalence relation is "the provider treats these calls as
the same operation" — a claim grounded in the provider's contract,
not in the function body.

### Partial failure and the retry contract

Idempotency is frequently discussed as a property of *successful*
calls — if `f(x); f(x)` both complete, they produce the same effect
as `f(x)` alone. In production, the execution paths that matter most
are the ones that *don't* complete. A function that begins, mutates
external state, then throws leaves the observer in an intermediate
state the retry has to reconcile.

The canonical failure mode:

```swift
// ❌ Each individual call is idempotent in isolation.
//    The composite is not — partial completion leaves state inconsistent.
func processPayment(id: PaymentID) async throws {
    try await chargeCard(id)               // succeeds, card is charged
    try await updateOrderStatus(id, .paid) // throws — network blip
}
```

On retry, `chargeCard` with the same key is deduplicated server-side,
`updateOrderStatus` retries and succeeds. OK — but only because
`chargeCard` is externally idempotent on its key. If `chargeCard` were
non-idempotent, the retry would double-charge.

Distinguish two contracts:

- **Unconditional idempotency**: the function is idempotent on *every*
  execution path, including paths that throw partway through. The
  observable state after any prefix of the function's execution is
  either the pre-call state or the post-call state — never an
  intermediate state that makes retry unsafe.
- **Atomic idempotency**: the function is idempotent *only* when its
  side effects commit atomically — typically because they're wrapped
  in a database transaction, a filesystem rename, or a single-message
  queue publish. If the atomic boundary is absent or broken, the
  function degrades to non-idempotent.

Compensating actions (manually rolling back a pre-failure write when
atomicity isn't available) are the mechanism teams reach for in the
gap between the two contracts. Document the compensating story
explicitly — a `reason:` clause on the doc-comment form
(`/// @lint.effect idempotent reason: "compensates on throw"`) makes
the claim reviewable.

The default expectation is unconditional: every `@Idempotent`
declaration is read as a claim that holds on *every* execution path
through the function, including early-throw paths. A function that
is idempotent only on the happy path needs either a transaction
boundary, a compensating-action story, or `@NonIdempotent`.

## Mental model: four tiers of safety

SwiftIdempotency offers four tiers, ordered by how early they catch
mistakes:

1. **Compile time** — `IdempotencyKey` makes "passing a fresh UUID where
   a stable key is required" a *type error*, not a runtime mistake.
2. **Lint time** — the `@Idempotent` / `@NonIdempotent` / `@Observational`
   / `@ExternallyIdempotent` attributes are read by SwiftProjectLint to
   enforce call-graph rules statically.
3. **Test time, return equality** — `#assertIdempotent` and
   `@IdempotencyTests` invoke a function twice and compare return values
   via `Equatable`. Catches non-idempotency that surfaces in the return.
4. **Test time, effect observation** — `IdempotentEffectRecorder` and
   `assertIdempotentEffects` watch what a handler *does* (writes, sends,
   publishes) rather than what it returns. Catches non-idempotency that
   the return value hides.

The tiers compose. They're additive, not alternatives. A handler that
takes `IdempotencyKey`, is annotated `@ExternallyIdempotent(by:)`, and
has both `#assertIdempotent` and `assertIdempotentEffects` tests gets
all four kinds of coverage.

## Choosing the right tier

Start with the tier that matches the *risk* you're carrying:

| Risk | Tier |
|---|---|
| A caller might pass `UUID()` where a stable key is required | Tier 1: `IdempotencyKey` |
| A reader can't tell which functions are idempotent and which aren't | Tier 2: annotations |
| A function looks idempotent but isn't, and its return value would expose the bug | Tier 3: `#assertIdempotent` |
| A function looks idempotent but isn't, and its return value *won't* expose the bug | Tier 4: `assertIdempotentEffects` |

The recommended adoption shape:

1. Migrate one or two high-value call sites to `IdempotencyKey`. Payment
   charges, email delivery, webhook processing, and message-queue
   producers are the common targets.
2. Sprinkle `#assertIdempotent { ... }` inside existing `@Test` methods
   for handlers whose returns reflect their side effects.
3. Add `assertIdempotentEffects` for handlers whose returns *don't*
   reflect their side effects (`HTTPStatus.ok`, `Void`, `Bool`).
4. Add the `@Idempotent` / `@ExternallyIdempotent(by:)` attributes when
   you want self-documenting contracts, or when you adopt SwiftProjectLint
   and want its rules to fire.

You don't have to do all four. The package is designed so each tier
delivers value on its own.

## Tier 1: `IdempotencyKey` for compile-time enforcement

The single most common idempotency-key bug is passing a per-invocation
generator (`UUID()`, `Date()`, `arc4random()`) where a stable identifier
is required. Each retry sees a new "identity," and the external service
treats every retry as a distinct request — defeating the key entirely.

`IdempotencyKey` is a struct with deliberately limited initialisers:

```swift
import SwiftIdempotency

func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) async throws { /* ... */ }
```

There is **no** `init()`, no `init(_ uuid: UUID)`, no
`ExpressibleByStringLiteral`. The only construction paths are:

- `init(fromEntity:)` — takes any `Identifiable` whose `id` is
  `CustomStringConvertible`. Use this when you have a stable entity
  (a webhook event, a database row, an upstream request).
- `init(fromAuditedString:)` — takes a string the caller has *audited*
  as stable. The label is deliberately explicit so reviewers can flag
  implausible audits (`UUID().uuidString`, `"\(Date())"`).

```swift
// ✅ Stable: webhook event id is constant across retried deliveries.
chargeCard(amount: 100, idempotencyKey: IdempotencyKey(fromEntity: webhookEvent))

// ✅ Stable but auditable: explicit label signals "I checked this".
chargeCard(amount: 100, idempotencyKey: IdempotencyKey(fromAuditedString: "stripe-charge-2026-q2"))

// ❌ Compile error: cannot convert UUID to IdempotencyKey.
chargeCard(amount: 100, idempotencyKey: UUID())

// ❌ Compile error: cannot convert String to IdempotencyKey.
chargeCard(amount: 100, idempotencyKey: "key-123")
```

`IdempotencyKey` conforms to `Hashable`, `Sendable`, `Codable`, and
`CustomStringConvertible`. It serialises as its raw string value — no
JSON wrapper.

### When the linter still helps

A determined caller can smuggle an unstable value in via
`IdempotencyKey(fromAuditedString: UUID().uuidString)`. SwiftProjectLint's
`missingIdempotencyKey` rule catches this specific pattern at the call
site. The type handles the common case; the linter handles the escape
hatch.

## Tier 2: Annotation attributes for the linter

Four attribute macros declare a function's effect:

| Attribute | Meaning |
|---|---|
| `@Idempotent` | Re-invoking with the same arguments produces the same observable result and no additional effects. |
| `@NonIdempotent` | Re-invoking produces additional observable effects (sending email, inserting rows, publishing events). |
| `@Observational` | Only side effects are observation primitives (logger calls, metrics, span creation) that are retry-safe by convention. |
| `@ExternallyIdempotent(by: "paramName")` | Idempotent *only* when routed through a caller-supplied dedup key, named by the parameter label. |

```swift
@Idempotent
func upsertUser(id: UserID, data: UserData) throws { /* ... */ }

@NonIdempotent
func sendWelcomeEmail(to user: User) async throws { /* ... */ }

@Observational
func logAudit(_ event: AuditEvent) { /* ... */ }

@ExternallyIdempotent(by: "idempotencyKey")
func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) async throws { /* ... */ }
```

These are equivalent to the doc-comment forms `/// @lint.effect idempotent`,
`/// @lint.effect non_idempotent`, etc. SwiftProjectLint's
`EffectAnnotationParser` reads both. Pick whichever fits your codebase
or mix the two — the linter treats them identically.

### Without the linter

The attributes carry no runtime semantics on their own. Without
SwiftProjectLint reading them, they're documentation. Adding them is
still safe (unread markers are silent) and they remain useful for human
readers, but the lint-time enforcement only fires when the linter is
in the loop.

### `@ExternallyIdempotent(by:)` constraints

The `by:` argument is the *external* parameter label as written in the
function signature. Dotted-path forms (`by: "envelope.messageId"`) are
rejected at macro-expansion time — point at a real top-level parameter
on the function. If you need to key off a nested field, factor your
business logic into a function that takes the primitive directly:

```swift
// ❌ Rejected at macro expansion.
@ExternallyIdempotent(by: "event.id")
func handle(event: WebhookEvent) async throws { /* ... */ }

// ✅ Take the primitive directly; unwrap at the framework boundary.
@ExternallyIdempotent(by: "messageId")
func handle(messageId: String, body: String) async throws { /* ... */ }
```

## Tier 3: Test scaffolding for return-equality checks

Two macros generate or assert idempotency at test time.

### `@IdempotencyTests` for zero-argument members

For zero-argument functions on a `@Suite`, attach `@IdempotencyTests` to
the type. The macro emits one `@Test` per `@Idempotent`-marked member:

```swift
@Suite
@IdempotencyTests
struct MaintenanceChecks {
    @Idempotent
    func currentSystemStatus() -> Int { 200 }

    @Idempotent
    func flushCaches() async throws { /* ... */ }
}

// Macro-generated, simplified:
// extension MaintenanceChecks {
//     @Test func testIdempotencyOfCurrentSystemStatus() async throws {
//         let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
//             currentSystemStatus()
//         }
//         #expect(first == second)
//     }
//     // ... one @Test per zero-arg @Idempotent member.
// }
```

The expansion is effect-aware: `try` and `await` appear only when the
target's signature requires them, so non-throwing targets don't produce
spurious "no calls to throwing functions occur within 'try' expression"
warnings.

**Limitation**: only zero-argument members get auto-generated tests.
Parameterised functions need `#assertIdempotent` instead.

### `#assertIdempotent` for arbitrary call sites

The freestanding expression macro asserts idempotency at one specific
call site. Two overloads (sync and async) coexist; Swift picks the
right one based on whether the closure body uses `await`:

```swift
// Sync — closure has no await, sync overload selected.
@Test func chargeIsIdempotent() throws {
    let event = StripeEvent(id: "evt_abc123")
    let result = try #assertIdempotent {
        try processPayment(for: event)
    }
    #expect(result.status == .succeeded)
}

// Async — closure has await, async overload selected.
@Test func webhookIsIdempotent() async throws {
    let payload = WebhookPayload(eventId: "evt_abc123", amount: 250)
    let result = try await #assertIdempotent {
        try await handleWebhook(payload: payload, store: store)
    }
    #expect(result.status == "succeeded")
}
```

Both overloads:

1. Invoke the closure twice.
2. Compare return values via `Equatable`.
3. Abort via `precondition` on mismatch.
4. Return the first invocation's value for further assertions.

### Comparing structured responses

`#assertIdempotent` compares via `Equatable`, so its sharpness depends on
the type's `==`. For primitives and synthesised-`Equatable` structs,
that's exactly right. For **raw response bytes** — `Data` buffers of
JSON, encoded protobufs — `Equatable` is on the byte sequence, and that
isn't guaranteed stable: `JSONEncoder` key ordering and most response
encoders are non-deterministic.

Decode before comparing:

```swift
@Test func webhookReplaySafe() async throws {
    try await app.test(.router) { client in
        let result = try await #assertIdempotent {
            try await client.execute(
                uri: "/webhook",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(data: requestBody)
            ) { response -> ChargeResult in
                try JSONDecoder().decode(
                    ChargeResult.self,
                    from: Data(buffer: response.body)
                )
            }
        }
        #expect(result.status == "succeeded")
    }
}
```

The closure returns the *decoded* `ChargeResult`. Its synthesised
`Equatable` compares field-by-field, which is stable across encoder
key-ordering choices.

### What return-equality cannot detect

`#assertIdempotent` compares return values. It does **not** observe
side effects that don't appear in the return type. A handler that
double-writes to Redis but returns `.ok` either way will silently pass:

```swift
// Non-idempotent: double-writes to Redis, returns .ok either way.
func startLiveActivity(req: Request, /* ... */) async throws -> HTTPStatus {
    _ = try await req.redis.hset("data", to: json, in: key).get()
    _ = try await req.redis.zadd(element, to: scheduleKey).get()
    return .ok
}

// "Passes": both calls returned .ok. Redis state is wrong. Assertion silent.
try await #assertIdempotent { try await startLiveActivity(/* ... */) }
```

For trivial-return handlers, reach for Tier 4 instead.

## Tier 4: Effect observation for trivial-return handlers

When the return value can't tell you whether a handler is idempotent,
watch what it *does*. Conform your test doubles to
`IdempotentEffectRecorder` and use `assertIdempotentEffects` to run
the body twice.

```swift
import SwiftIdempotency
import SwiftIdempotencyTestSupport
import Testing

final class MockCoinRepo: IdempotentEffectRecorder {
    private(set) var effectCount = 0
    private(set) var puts: [CoinEntry] = []

    func putItem(_ entry: CoinEntry) async throws {
        puts.append(entry)
        effectCount += 1
    }
}

@Test("addUser is idempotent when keyed on the request id")
func addUserIsIdempotent() async throws {
    let coinRepo = MockCoinRepo()
    let handler = UsersHandler(coinRepo: coinRepo)
    let request = UserRequest(id: "req-42", amount: 10)

    try await assertIdempotentEffects(recorders: [coinRepo]) {
        _ = try await handler.handleAddUser(entry: request)
    }
    // Passes iff the second invocation produced no new puts.
}
```

### Reads should NOT count

The point is to detect *observable-state-changing* retries. A handler
that reads a row twice is idempotent. A handler that writes twice is
not. Increment `effectCount` only on writes / sends / publishes, never
on reads.

### When to reach for Tier 4 vs Tier 3

| Your handler returns... | Use |
|---|---|
| A typed model with meaningful `Equatable` | `#assertIdempotent` |
| `Void` / `HTTPStatus.ok` / `Bool` / other trivial type | `assertIdempotentEffects` |
| A status *and* writes to a DB / sends a message | both |
| A non-`Equatable` reference type | `assertIdempotentEffects`, or project to a struct |

The two compose. Use both when the handler has a meaningful return
*and* observable side effects.

### Failure modes

```swift
// Default: aborts via Swift.preconditionFailure on detection.
// Matches #assertIdempotent's failure mode.
try await assertIdempotentEffects(recorders: [mockDB]) {
    try await handler.run()
}

// Swift Testing path: reports via Issue.record without aborting.
// Useful for failure-path tests inside withKnownIssue.
await withKnownIssue {
    await assertIdempotentEffects(
        recorders: [mockDB],
        failureMode: .issueRecord
    ) {
        await nonIdempotentHandler.run()
    }
}
```

### Richer snapshots via `Snapshot`

`IdempotentEffectRecorder` has an associated `Snapshot: Equatable` type
that defaults to `Int` (backed by `effectCount`). Override it with any
`Equatable` type — an ordered call log, a dictionary of per-operation
counters — to detect non-idempotency invisible to counts alone (e.g.
retries that undo-then-redo, leaving count unchanged but call order
diverged).

```swift
final class DetailedMock: IdempotentEffectRecorder {
    typealias Snapshot = [String]          // ordered call log

    private(set) var callLog: [String] = []
    var effectCount: Int { callLog.count }

    func snapshot() -> [String] { callLog }

    func putItem(_ id: String) { callLog.append("put(\(id))") }
    func deleteItem(_ id: String) { callLog.append("del(\(id))") }
}
```

The protocol lives in `SwiftIdempotency`, not `SwiftIdempotencyTestSupport`,
so production mocks (observability shims, retry instrumentation) can
conform without pulling in the test-support dependency. Only
`assertIdempotentEffects` itself lives in `SwiftIdempotencyTestSupport`,
because it imports `Testing` for the `.issueRecord` path.

## Integrating with Fluent ORM

Vapor's Fluent ORM has three rough edges; all have known workarounds.

### Header-sourced keys are the idiomatic path

Route through `init(fromAuditedString:)` with an `Idempotency-Key`
header, falling back to a natural business-key field when absent:

```swift
app.post("api", "acronym") { req async throws -> Acronym in
    let acronym = try req.content.decode(Acronym.self)
    let keyString = req.headers.first(name: "Idempotency-Key") ?? acronym.short
    let key = IdempotencyKey(fromAuditedString: keyString)
    return try await createAcronym(req: req, acronym: acronym, idempotencyKey: key)
}

@ExternallyIdempotent(by: "idempotencyKey")
func createAcronym(
    req: Request,
    acronym: Acronym,
    idempotencyKey: IdempotencyKey
) async throws -> Acronym {
    try await acronym.save(on: req.db)
    return acronym
}
```

Stripe-convention-aligned, integrates with `Request.headers` without
adapter code, and the fallback to a business key gives clients that
don't supply the header deterministic dedup via the adopter's own data.

Create handlers can't use `init(fromEntity:)` anyway: a Fluent Model
being created has no `id` until after save. `init(fromEntity:)` is a
post-save tool, not a create-handler tool.

### Post-save keys: `init(fromFluentModel:)`

For post-save handlers that want to key from the saved entity, depend
on the `SwiftIdempotencyFluent` product:

```swift
// Package.swift
.product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
.product(name: "SwiftIdempotencyFluent", package: "SwiftIdempotency"),
```

```swift
import SwiftIdempotency
import SwiftIdempotencyFluent

// Post-save:
let key = try IdempotencyKey(fromFluentModel: savedAcronym)
// → key.rawValue == savedAcronym.requireID().uuidString
```

The initializer throws `FluentError.idRequired` if the Model's `id` is
nil (pre-save) — the same error `model.requireID()` throws.

**Supported `IDValue` types**: any `CustomStringConvertible` — `UUID`,
`Int`, `String`, and typed wrappers around those. Models using
`@CompositeID` have a custom struct `IDValue` and are rejected at
compile time; route those through `init(fromAuditedString:)` on a
manually-composed string.

### `#assertIdempotent` on Model returns needs a projection

Fluent `Model` is `final class` without explicit `Equatable`
conformance. Handing a Model-returning closure to `#assertIdempotent`
produces a compile error. Use a dedicated `Equatable` struct:

```swift
struct AcronymProjection: Equatable {
    let id: UUID?
    let short: String
    let long: String
}

_ = try #assertIdempotent {
    let acronym = try await Acronym.find(id, on: db)!
    return AcronymProjection(id: acronym.id, short: acronym.short, long: acronym.long)
}
```

Tuples do **not** work here. Swift's tuple-`==` synthesis is not the
same as `Equatable` *protocol* conformance, and `#assertIdempotent`'s
generic `<Result: Equatable>` constraint rejects tuples at type-check
time. Only named types satisfy protocol constraints.

For create handlers, include the mutable `id: UUID?` in the projection:
a non-idempotent create produces distinct UUIDs across the two
invocations, the projections compare unequal, and the precondition
fires.

Worked migration in
[`docs/hellovapor-package-trial/`](docs/hellovapor-package-trial/) and
[`docs/luka-vapor-package-trial/`](docs/luka-vapor-package-trial/).

## Integrating with SwiftData

SwiftData is Apple's first-party persistence layer. Its `@Model` macro
emits `PersistentModel` conformance with an inherited `Identifiable`,
so `SwiftIdempotencyFluent` isn't needed. The integration turns on one
question: does your `@Model` expose a stable identifier named `id`,
or something else?

### Clean path: `id: UUID` or `id: String`

When the identifier is named `id`, `init(fromEntity:)` works directly.
Adding `@Attribute(.unique)` is recommended — it makes persistence the
final dedup gate, pairing naturally with the handler-layer key flow.

```swift
import SwiftData
import SwiftIdempotency

@Model
final class OfflineAlbum {
    @Attribute(.unique) var id: String
    var name: String
    var favorite: Bool

    init(id: String, name: String, favorite: Bool) {
        self.id = id; self.name = name; self.favorite = favorite
    }
}

let album = OfflineAlbum(id: "album-42", name: "Kind of Blue", favorite: true)
let key = IdempotencyKey(fromEntity: album)
// key.rawValue == "album-42"
```

### Business-named-UUID path

When the identifier is named something other than `id` —
`annotationId`, `uuid`, `pk`, domain-specific names — `init(fromEntity:)`
won't reach it. Swift's `Identifiable` synthesis requires a member
named `id` (or a `typealias ID = ...`); absent both, SwiftData falls
through to the synthesised `id: PersistentIdentifier`, which isn't
`CustomStringConvertible`.

Two workarounds:

**Option A — `fromAuditedString:` over the stringified UUID** (zero
boilerplate):

```swift
@Model
final class AnnotationNote {
    @Attribute(.unique) var annotationId: UUID
    var content: String
    // ... no id property
}

let key = IdempotencyKey(fromAuditedString: annotation.annotationId.uuidString)
```

**Option B — opt in via typealias + computed `id`** (three lines per
Model):

```swift
@Model
final class AnnotationNote: Identifiable {
    @Attribute(.unique) var annotationId: UUID
    var content: String

    typealias ID = UUID
    var id: UUID { annotationId }
}

let key = IdempotencyKey(fromEntity: annotation)
```

Pick based on how much per-Model boilerplate is acceptable.

### `#assertIdempotent` on SwiftData Model returns

Same as Fluent: `@Model` classes are non-`Equatable` reference types,
so project to a struct before returning from the closure. Tuples don't
work for the same reason they don't work on Fluent Models.

Worked examples in
[`docs/synthetic-swiftdata-package-trial/`](docs/synthetic-swiftdata-package-trial/)
and [`docs/vreader-package-trial/`](docs/vreader-package-trial/).

## Integrating with Vapor and Hummingbird

The main wrinkle is that route handlers in both frameworks are
idiomatically written as inline trailing closures. Attribute macros
attach to declarations, not expressions — see
[Migrating inline-closure handlers](#migrating-inline-closure-handlers)
for the extraction pattern.

### Vapor + Swift Testing

Import `VaporTesting`, not `XCTVapor`. `XCTVapor`'s `app.test(...)`
silently drops failures when invoked from a Swift Testing `@Suite`
(Vapor itself warns at runtime). `VaporTesting` is the Swift
Testing-native counterpart with the same API shape.

### Hummingbird

Standard `@Idempotent` / `@ExternallyIdempotent(by:)` annotations work
on extracted handler functions. The Hummingbird adopter trial under
`docs/hummingbird-examples/` covers the integration shape end-to-end.

## Integrating with AWS Lambda

`swift-aws-lambda-events` event types (`SQSEvent.Message`,
`SNSEvent.Record`, etc.) are `Decodable`-only. They expose no public
memberwise initialiser, so tests can't synthesise synthetic events
via struct initialisation.

Factor your per-event business logic into functions that take the
specific primitive fields they need (`messageId: String, body: String,
...`), then unwrap the event envelope at the framework boundary:

```swift
// At the framework boundary — unwrap the envelope.
@main
struct MyHandler: SimpleLambdaHandler {
    func handle(_ event: SQSEvent, context: LambdaContext) async throws {
        for record in event.records {
            try await processMessage(
                messageId: record.messageId,
                body: record.body
            )
        }
    }
}

// Business logic — takes primitives, testable in isolation.
@ExternallyIdempotent(by: "messageId")
func processMessage(messageId: String, body: String) async throws {
    let key = IdempotencyKey(fromAuditedString: messageId)
    // ...
}
```

That shape also lets `@ExternallyIdempotent(by: "messageId")` point at
a real top-level parameter — the dotted-path form
`by: "envelope.messageId"` is rejected at macro expansion.

Every Lambda invocation runs in an objectively replayable retry context
by the runtime's at-least-once contract, so
`/// @lint.context replayable` on the handler entry point is unambiguous
without judgement calls about what the context should be.

## Migrating inline-closure handlers

The attribute macros attach to **declarations** (`func`, `var`,
`struct`). They do not attach to expressions like inline trailing
closures, which is the idiomatic route-registration shape in Vapor and
Hummingbird:

```swift
// ❌ Attribute macros can't attach to an inline closure.
app.post("charge") { req async throws -> Response in
    let body = try req.content.decode(ChargeRequest.self)
    // handler body
}
```

To add `@ExternallyIdempotent(by:)` et al. to a handler in this shape,
extract the body into a named function:

```swift
// ✅ Named decl — attribute macros attach cleanly.
@ExternallyIdempotent(by: "idempotencyKey")
func charge(
    req: Request,
    body: ChargeRequest,
    idempotencyKey: IdempotencyKey
) async throws -> Response {
    // handler body
}

// Registration becomes a thin decode-and-delegate.
app.post("charge") { req async throws -> Response in
    let body = try req.content.decode(ChargeRequest.self)
    return try await charge(
        req: req, body: body, idempotencyKey: body.idempotencyKey
    )
}
```

Mechanical but invasive on codebases that use inline closures heavily —
expect one new file per handler and a two-to-three-line registration
delegate replacing each body. Worked example with full diff:
[`docs/luka-vapor-package-trial/`](docs/luka-vapor-package-trial/).

The same-named doc-comment form
(`/// @lint.effect externally_idempotent(by: "idempotencyKey")`) has
the same constraint: doc comments attach to declarations, not to
closure expressions. This is a Swift-language constraint, not a
macro-specific one.

> **Context annotations are different.** `/// @lint.context replayable`
> on an *enclosing* function (e.g., `func routes(_ app:)`) walks into
> inline trailing closures registered inside it — so the retry-context
> linter rule reaches closure bodies without this refactor. Only the
> per-handler effect declarations require extraction.

## Coordination with SwiftProjectLint

If your project already uses SwiftProjectLint, adding this package is
additive:

- **Annotation forms coexist.** Existing `/// @lint.effect idempotent`
  doc comments keep working. Attribute form can be added alongside or
  used instead.
- **Linter reads both.** The linter's `EffectAnnotationParser` scans
  attribute lists for `@Idempotent` et al., same as it scans doc
  comments. Both signals feed the same rule pipeline.
- **Conflict semantics.** If a declaration carries both forms and they
  disagree (e.g. `/// @lint.effect idempotent` + `@NonIdempotent`), the
  linter withdraws the entry — matching the cross-file collision
  policy.
- **The tiers layer.** Once a callee takes `IdempotencyKey` directly,
  the compile-time type check rejects `UUID()` / `Date()` at call sites
  *before* the linter's `MissingIdempotencyKey` rule would fire. That
  rule's value concentrates on un-migrated call sites where the key is
  still typed as `String`.

If your project doesn't use SwiftProjectLint, this package is still
useful on its own — `IdempotencyKey` and the test scaffolding deliver
value independent of static analysis.

## Design boundaries

**What this package does:**

- Compile-time type enforcement via `IdempotencyKey`
- Recognisable attribute names for hand-written and linter-consumed
  annotations
- Test scaffolding via `@IdempotencyTests` (zero-arg auto-expansion),
  `#assertIdempotent` (sync + async overloads), and
  `assertIdempotentEffects` + `IdempotentEffectRecorder` for effect
  observation

**What this package does NOT do:**

- **Production-runtime instrumentation.** Macros cannot inject into
  every call site silently. Runtime safety is covered by compile-time
  (types), test-time (generated / explicit tests), and lint-time
  (SwiftProjectLint rules) — not production AOP.
- **Auto-generated mocks or dependency injection.** The test
  `@IdempotencyTests` generates for a zero-arg function calls it
  literally twice. If your function touches the filesystem or a real
  database, you're responsible for test isolation.
- **Parameterised `@IdempotencyTests` expansion.** Only zero-argument
  `@Idempotent`-marked members get auto-generated tests. Parameterised
  functions use `#assertIdempotent` at test sites, or wait for a future
  slice that introduces an `IdempotencyTestArgs` protocol.
- **Dynamic equivalence checking by default.** `#assertIdempotent`'s
  built-in semantics are return-equality. Effect observation is opt-in
  via `IdempotentEffectRecorder` — handlers without instrumented mocks
  still pass `#assertIdempotent` even when their side effects diverge.
