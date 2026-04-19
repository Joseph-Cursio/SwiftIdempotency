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

### 3. Test scaffolding via `@Idempotent` and `#assertIdempotent`

For **zero-argument functions**, the `@Idempotent` attribute also
generates a companion Swift Testing test:

```swift
@Idempotent
func flushCaches() async throws { ... }

// Macro-generated peer:
// @Test func testIdempotencyOfFlushCaches() async throws {
//     try await flushCaches()
//     try await flushCaches()
// }
```

For parameterised functions, use the freestanding `#assertIdempotent`
expression macro at a specific call site:

```swift
@Test func chargeIsIdempotent() throws {
    let event = StripeEvent(id: "evt_abc123")
    let result = try #assertIdempotent {
        try processPayment(for: event)
    }
    #expect(result.status == .succeeded)
}
```

The macro expands to a call to a runtime helper that invokes the closure
twice, asserts identical return values via `precondition`, and returns
the first result. If the closure isn't idempotent, the second
invocation's result differs and the test fails.

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

## Design boundaries

**What this package does:**
- Compile-time type enforcement via `IdempotencyKey`
- Recognisable attribute names for hand-written and linter-consumed
  annotations
- Test-time scaffolding via `@Idempotent` peer-macro expansion (zero-arg
  functions) and `#assertIdempotent` expression macro

**What this package does NOT do:**
- **Production-runtime instrumentation.** Macros cannot inject into every
  call site silently. Runtime safety is covered by compile-time (types),
  test-time (generated / explicit tests), and lint-time (SwiftProjectLint
  rules) — not production AOP.
- **Auto-generated mocks or dependency injection.** The
  `@Idempotent`-generated test for a zero-arg function calls it literally
  twice. If your function touches the filesystem or a real database,
  you're responsible for test isolation.
- **Parameterised `@Idempotent` expansion.** Only zero-argument functions
  get auto-generated tests. Parameterised functions can either use
  `#assertIdempotent` at test sites, or wait for a future slice that
  introduces an `IdempotencyTestArgs` protocol.
- **Dynamic observable-equivalence checking.** The current
  implementation uses Option C semantics — same return value + no throw
  on second call. It doesn't capture side effects via mocks. Genuinely
  non-idempotent functions whose side effects are invisible to the
  return value will not be caught by the auto-generated test alone.

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

If your project doesn't use SwiftProjectLint yet, this package is still
useful on its own — `IdempotencyKey` and the generated tests provide
value independent of static analysis.

## Status

Early release. Annotation attributes, `IdempotencyKey`, zero-arg
`@Idempotent` expansion, and `#assertIdempotent` are implemented and
tested. Deferred for future work:

- Parameterised `@Idempotent` expansion (needs `IdempotencyTestArgs`
  protocol design)
- Option A / B observable-equivalence (dependency-injected mocks)
- Framework-specific integrations (Vapor, Hummingbird, SwiftNIO)

See the design document in
[swiftIdempotency/docs](https://github.com/Joseph-Cursio/swiftIdempotency/tree/main/docs)
for the full roadmap and the
[claude_phase_5_macros_plan.md](https://github.com/Joseph-Cursio/swiftIdempotency/blob/main/docs/claude_phase_5_macros_plan.md)
for this package's specific scope.

## License

TBD — will match `SwiftProjectLint`'s license.
