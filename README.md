# SwiftIdempotency

Compile-time type enforcement and test scaffolding for idempotent operations
in Swift. Complements the static analysis rules in
[SwiftProjectLint](https://github.com/Joseph-Cursio/SwiftProjectLint) — this
package raises the ceiling on what can be enforced without running the
code.

## What it provides

Three tiers of safety. Strongest first.

### 1. Compile-time enforcement via `IdempotencyKey`

```swift
import SwiftIdempotency

func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) async throws { ... }

// ❌ Compile error: cannot convert UUID to IdempotencyKey
chargeCard(amount: 100, idempotencyKey: UUID())

// ✅ Works: key derived from a stable webhook event id
chargeCard(amount: 100, idempotencyKey: IdempotencyKey(fromEntity: webhookEvent))

// ✅ Works but auditable: explicit label signals "I checked this"
chargeCard(amount: 100, idempotencyKey: IdempotencyKey(fromAuditedString: "stripe-charge-2026-q2"))
```

The type has **no `init()`**, no `init(_ uuid: UUID)`, no
`ExpressibleByStringLiteral`. The only construction paths are
`init(from:)` (requires `Identifiable`) and `init(fromAuditedString:)`
(requires the caller to explicitly audit a string as stable across
retries). Using `UUID()` or `Date()` as a key becomes a type error — not
a runtime mistake, not a lint finding, a compile-time failure.

### 2. Annotation attributes the linter reads

```swift
import SwiftIdempotency

@Idempotent
func upsertUser(id: UserID, data: UserData) throws { ... }

@NonIdempotent
func sendWelcomeEmail(to user: User) async throws { ... }

@Observational
func logAudit(_ event: AuditEvent) { ... }

@ExternallyIdempotent(by: "idempotencyKey")
func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) async throws { ... }
```

Equivalent to the doc-comment form `/// @lint.effect idempotent` etc.
SwiftProjectLint's idempotency rules recognise both forms — pick the
idiom that fits your codebase, or mix and match. Linter's
`idempotencyViolation` and `nonIdempotentInRetryContext` rules fire
identically for either form.

### 3. Test scaffolding via `@IdempotencyTests` and `#assertIdempotent`

For **zero-argument functions**, attach `@IdempotencyTests` to the
enclosing `@Suite` type. For each `@Idempotent`-marked zero-argument
member, the macro emits one `@Test` method in a generated extension:

```swift
@Suite
@IdempotencyTests
struct MaintenanceChecks {
    @Idempotent
    func currentSystemStatus() -> Int { 200 }

    @Idempotent
    func flushCaches() async throws { ... }
}

// Macro-generated:
// extension MaintenanceChecks {
//     @Test func testIdempotencyOfCurrentSystemStatus() async throws {
//         let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
//             currentSystemStatus()
//         }
//         #expect(first == second)
//     }
//     @Test func testIdempotencyOfFlushCaches() async throws {
//         let (first, second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
//             try await flushCaches()
//         }
//         #expect(first == second)
//     }
// }
```

The expansion is effect-aware — `try` and `await` appear only when the
target's signature requires them, so non-throwing targets don't
produce spurious `"no calls to throwing functions occur within 'try'
expression"` warnings.

For parameterised functions, use the freestanding `#assertIdempotent`
expression macro at a specific call site. The macro has sync and async
overloads; Swift's overload resolution picks the right one based on the
closure's effects, so callers just write what their closure needs:

```swift
// Sync — no `await` in the body, compiles without it at the call site.
@Test func chargeIsIdempotent() throws {
    let event = StripeEvent(id: "evt_abc123")
    let result = try #assertIdempotent {
        try processPayment(for: event)
    }
    #expect(result.status == .succeeded)
}

// Async — `await` in the body forces the async overload.
@Test func webhookIsIdempotent() async throws {
    let payload = WebhookPayload(eventId: "evt_abc123", amount: 250)
    let result = try await #assertIdempotent {
        try await handleWebhook(payload: payload, store: store)
    }
    #expect(result.status == "succeeded")
}
```

Both overloads invoke the closure twice, compare return values via
`Equatable`, abort via `precondition` on mismatch, and return the first
result.

#### Comparing structured responses

`#assertIdempotent` compares return values via `Equatable`, so its
answer is only as sharp as the type's `==`. For primitives and typed
models with synthesised `Equatable`, that's exactly right. For **raw
response bytes** — `Data` buffers of JSON, encoded protobufs, etc. —
`Equatable` is on the byte sequence, and that's not guaranteed stable:
`JSONEncoder` key ordering and most framework response encoders are
non-deterministic, so two semantically-identical responses can diverge
on the wire.

**Decode before comparing:**

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

The closure returns the *decoded* `ChargeResult`, whose synthesised
`Equatable` compares field-by-field. The assertion is stable regardless
of the encoder's key ordering. The same caveat and fix apply to the
`@IdempotencyTests` auto-generated tests — prefer a typed return over
raw bytes in the target function.

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/Joseph-Cursio/SwiftIdempotency.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
        ]
    ),
    .testTarget(
        name: "YourAppTests",
        dependencies: [
            .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            .product(name: "SwiftIdempotencyTestSupport", package: "SwiftIdempotency"),
        ]
    ),
]
```

Swift 5.10+; requires Swift Testing for `@Test`-based peer expansion.

**Vapor adopters using Swift Testing**: import `VaporTesting` rather
than `XCTVapor`. XCTVapor's `app.test(...)` silently drops failures
when invoked from a Swift Testing `@Suite` — Vapor itself warns at
runtime if you try — and `VaporTesting` is the Swift Testing-native
counterpart exposing the same API shape.

**AWS Lambda adopters**: `swift-aws-lambda-events` event types
(`SQSEvent.Message`, `SNSEvent.Record`, etc.) are `Decodable`-only —
they expose no public memberwise initialiser, so tests can't
synthesise synthetic events via struct initialisation. Factor your
per-event business logic into functions that take the specific
primitive fields they need (`messageId: String, body: String, ...`)
and unwrap the event envelope at the framework boundary. That shape
also lets `@ExternallyIdempotent(by: "messageId")` point at a real
parameter label — the dotted-path form `by: "message.messageId"` is
rejected at macro-expansion time.

## Design boundaries

**What this package does:**
- Compile-time type enforcement via `IdempotencyKey`
- Recognisable attribute names for hand-written and linter-consumed
  annotations
- Test-time scaffolding via `@IdempotencyTests` extension-macro
  expansion (zero-arg `@Idempotent`-marked members) and
  `#assertIdempotent` expression macro (sync + async overloads)

**What this package does NOT do:**
- **Production-runtime instrumentation.** Macros cannot inject into every
  call site silently. Runtime safety is covered by compile-time (types),
  test-time (generated / explicit tests), and lint-time (SwiftProjectLint
  rules) — not production AOP.
- **Auto-generated mocks or dependency injection.** The test that
  `@IdempotencyTests` generates for a zero-arg function calls it
  literally twice. If your function touches the filesystem or a real
  database, you're responsible for test isolation.
- **Parameterised `@IdempotencyTests` expansion.** Only zero-argument
  `@Idempotent`-marked members get auto-generated tests. Parameterised
  functions can either use `#assertIdempotent` at test sites, or wait
  for a future slice that introduces an `IdempotencyTestArgs` protocol.
- **Dynamic observable-equivalence checking.** The current
  implementation uses Option C semantics — same return value + no throw
  on second call. It doesn't capture side effects via mocks. Genuinely
  non-idempotent functions whose side effects are invisible to the
  return value will not be caught by the auto-generated test alone.

## Using without SwiftProjectLint

The package has standalone value — two of the three tiers work independently, no linter required.

**Standalone — full value:**

- **`IdempotencyKey`** — compile-time type enforcement. `UUID()` / `Date()` at call sites become type errors, rejected by the compiler before any external tool runs.
- **`#assertIdempotent` and `@IdempotencyTests`** — compile-time macro expansion into ordinary Swift Testing calls. Tests run at `swift test` time, no external tooling in the loop.

**Needs the linter to pay off:**

- **`@Idempotent` / `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent(by:)`** — marker attributes that carry no runtime semantics on their own. Without a linter reading them, they're documentation; a `/// @lint.effect idempotent` doc comment is informationally equivalent. Still safe to add (unread markers are silent), just not load-bearing without the tool.

**Recommended standalone adoption shape:**

1. Migrate one or two high-value call sites to take `IdempotencyKey` instead of `String` or `UUID`. Payment charges, email delivery, webhook processing, and message-queue producers are the common targets.
2. Sprinkle `#assertIdempotent { ... }` inside existing `@Test` methods where handlers should be retry-safe. The macro is effect-polymorphic — sync, async, throwing, non-throwing — and picks the right overload based on the closure's effects.
3. Skip the attribute macros until you either add SwiftProjectLint or want self-documenting contracts for future tooling.

What you give up without the linter: no verification that a function claiming `@Idempotent` is actually idempotent in its body; no retry-context reasoning; no framework-primitive recognition (Fluent ORM verbs, routing DSL, HTTP primitives). Those are linter-side guarantees. The package and the linter compose additively — same annotations, both read them — but the standalone proposition stands on its own two tiers.

## Coordination with SwiftProjectLint

If your project already uses SwiftProjectLint, adding this package is
additive:

- **Annotation forms coexist.** Existing `/// @lint.effect idempotent`
  doc comments keep working. Attribute form can be added alongside or
  used instead.
- **Linter reads both.** The linter's `EffectAnnotationParser` scans
  attribute lists for `@Idempotent` et al., same as it scans doc
  comments. The two signals feed the same rule pipeline.
- **Conflict semantics.** If the same declaration has both forms and
  they disagree (e.g. `/// @lint.effect idempotent` + `@NonIdempotent`),
  the linter withdraws the entry (collision policy) — matching how two
  conflicting `@lint.effect` declarations across files are handled.
- **The tiers layer, they don't overlap wastefully.** Once a callee
  takes `IdempotencyKey` directly, the compile-time type check rejects
  `UUID()` / `Date()` at call sites *before* the linter's
  `MissingIdempotencyKey` rule would have flagged them. That rule's
  value concentrates on un-migrated call sites where the key is still
  typed as `String`. Both tiers carry their weight: the type catches
  what it can earliest; the linter catches the string-typed remainder.

If your project doesn't use SwiftProjectLint yet, this package is still
useful on its own — `IdempotencyKey` and the generated tests provide
value independent of static analysis.

## Status

Early release. Annotation attributes (`@Idempotent`, `@NonIdempotent`,
`@Observational`, `@ExternallyIdempotent`), `IdempotencyKey`, zero-arg
`@IdempotencyTests` extension expansion, and `#assertIdempotent` (sync +
async) are implemented and tested. Deferred for future work:

- Parameterised `@IdempotencyTests` expansion — today only zero-arg
  `@Idempotent`-marked members get auto-generated tests; extending to
  parameterised members needs an `IdempotencyTestArgs` protocol design
  so the macro has a stable way to synthesise arguments
- Option A / B observable-equivalence (dependency-injected mocks)
- Framework-specific integrations (Vapor, Hummingbird, SwiftNIO)

See the design document in
[swiftIdempotency/docs](https://github.com/Joseph-Cursio/swiftIdempotency/tree/main/docs)
for the full roadmap and the
[claude_phase_5_macros_plan.md](https://github.com/Joseph-Cursio/swiftIdempotency/blob/main/docs/claude_phase_5_macros_plan.md)
for this package's specific scope.

## License

Apache License 2.0. See [LICENSE](LICENSE).
