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

#### What `#assertIdempotent` cannot detect

`#assertIdempotent` compares return values. It does **not** observe
side effects that don't appear in the return type. A handler that
mutates a database, emits a notification, or publishes to a queue —
and returns `HTTPStatus.ok` (or `Void`, or `Bool`, or `.created`)
regardless — will silently pass `#assertIdempotent` even when it's
demonstrably non-idempotent at the observable-state level.

```swift
// Non-idempotent: double-writes to Redis, returns .ok either way.
func startLiveActivity(req: Request, /* ... */) async throws -> HTTPStatus {
    _ = try await req.redis.hset("data", to: json, in: key).get()
    _ = try await req.redis.zadd(element, to: scheduleKey).get()
    return .ok
}

// #assertIdempotent "passes" — both calls returned .ok.
// Redis state now has duplicate entries. Assertion is silent.
try await #assertIdempotent { try await startLiveActivity(...) }
```

The macro is sharpest on handlers whose return value reflects the
side effect — a `create → Entity` handler, an `increment → Int`, a
`fetch → [Row]`. On handlers with trivial returns, pair the macro
with explicit state inspection:

```swift
@Test func startActivityIsIdempotent() async throws {
    let redis = try await makeEphemeralRedis()
    let key = IdempotencyKey(fromAuditedString: "test-key-001")
    let body = StartLiveActivityRequest(/* ... */, idempotencyKey: key)

    _ = try await #assertIdempotent {
        try await startLiveActivity(req: req, body: body, idempotencyKey: key)
    }
    let sessionCount = try await redis.hlen("data").get()
    #expect(sessionCount == 1)  // catches what Option C cannot
}
```

Treat return-equality as a **necessary but not sufficient** check
on any handler whose return type doesn't reflect the side effect.
A future release may add a dependency-injected-effect variant that
observes state mutations directly; until then, handler-return shape
determines how sharp `#assertIdempotent` can be. SwiftProjectLint's
`nonIdempotentInRetryContext` rule fills part of the gap statically
— it flags handlers that call known-non-idempotent operations
inside a `@lint.context replayable` or `@ExternallyIdempotent(by:)`
body — but static analysis has its own shape of limitation. Neither
layer is complete on its own.

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
        ]
    ),
]
```

Swift 5.10+; requires Swift Testing for `@Test`-based peer expansion.

The package also exposes a `SwiftIdempotencyTestSupport` library. It's
currently a placeholder — `#assertIdempotent`'s runtime helpers live
in the main `SwiftIdempotency` library, so test targets only need the
one product shown above. The placeholder target exists so future
test-only helpers can ship without breaking adopter Package.swift
files that already declare the dependency; adopters adopting today
can omit it.

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

## Migrating inline-closure handlers

The attribute macros (`@Idempotent`, `@NonIdempotent`, `@Observational`,
`@ExternallyIdempotent`) attach to **declarations** — `func`, `var`,
`struct`, etc. They do not attach to expressions like inline trailing
closures, which is the idiomatic route-registration shape in both
Vapor and Hummingbird:

```swift
// ❌ Attribute macros can't attach to an inline closure.
app.post("charge") { req async throws -> Response in
    let body = try req.content.decode(ChargeRequest.self)
    // handler body
}
```

To add `@ExternallyIdempotent(by:)` et al. to a handler in this shape,
extract the body into a named function and call it from the closure:

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
    return try await charge(req: req, body: body, idempotencyKey: body.idempotencyKey)
}
```

The refactor is mechanical but invasive on codebases that use inline
closures heavily — expect one new file per handler and a two-to-three-
line registration delegate replacing each body. Worked example with
full diff: [luka-vapor package-integration trial](https://github.com/Joseph-Cursio/swiftIdempotency/tree/main/docs/luka-vapor-package-trial).

The same-named doc-comment form (`/// @lint.effect externally_idempotent(by: "idempotencyKey")`)
has the identical constraint: doc comments attach to declarations,
not to closure expressions. This is a Swift-attribute-and-doc-comment
constraint, not a macro-specific one.

> **Context annotations are different.** `/// @lint.context replayable`
> on an **enclosing** function (e.g., `func routes(_ app:)`) walks into
> inline trailing closures registered inside it — so the retry-context
> linter rule reaches closure bodies without this refactor. Only the
> per-handler effect declarations (`@ExternallyIdempotent(by:)` etc.)
> require the extraction.

## Using with Fluent ORM

Vapor's Fluent ORM is the biggest persistence library in the Vapor
ecosystem. Integrating SwiftIdempotency with Fluent adopters hits
three rough edges worth calling out up front — all have known
workarounds, and the idiomatic integration path sidesteps the first
two entirely.

### Header-sourced keys are the idiomatic path

Route through `init(fromAuditedString:)` with an HTTP header, falling
back to a natural business-key field when the header is absent:

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
adapter code, and the fallback to the business key gives clients that
don't supply the header deterministic dedup via the adopter's own
data.

Create handlers have a bootstrap problem that rules out
`init(fromEntity:)` anyway — a Fluent Model being created has no
`id` until after save, so the entity can't be the source of its own
pre-save dedup key. `init(fromEntity:)` is a post-save-read-or-lookup
tool, not a create-handler tool.

### `init(fromEntity:)` needs an adapter for Fluent Models

Post-save handlers that want to key from the saved entity hit two
compile errors. Fluent's `Model` does not inherit `Identifiable`
(despite exposing `@ID var id: UUID?`), and the constructor's
`E.ID: CustomStringConvertible` constraint rejects Optional types.
An adopter-side adapter bridges both:

```swift
struct IdentifiableAcronym: Identifiable {
    let acronym: Acronym
    var id: UUID { acronym.id! } // safe only post-save
    init(_ acronym: Acronym) { self.acronym = acronym }
}

// Post-save usage:
let key = IdempotencyKey(fromEntity: IdentifiableAcronym(savedAcronym))
```

One adapter per Model type the adopter keys on. Force-unwrapping
`id` is safe inside this adapter because construction is post-save —
the invariant the handler controls. Third-party Model types defined
outside the adopter's module can't always be retroactively
conformed this way; for those, fall back to
`init(fromAuditedString:)` on a stable business key.

### `#assertIdempotent` on Model returns needs a tuple

Fluent `Model` is `final class` without explicit `Equatable`
conformance. `#assertIdempotent` requires an `Equatable` return —
handing a Model-returning closure directly produces a compile
error. Return a value-tuple of the Model's fields instead (tuples
of Equatables are synthesized-Equatable):

```swift
// ❌ Acronym is a final class; Equatable not synthesized.
_ = try #assertIdempotent {
    try await Acronym.find(id, on: db)
}

// ✅ Tuple of Equatable value fields.
_ = try #assertIdempotent {
    let a = try await Acronym.find(id, on: db)!
    return (a.id, a.short, a.long)
}
```

Size the tuple to whichever fields matter for the operation being
asserted. For create handlers, include the mutable `id: UUID?`:
a non-idempotent create produces distinct UUIDs across the two
invocations, the tuples compare unequal, and the precondition fires.

### Full worked migration

These patterns are drawn from a fully-compiling adopter trial with
passing tests — see
[`docs/hellovapor-package-trial/`](docs/hellovapor-package-trial/)
for the complete migration diff and the findings that motivated each
pattern. The earlier
[`docs/luka-vapor-package-trial/`](docs/luka-vapor-package-trial/)
covers the first adopter-integration round (non-Fluent Vapor, same
inline-closure refactor shape).

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
