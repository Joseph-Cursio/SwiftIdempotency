# SwiftIdempotency API Reference

Symbol-by-symbol reference for the public API. Organised by library
product. For task-oriented guidance see [USER_GUIDE.md](USER_GUIDE.md);
for a worked walkthrough see [TUTORIAL.md](TUTORIAL.md).

## Contents

- [Library products](#library-products)
- [Effect lattice](#effect-lattice)
- [Annotation grammar](#annotation-grammar)
- [Context annotations](#context-annotations)
- [Idempotency keys as a first-class concept](#idempotency-keys-as-a-first-class-concept)
- [Effect escaping analysis](#effect-escaping-analysis)
- [Retry pattern detection](#retry-pattern-detection)
- [Swift concurrency interactions](#swift-concurrency-interactions)
- [Macro-based test generation: design rationale](#macro-based-test-generation-design-rationale)
- [Protocol-based type safety: design alternatives](#protocol-based-type-safety-design-alternatives)
- [Integration with SwiftProjectLint](#integration-with-swiftprojectlint)
- [Edge cases and implementation notes](#edge-cases-and-implementation-notes)
- [`SwiftIdempotency`](#swiftidempotency)
  - [`IdempotencyKey`](#idempotencykey)
  - [`@Idempotent`](#idempotent)
  - [`@NonIdempotent`](#nonidempotent)
  - [`@Observational`](#observational)
  - [`@ExternallyIdempotent(by:)`](#externallyidempotentby)
  - [`@IdempotencyTests`](#idempotencytests)
  - [`#assertIdempotent`](#assertidempotent)
  - [`IdempotentEffectRecorder`](#idempotenteffectrecorder)
  - [`IdempotencyFailureMode`](#idempotencyfailuremode)
- [`SwiftIdempotencyTestSupport`](#swiftidempotencytestsupport)
  - [`assertIdempotentEffects(recorders:failureMode:body:)`](#assertidempotenteffectsrecordersfailuremodebody)
- [`SwiftIdempotencyFluent`](#swiftidempotencyfluent)
  - [`IdempotencyKey.init(fromFluentModel:)`](#idempotencykeyinitfromfluentmodel)
- [Compiler plugin](#compiler-plugin)
- [Underscored helpers](#underscored-helpers)
- [Platform and tooling requirements](#platform-and-tooling-requirements)
- [Deferred and not-shipped features](#deferred-and-not-shipped-features)
- [Q&A: addressing common critiques](#qa-addressing-common-critiques)
- [Related work](#related-work)
- [What's novel here](#whats-novel-here)

## Library products

| Product | What it provides | When to depend on it |
|---|---|---|
| `SwiftIdempotency` | `IdempotencyKey`, all attribute and freestanding macros, `IdempotentEffectRecorder` protocol, runtime helpers backing `#assertIdempotent` | Always — main library. |
| `SwiftIdempotencyTestSupport` | `assertIdempotentEffects(...)` | Test targets that use the effect-observation helper. |
| `SwiftIdempotencyFluent` | `IdempotencyKey.init(fromFluentModel:)` | Adopters using Vapor's Fluent ORM. Pulls in `vapor/fluent-kit`. |
| `SwiftIdempotencyPropertyBased` (v0.4.0) | `assertIdempotentProperty(over:)` (value-level), `assertIdempotentEffectsProperty(over:makeRun:)` (action-sequence, effect-level) | Test targets that want **generated-input, shrinking** retry-idempotence checks (incl. parameterised functions). Pulls in `swift-property-based`. |

The compiler plugin target `SwiftIdempotencyMacros` is loaded
automatically by the Swift compiler when expanding macros — adopters
do not import it.

---

## Effect lattice

The package's attribute macros are markers that participate in a
formalized effect lattice. The lattice is the conceptual framework
that governs how effects compose and conflict; the macros declare a
function's position in it. Composition and conflict-detection rules
are enforced by [SwiftProjectLint](https://github.com/Joseph-Cursio/SwiftProjectLint)
when the linter is in the loop. Without the linter, the lattice still
informs how human reviewers should reason about the markers.

### The lattice

```
pure < { idempotent, observational } < { transactional_idempotent, externallyIdempotent } < non_idempotent
                                                                                      unknown (incomparable)
```

`unknown` is incomparable to `non_idempotent`; in strict mode it is
treated conservatively as `non_idempotent`. `idempotent` and
`observational` sit at the same tier — both are *intrinsically*
retry-safe without an external mechanism, but they describe different
effect shapes. `transactional_idempotent` and `externallyIdempotent`
sit at the next tier up — both are *conditionally* idempotent,
depending on an external mechanism (a transaction boundary or a
deduplication key respectively). Neither is strictly stronger than
the other at its tier; they address different classes of effect.

### Tier descriptions

| Tier | Macro on this package | Meaning |
|---|---|---|
| `pure` | (none — purity is not modelled here) | No side effects; same inputs always produce the same outputs. |
| `idempotent` | `@Idempotent` | Re-invocation produces no additional observable effect on external state. |
| `observational` | `@Observational` | Only side effects are append-only writes to observation sinks (loggers, metrics, tracing spans). Duplicate writes on retry are a feature, not a bug. |
| `transactional_idempotent` | *not exposed as a macro; doc-comment-only via `/// @lint.effect transactional_idempotent`* | Side effects are individually non-idempotent but commit atomically — typically inside a database transaction. |
| `externallyIdempotent` | `@ExternallyIdempotent(by:)` | Idempotent only when routed through a caller-supplied dedup key. |
| `non_idempotent` | `@NonIdempotent` | Re-invocation produces additional observable effects. |
| `unknown` | (none — emerges from inference) | The linter could not determine an effect (e.g., calls into an un-annotated third-party API). |

The package ships macro attributes for five of the seven tiers
(`idempotent`, `observational`, `externallyIdempotent`,
`non_idempotent`, plus the call-graph-only `unknown` and `pure` tiers
that need no marker). `transactional_idempotent` is intentionally
left at the doc-comment level — it requires a transaction boundary
that the macro can't verify, and the doc-comment form already carries
the necessary `@lint.txn_boundary` companion annotation.

#### Why `observational` exists separately from `idempotent`

`Logger.info`, `metrics.increment`, and span emission *do* have
observable effects (a log line exists; a counter increments) but
duplicates are not a correctness violation. Without a separate tier,
these calls would have to be misclassified as `idempotent`
(overstated — the log-line count changes on repetition) or
`non_idempotent` (which would flood any `@lint.context replayable`
handler with noise).

A `@lint.context replayable` body may call `observational` callees
freely; composing `observational` with `idempotent` callees produces
`idempotent` (the broader claim subsumes observational).

#### Why `externallyIdempotent` exists separately from `idempotent`

`externallyIdempotent` represents operations that are made safe to
retry via an external mechanism (idempotency keys, deduplication
tables) rather than intrinsic function-body properties. Tagging a
Stripe charge or an SNS publish as plain `idempotent` would be
misleading — the function body itself is not idempotent; the
deduplication is happening at the provider. The separate tier makes
the dependence on the external mechanism explicit and lets the
linter verify the key is being routed correctly.

### Composition rules

A function's inferred effect is computed from the effects of its
callees:

| Callees include | Caller's inferred effect |
|---|---|
| pure only | pure |
| idempotent only | idempotent |
| observational only | observational |
| observational + pure | observational |
| observational + idempotent | idempotent (broader claim subsumes observational) |
| any non_idempotent (outside a transaction) | non_idempotent |
| multiple non_idempotent inside a single transaction | transactional_idempotent |
| any externally_idempotent | externally_idempotent (if sole source) or non_idempotent (if mixed outside a txn) |
| any unknown | unknown (warn; treat as non_idempotent in strict mode) |
| idempotent + unknown | unknown |
| observational + unknown | unknown |

### Conflict detection

When a function carries a declared annotation but its body's inferred
effect doesn't match, the linter reports a conflict:

| Declared | Inferred | Outcome |
|---|---|---|
| `idempotent` | `idempotent` | ✅ OK |
| `idempotent` | `observational` | ⚠️ Warning — simpler annotation applies |
| `idempotent` | `non_idempotent` | ❌ Error |
| `idempotent` | `unknown` | ⚠️ Warning |
| `idempotent` | `transactional_idempotent` | ❌ Error — weaker guarantee than declared |
| `idempotent` | `externallyIdempotent` | ❌ Error — declared stronger than body supports |
| `observational` | `observational` | ✅ OK |
| `observational` | `idempotent` | ❌ Error — body mutates business state beyond observation sinks |
| `observational` | `non_idempotent` | ❌ Error — body mutates business state beyond observation sinks |
| `observational` | `pure` | ⚠️ Warning — stronger annotation applies |
| `transactional_idempotent` | `transactional_idempotent` | ✅ OK |
| `transactional_idempotent` | `non_idempotent` | ❌ Error — no transaction boundary detected |
| `transactional_idempotent` | `idempotent` | ⚠️ Warning — stronger annotation applies |
| `non_idempotent` | `idempotent` | ⚠️ Warning (over-declared) |
| `non_idempotent` | `observational` | ⚠️ Warning (over-declared) |
| `non_idempotent` | `non_idempotent` | ✅ OK |
| `externallyIdempotent` | `non_idempotent` | ✅ OK — key is the mechanism |
| `externallyIdempotent` | `idempotent` | ⚠️ Warning — simpler annotation applies |
| (none) | `non_idempotent` | ℹ️ Suggestion to annotate |

These outcomes are produced by SwiftProjectLint. Without the linter,
the package cannot detect conflicts on its own — the macros are
markers, not body verifiers.

### Transactions as a composition boundary

A sequence of non-idempotent operations that commits atomically
inside a single transaction is idempotent with respect to external
observers — after any retry, the observable state is either
"transaction never happened" or "transaction committed exactly once."
The lattice recognises this composite as `transactional_idempotent`:

```swift
/// @lint.effect transactional_idempotent
/// @lint.txn_boundary db.transaction
/// Each operation is non-idempotent in isolation; the transaction makes
/// the composite safe to retry.
func transferFunds(from: AccountID, to: AccountID, amount: Money) async throws {
    try await db.transaction { tx in
        try await tx.debit(from, amount)
        try await tx.credit(to, amount)
        try await tx.log(.transfer(from, to, amount))
    }
}
```

**Body-analysis requirements** for `@lint.effect transactional_idempotent`:

1. The function must contain exactly one transaction scope (by
   default: a call to a known transaction opener — `db.transaction`,
   `db.withTransaction`, `Connection.transaction`; configurable per
   project).
2. Every non-idempotent side effect must occur *inside* that
   transaction scope.
3. A non-idempotent call observed *outside* the transaction scope
   demotes the inferred effect to `non_idempotent` and triggers
   `transactionalIdempotencyViolation`.
4. `@lint.txn_boundary <identifier>` optionally names the
   transaction opener for codebases that wrap the driver with a
   domain-specific helper (`ledger.withTransaction`, `UnitOfWork.run`).

**Limitation.** The linter cannot verify that the *database itself*
provides the atomicity guarantee — that's an assumption about the
driver and the storage engine, recorded via
`@lint.assume db.transaction is atomic` or treated as a project-wide
baseline. A transactional composite over a non-transactional store
(two HTTP calls wrapped in a function named `transaction`) is
outside the linter's reach and belongs in code review.

### Branch-sensitive effect inference

A function whose branches have different effects must be reconciled —
the function's inferred effect is the *join* of its branches under
the lattice, which in practice is almost always the weaker of the
two:

```swift
// Branches disagree: one is idempotent, the other is not.
// Inferred effect: non_idempotent (the weaker join).
func save(_ user: User) async throws {
    if featureFlag.isOn(.upsert) {
        try await db.upsert(user)   // idempotent
    } else {
        try await db.insert(user)   // non_idempotent
    }
}
```

Silently collapsing this to `non_idempotent` would surprise authors,
so the linter emits a distinct diagnostic — `effectVariesByBranch` —
that surfaces the disagreement and names the branches. The author
can then reconcile the branches (make both idempotent), restructure
the function, or explicitly annotate the weaker of the two.

**Join rules** (pairwise; extend to N branches by reduction):

| Branch A | Branch B | Join |
|---|---|---|
| pure | idempotent | idempotent |
| pure | observational | observational |
| idempotent | idempotent | idempotent |
| observational | observational | observational |
| idempotent | observational | idempotent (broader claim subsumes observational) |
| idempotent | transactional_idempotent | transactional_idempotent (requires both branches inside the same transaction, else demote) |
| idempotent | externally_idempotent | externally_idempotent |
| idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| observational | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| transactional_idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| externally_idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| any | unknown | unknown (emit `effectVariesByBranch` if non-unknown branch is not unknown) |

The diagnostic is a warning by default and an error when the function
is declared `@Idempotent` (or `@lint.effect idempotent`) but has
non-idempotent branches — the declared contract does not hold
uniformly.

**Rule identifier:** `effectVariesByBranch`.

---

## Annotation grammar

The macro attributes on this package have doc-comment equivalents in
the SwiftProjectLint grammar. The two forms coexist — the linter's
`EffectAnnotationParser` reads both — and adopters can mix them. This
section documents the doc-comment surface for reference.

The `@lint.` prefix avoids collision with DocC conventions
(`@param`, `@returns`, `@throws`) and makes tool-specific annotations
visually distinct.

### Doc-comment forms vs. macro forms

| Macro form | Doc-comment form |
|---|---|
| `@Idempotent` | `/// @lint.effect idempotent` |
| `@NonIdempotent` | `/// @lint.effect non_idempotent` |
| `@Observational` | `/// @lint.effect observational` |
| `@ExternallyIdempotent(by: "key")` | `/// @lint.effect externally_idempotent reason: "..."` |
| (no macro counterpart) | `/// @lint.effect transactional_idempotent` |
| (no macro counterpart) | `/// @lint.effect idempotent(by: <param>)` |
| (no macro counterpart) | `/// @lint.context replayable` (and other contexts — see below) |
| (no macro counterpart) | `/// @lint.assume <symbol> is <effect>` |
| (no macro counterpart) | `/// @lint.unsafe reason: "..."` |
| (no macro counterpart) | `/// @lint.requires idempotency_key` |

A complete example using the doc-comment form:

```swift
/// @lint.effect idempotent
func upsertUser(/* ... */) { /* ... */ }

/// @lint.effect idempotent(by: requestID)
/// Repeated calls with the same requestID produce a single logical effect.
func enqueueJob(requestID: JobID, payload: Data) async throws { /* ... */ }

/// @lint.assume db.upsert is idempotent
/// @lint.assume Logger.info is observational
/// @lint.assume stripe.PaymentIntents.create is externally_idempotent reason: "idempotency-key header"
```

### Scoped idempotency: `idempotent(by: <parameter>)`

Some operations are idempotent only when repeated with the *same
logical key*. Two calls with the same `requestID` are safe to
collapse; two calls with different `requestID`s are two distinct
operations, each of which happens exactly once.

```swift
/// @lint.effect idempotent(by: requestID)
func enqueueJob(requestID: JobID, payload: Data) async throws { /* ... */ }
```

**Linter rules:**

- The named parameter must exist on the function signature. Missing
  parameter → `scopedIdempotencyParameterNotFound`.
- At retry-context call sites, the scoping parameter must be stable
  across iterations: input-derived, defined outside the retry scope,
  not freshly generated per attempt. Violations reuse
  `idempotencyKeyGeneratedInRetry`.
- For callers, `idempotent(by:)` is equivalent to `idempotent` —
  callers may invoke it freely from `@lint.context retry_safe` /
  `replayable` bodies, because the caller is expected to hold the key
  stable.

The macro counterpart is `@ExternallyIdempotent(by:)`; both surface
the same parameter-routing requirement.

### `@lint.assume` — declared, auditable assumptions

Much of the static analysis rests on claims the linter cannot verify:
that a third-party library method is idempotent, that a database
driver's `upsert` really is an upsert, that a specific HTTP endpoint
deduplicates server-side. Rather than burying these claims in
`@lint.unsafe reason:` escape hatches, declare them explicitly:

```swift
/// @lint.assume db.upsert is idempotent
/// @lint.assume stripe.PaymentIntents.create is externally_idempotent reason: "idempotency-key header"
/// @lint.assume Logger.log is pure
```

An assumption:

- Binds a symbol (method, free function, type) to an asserted effect.
- Is *named and locatable* — the linter can list every assumption in
  the codebase as a single report, making them reviewable in bulk.
- Is *scoped* — assumptions declared at file scope apply only within
  that file; assumptions declared in a top-level `Assumptions.swift`
  (by convention) apply project-wide.

Assumptions replace `@lint.unsafe` for the common case of "I know
this external thing is idempotent." `@lint.unsafe` remains the
escape hatch for cases where even an assumption would be too strong.

### Effect annotations on closure parameters

A generic retry wrapper cannot say anything useful about its callees
without a mechanism to declare what it expects of its body argument.
The grammar extends to closure parameter types:

```swift
/// @lint.effect non_idempotent
/// @lint.param body requires idempotent
/// Retries `body` on transient failure. Body must be idempotent.
func withRetry<T>(
    maxAttempts: Int = 3,
    body: @escaping () async throws -> T
) async throws -> T { /* ... */ }
```

**Enforcement:**

- At every call site of `withRetry`, the linter resolves the
  argument passed for `body` and checks its effect against the
  declared requirement.
- A literal closure is analysed in-place using the same rules as a
  named function body.
- A named function reference (`withRetry(body: sendEmail)`) is
  looked up in the effect symbol table.
- A closure whose effect cannot be determined (captures an `unknown`
  callee, or is passed through multiple indirections) produces a
  warning rather than an error.

**Shorthand form** for the common case where the retry wrapper is
the body's only user:

```swift
/// @lint.effect retry_safe_wrapper
func withRetry<T>(maxAttempts: Int = 3, body: @escaping () async throws -> T) async throws -> T
```

`@lint.effect retry_safe_wrapper` is sugar for
`@lint.effect non_idempotent` plus
`@lint.param body requires idempotent_or_externally_idempotent`,
matching the most common pattern exactly.

**Rule identifiers:**

```swift
case closureArgumentFailsEffectRequirement   // body argument does not meet declared @lint.param requirement
case retryWrapperMissingBodyRequirement      // @lint.effect retry_safe_wrapper without declared body effect
```

There is no macro counterpart to `@lint.param`. The doc-comment form
is the only surface for declaring closure-argument effect
requirements.

### Suppression grammar

`@lint.unsafe` is the right escape hatch for *semantic* suppressions —
cases where the author is making a claim about external behaviour
that the linter cannot verify. It is the wrong mechanism for
*mechanical* suppressions: a known false positive on a single line, a
file that hasn't been migrated yet, a whole module excluded from a
new rule. A separate suppression grammar, modelled on SwiftLint's
conventions, handles the mechanical case:

```swift
// Single line
// swift-idempotency:disable-next-line nonIdempotentInRetryContext
try await chargeCard(amount: 100)

// Block
// swift-idempotency:disable nonIdempotentInRetryContext
for attempt in 1...maxRetries {
    try await legacyNonIdempotentCall()
}
// swift-idempotency:enable nonIdempotentInRetryContext

// File scope — first line of the file
// swift-idempotency:disable-file actorReentrancyIdempotencyHazard
```

**Rules:**

- Suppressions name the specific rule identifier. Blanket
  `// swift-idempotency:disable` (no identifier) is not supported — it
  makes the codebase unreviewable.
- A suppression with no matching violation in its scope is itself a
  diagnostic (`unusedSuppression`). Suppressions don't outlive the
  problem they were hiding.
- Project-level configuration (`.swift-idempotency.yml`) supports
  per-directory rule disables for incremental adoption.

The distinction to remember: `@lint.unsafe reason:` is a claim about
*semantics* ("this really is idempotent, trust me");
`// swift-idempotency:disable-next-line` is a claim about *the linter*
("this rule is wrong here"). Different review implications, different
syntax.

**Rule identifiers:**

```swift
case unusedSuppression              // suppression directive with no violation in scope
case malformedSuppressionDirective  // unparseable // swift-idempotency: directive
```

---

## Context annotations

Context annotations describe the *execution context* in which a
function runs, rather than the function's own properties. They catch
a different class of bugs — violations that arise not from what a
function does, but from where it is called.

These annotations are **doc-comment-only** — there are no macro
counterparts in this package. They are documented here because the
package's macros interact with them at the lattice level: a function
marked `@NonIdempotent` cannot legally be called from a body
annotated `/// @lint.context replayable`, for example.

```swift
/// @lint.context replayable
func handleOrderCreated(event: OrderCreatedEvent) async throws { /* ... */ }

/// @lint.context retry_safe
func syncUserProfile(userID: UserID) async throws { /* ... */ }

/// @lint.context once
func migrateDatabase(from: SchemaVersion) async throws { /* ... */ }

/// @lint.context dedup_guarded
func processPayment(id: PaymentID) async throws { /* ... */ }
```

### `replayable` and `retry_safe`

These two contexts place **requirements on callees**. The function
may execute multiple times; therefore everything it calls must
tolerate multiple executions.

| Callee effect | Outcome |
|---|---|
| `pure`, `idempotent`, or `observational` | ✅ OK |
| `externally_idempotent` | ⚠️ Warning — weaker contract, accepted with justification |
| `non_idempotent` (declared) | ❌ Error |
| `non_idempotent` (inferred) | ❌ Error |
| `unknown` | ⚠️ Warning |

`observational` is accepted unconditionally — observation calls
(logging, metrics, tracing) are ubiquitous in any idempotency-caring
system, and their effects on observation sinks are tolerable under
retry by construction.

**Distinction between the two:** `replayable` implies the system
delivers the call (event bus, message queue — outside the function's
control). `retry_safe` implies the function or its caller initiates
the retry on failure. Enforcement is identical; the distinction is
documentary.

### `strict_replayable` — opt-in strict mode

`strict_replayable` is the opt-in strict variant of `replayable`. It
imposes every constraint `replayable` imposes, *plus* flags callees
whose effect the linter can't prove. The "silent on unknown callees"
default of `replayable` flips to "flag unless proven."

| Callee status | Outcome (vs. plain `replayable`) |
|---|---|
| Annotated `idempotent`/`observational`/`externally_idempotent` | ✅ OK (unchanged) |
| Inferred `non_idempotent` | ❌ Error (unchanged) |
| No annotation, no inference, no heuristic | ❌ Error (`unannotatedInStrictReplayableContext`) — *new* |

**When to use it.** Promote critical handlers individually; leave
less-critical ones on `replayable`. Best suited to *business-app
handlers* where most callees live in-project and can be annotated —
webhooks, payment processors, event handlers built on your own
helpers. Library-mediated handlers (where every callee is in
Foundation/NIO/an SDK) produce high noise floors because external
callees are un-annotatable. For those, stay on `replayable`.

### `once` — the inverse guarantee

`once` is the complement of `retry_safe`. It does not constrain
callees — a once-only migration is *allowed* to call non-idempotent
operations, because that's the whole point. Instead, it places
**requirements on callers**: this function must not be invoked in
any retry context.

```swift
// ❌ Error: retry context calls a once-only function
/// @lint.context retry_safe
func rebuildSearchIndex() async throws {
    try await migrateDatabase(from: .v1)  // @lint.context once — cannot be called here
}

// ❌ Error: once-only function called inside an explicit retry loop
for attempt in 1...maxRetries {
    try await migrateDatabase(from: .v1)
}

// ✅ OK: called from a non-retry context
func runStartupSequence() async throws {
    try await migrateDatabase(from: .v1)
}
```

**Limitation**: if a `once` function is stored as a closure and
called later, the static analysis cannot detect the eventual call
site. Call-site checking only works for direct invocations visible
in the AST.

### `dedup_guarded` — assertion with mechanism

This is the most nuanced context and the one most easily confused
with `@Idempotent`. The distinction matters:

- **`@Idempotent`** (or `/// @lint.effect idempotent`): the linter
  *verifies* the function body is idempotent through analysis. The
  body must pass the body check.
- **`/// @lint.context dedup_guarded`**: the function *asserts* it
  produces idempotent outcomes through a mechanism the linter cannot
  fully verify (idempotency keys, a deduplication table, a
  transactional guard). Body check is suppressed; mechanism check
  replaces it.

```swift
// ❌ Wrong annotation — linter flags chargeCard as non_idempotent in the body
/// @lint.effect idempotent
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: IdempotencyKey(fromAuditedString: id.value))
    try await updateOrderStatus(id, status: .paid)
}

// ✅ Correct annotation — asserts idempotency is handled via the key mechanism
/// @lint.context dedup_guarded
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: IdempotencyKey(fromAuditedString: id.value))
    try await updateOrderStatus(id, status: .paid)
}
```

Because the body check is suppressed, the linter instead requires
*evidence of a mechanism*:

| Mechanism | Outcome |
|---|---|
| Function accepts `IdempotencyKey` parameter, or constructs one from inputs before any non-idempotent calls | ✅ |
| Function checks a processed-ID set or similar guard before non-idempotent work | ✅ |
| `@lint.unsafe reason: "..."` suppresses the mechanism requirement with documented justification | ✅ with warning |
| No visible mechanism | ❌ `dedupGuardedWithoutMechanism` |

From the caller's perspective, `dedup_guarded` behaves like
`@Idempotent`: the function is safe to call from retry contexts.

### Context interaction matrix

| Caller's context | Callee `once` | Callee `retry_safe` / `replayable` | Callee `dedup_guarded` |
|---|---|---|---|
| `retry_safe` / `replayable` | ❌ Would call once-function multiple times | ✅ | ✅ |
| `once` | ✅ Both run once | ✅ | ✅ |
| `dedup_guarded` | ❌ Caller may run multiple times; violates callee's once contract | ✅ | ✅ |
| (no context) | ✅ No retry implied | ✅ | ✅ |

### Rule identifiers (context)

```swift
case onceOperationInRetryContext           // @context once function called inside retry_safe / replayable body
case onceOperationInRetryLoop              // @context once function called inside a detected retry loop
case dedupGuardedWithoutMechanism          // @context dedup_guarded with no visible key or guard mechanism
case retryContextCallingOnce               // retry_safe / replayable context directly calls @context once
case unannotatedInStrictReplayableContext  // strict_replayable callee is unproven
```

---

## Idempotency keys as a first-class concept

Idempotency keys represent a categorically different form of
idempotency from the function-level analysis above. They make a
*non-idempotent operation* safe to retry by outsourcing
deduplication to an external system. The package's `IdempotencyKey`
strong type and `@ExternallyIdempotent(by:)` macro are the surface
through which this lattice tier appears in user code; this section
covers the *concept* and key-quality criteria. See the
[`IdempotencyKey`](#idempotencykey) symbol entry below for
constructor-by-constructor detail.

### The `externallyIdempotent` effect tier

The [Effect lattice](#effect-lattice) places `externallyIdempotent`
between `idempotent` and `non_idempotent`. It's weaker than
intrinsic idempotency in two ways:

- It depends on an external system's stateful contract, not the
  local function body.
- A wrong key — unstable, colliding, or too broadly scoped —
  silently degrades it back to `non_idempotent`.

```swift
@ExternallyIdempotent(by: "idempotencyKey")
func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) throws -> Receipt { /* ... */ }
```

### Key quality: what makes a key valid

Three properties of a valid key:

1. **Stable across retries** — identical value on every retry of the
   same logical operation.
2. **Input-derived or pre-generated** — not sourced from fresh
   entropy at the call site.
3. **Correctly scoped** — unique per logical operation, not reused
   across different operations.

```swift
// ❌ New key generated each iteration
for attempt in 1...maxRetries {
    let key = IdempotencyKey(fromAuditedString: UUID().uuidString)
    try chargeCard(amount: 100, idempotencyKey: key)
}

// ✅ Key derived deterministically from inputs, defined outside the loop
let key = IdempotencyKey(fromEntity: paymentRequest)
for attempt in 1...maxRetries {
    try chargeCard(amount: 100, idempotencyKey: key)
}
```

### Strong-type enforcement

The package's `IdempotencyKey` type is the most effective lint
target — it eliminates `String` as a key parameter. With
`IdempotencyKey` as the parameter type, passing `UUID().uuidString`
directly is a *compile error*, not a lint warning. See the
[`IdempotencyKey`](#idempotencykey) symbol entry below for the
allowed constructors and the rationale for what is *not* provided.

### Lintable bad patterns

Even without the strong type — e.g., on call sites that haven't been
migrated and still pass `String` — several patterns are detectable
by the linter at the call site.

**Pattern 1: `UUID()` passed directly as an idempotency key**

```swift
try chargeCard(amount: 100, idempotencyKey: UUID().uuidString)  // ❌
```

Detection: at any call site where an argument label matches
`/idempotency.?key/i`, check if the argument expression is or
contains `UUID()` or `Date()`.

**Pattern 2: Key generated inside a retry loop body**

```swift
for attempt in 1...maxRetries {
    let key = UUID().uuidString
    try chargeCard(amount: 100, idempotencyKey: key)
}
```

Detection: inside a retry context body, flag any `let key = UUID()`
whose binding is used as an idempotency-key argument in the same
scope. The key must be defined *outside* the retry scope.

**Pattern 3: `@lint.requires idempotency_key` function called without
a key in retry context**

When a function is annotated `/// @lint.requires idempotency_key`,
call sites inside retry contexts that omit the key argument are
flagged.

### `@lint.requires idempotency_key` — enforcement definition

The linter enforces this in two directions:

- **On the declaration**: the annotated function must have a
  parameter whose label matches `/idempotency.?key/i`. If the body
  doesn't use that parameter to dedup or pass it to an external
  system, that's a warning (annotation without mechanism).
- **On call sites**: inside any retry context, a call to a
  `@lint.requires idempotency_key` function must provide a key
  argument whose value is not derived from fresh entropy in the
  retry scope.

The macro-form equivalent is `@ExternallyIdempotent(by: "<param>")`
— specifying the parameter name lets the linter verify the key is
being routed correctly without requiring the regex match.

### Rule identifiers (idempotency keys)

```swift
case unstableIdempotencyKey         // UUID() or other fresh entropy used as key value
case idempotencyKeyGeneratedInRetry // key binding created inside retry scope body
case missingIdempotencyKey          // @lint.requires idempotency_key function called without key in retry context
case idempotencyKeyMechanismMissing // @lint.effect externally_idempotent declared but no key parameter found
```

---

## Effect escaping analysis

A naive heuristic — flagging every `UUID()`, `Date()`, or
`array.append` call as non-idempotent — produces significant false
positives. The linter must distinguish between non-determinism that
**escapes** the function boundary and non-determinism that is
**local and discarded**.

```swift
// UUID is local and discarded — function IS idempotent at the business-logic level.
@Idempotent
func processPayment(id: PaymentID, amount: Int) {
    let traceID = UUID()             // local trace
    log.trace(traceID, "processing \(id)")
    db.upsert(Payment(id: id, amount: amount))
}
```

Flagging `UUID()` here would be wrong. The `traceID` never escapes
the function — it's not persisted, returned, or routed into business
state. Compare:

```swift
// Non-idempotent: UUID escapes via the return value.
func createUser() -> User {
    User(id: UUID())  // each call returns a different User
}

// Non-idempotent: UUID escapes via persistence.
func createAuditEntry(action: String) {
    db.insert(AuditLog(id: UUID(), action: action))  // UUID persisted
}

// Idempotent: UUID local, discarded after the log call.
func processPayment(id: PaymentID) {
    let spanID = UUID()
    log.debug("span: \(spanID)")
    db.upsert(Payment(id: id))
}
```

Implementing escape analysis fully requires data-flow tracking. The
linter uses a practical SwiftSyntax-based approximation:

1. Flag `UUID()`, `Date()`, and similar calls as **potentially
   non-idempotent sources**.
2. Track each value's downstream usage:
   - Passed to `db.insert` / `db.create` / `append` / etc. →
     **likely escapes** → diagnostic fires.
   - Used only in logging calls or local scope → **likely local** →
     suppressed.
3. Annotate genuinely ambiguous cases (`@lint.assume` or
   `@lint.unsafe reason:`) and let the author decide.

This is why a `UUID()` inside an `@Idempotent`-marked function does
not always fire a diagnostic — escape analysis governs whether the
non-determinism actually reaches the observable surface.

---

## Retry pattern detection

The linter detects known retry shapes syntactically and enforces
idempotency on the bodies inside them. This is what makes the
retry-context rules (`nonIdempotentInRetryContext`,
`idempotencyKeyGeneratedInRetry`) actionable on un-annotated code.

**Pattern 1 — named retry function**

```swift
retry {
    chargeCard(amount: 100)  // ❌ — body of a known retry wrapper
}
```

**Pattern 2 — counted `for` loop**

```swift
for attempt in 1...maxRetries {
    try await chargeCard(amount: 100)  // ❌
}
```

**Pattern 3 — retry middleware on an HTTP client**

```swift
session.dataTask(retryPolicy: .exponential) { /* ... */ chargeCard(/* ... */) }
```

**Detection strategy** (linter-side):

- Maintain a **known retry-call list**: `retry(_:)`,
  `withRetry(_:)`, `retryable(_:)`, plus configured per-project
  additions.
- Detect `for` loops iterating over `1...N` or `0..<N` ranges that
  contain `try await` calls in the body.
- Recurse into closures passed to known retry wrappers, applying
  the same body-analysis rules used for `@lint.context replayable`.

The patterns above cover the synchronous and simple-async shapes.
Swift Concurrency introduces several more (Task, TaskGroup,
recursive retry, SwiftUI `.task`, AsyncSequence) — see the next
section.

---

## Swift concurrency interactions

Swift concurrency creates two independent problems for idempotency
analysis: actors introduce a class of idempotency bug that doesn't
exist in synchronous code, and the async/await ecosystem introduces
retry patterns that the simple shapes documented in
[Retry pattern detection](#retry-pattern-detection) don't cover.

### Actors don't imply idempotency

Actor isolation serialises *access* to state — it prevents concurrent
mutation. It does not prevent repeated mutation:

```swift
actor UserCache {
    // Idempotent — setting a key to the same value is safe to repeat.
    func upsert(_ user: User) {
        users[user.id] = user
    }

    // Non-idempotent — appending grows the collection on every call.
    func append(_ user: User) {
        users[user.id] = user
        auditLog.append(user)
    }
}
```

Actor method bodies are analysed exactly like any other function body
— actor isolation is irrelevant to idempotency analysis.

### Actor reentrancy breaks the check-then-act pattern

Actors in Swift are *reentrant*: when an actor method hits an
`await`, it suspends and other callers can enter. The classic
"check then act" idempotency guard fails silently across a
suspension point:

```swift
actor PaymentProcessor {
    private var processedIDs: Set<PaymentID> = []

    func process(_ id: PaymentID) async throws {
        // ❌ Reentrancy hazard: another caller can enter between the guard and the insert.
        guard !processedIDs.contains(id) else { return }
        try await chargeCard(id)  // suspension point — actor is now open to re-entry
        processedIDs.insert(id)   // too late
    }
}
```

Two concurrent callers both pass the `guard`, both `await chargeCard`,
both charge the card. The actor serialised their *reads* of
`processedIDs` but not the full check-suspend-act sequence.

The fix is to claim the slot *before* the suspension point:

```swift
actor PaymentProcessor {
    func process(_ id: PaymentID) async throws {
        guard !processedIDs.contains(id) else { return }
        processedIDs.insert(id)  // ✅ claim before any suspension
        do {
            try await chargeCard(id)
        } catch {
            processedIDs.remove(id)  // compensate on failure
            throw error
        }
    }
}
```

This is structurally detectable. The linter's
`actorReentrancyIdempotencyHazard` rule fires on the pattern:

```
Inside an actor method:
    guard !collection.contains(id) → ...
    [one or more await expressions]
    collection.insert(id)           ← insert appears AFTER a suspension
```

The rule fires on structural grounds independent of any annotation —
it's the one rule that delivers value before any team has annotated
anything.

### Retry patterns introduced by Swift concurrency

Beyond the simple `for attempt in 1...maxRetries { ... }` shape,
Swift concurrency introduces several patterns that are functionally
retries but require more sophisticated detection.

**Pattern A — unstructured `Task` inside a retry loop**

```swift
for attempt in 1...maxRetries {
    let task = Task { try await chargeCard(amount: 100) }
    _ = try await task.value
}
```

The `try await` is on `task.value`, not on `chargeCard` directly —
detection must trace into `Task { }` closures.

**Pattern B — `withThrowingTaskGroup` used as a retry mechanism**

```swift
try await withThrowingTaskGroup(of: Receipt.self) { group in
    for attempt in 1...maxRetries {
        group.addTask { try await chargeCard(amount: 100) }
    }
    return try await group.next()!
}
```

A `for` loop over `addTask` is structurally a retry loop with
parallel execution.

**Pattern C — recursive async retry**

```swift
func retryableCharge(attempt: Int = 0) async throws -> Receipt {
    do {
        return try await chargeCard(amount: 100)
    } catch where attempt < 3 {
        return try await retryableCharge(attempt: attempt + 1)
    }
}
```

Detection requires identifying recursive calls in `catch` blocks.

**Pattern D — SwiftUI `.task {}` view modifier**

```swift
.task {
    try? await chargeCard(amount: 100)
}
```

`.task {}` runs each time the view appears. Navigating back and
forth replays the body — functionally equivalent to a retry for
idempotency purposes. High-value lint target in SwiftUI codebases.

**Pattern E — `for try await` over an at-least-once `AsyncSequence`**

```swift
for try await event in eventStream {
    try await chargeCard(amount: event.amount)
}
```

An `AsyncSequence` is a replayable context whenever its producer has
at-least-once semantics — Kafka consumers, Kinesis shards,
CloudWatch Logs subscribers, SwiftNIO channel reads during
reconnection. The sequence type alone doesn't tell the linter
whether repeats are possible; the consumption site should be
annotated when relevant:

```swift
/// @lint.context replayable reason: "Kinesis may re-deliver on shard rebalance"
for try await event in kinesisShard.events {
    try await processEvent(event)  // must be @Idempotent
}
```

Without an annotation, the linter cannot know the semantics of an
arbitrary `AsyncSequence`, so the default is no diagnostic — this is
an opt-in replayable context rather than an inferred one.

### Async/await is not itself an effect

The `async` keyword does not change a function's effect
classification. A function is idempotent or not independent of
whether it suspends:

```swift
@Idempotent
func upsertUser(id: UserID) async throws { /* ... */ }
```

The package's `@IdempotencyTests` macro expansion mirrors the
target's effect specifiers — `try` and `await` appear at the
generated call site only when the target's signature requires them.
See the [`@IdempotencyTests`](#idempotencytests) symbol entry below.

### Rule identifiers (concurrency)

```swift
case actorReentrancyIdempotencyHazard  // guard-await-insert ordering violation in actor method
case nonIdempotentInTaskRetry          // non-idempotent call inside Task { } within retry loop
case nonIdempotentInTaskGroup          // non-idempotent addTask inside counted retry loop
case nonIdempotentInRecursiveRetry     // non-idempotent call in recursive catch-and-retry pattern
case nonIdempotentInSwiftUITask        // non-idempotent call in .task {} view modifier
```

---

## Macro-based test generation: design rationale

This section documents the design problem the package's test-generation
macros (`@IdempotencyTests`, `#assertIdempotent`,
`assertIdempotentEffects`) had to solve, and explains why the surface
is shaped the way it is. The original PRD design proposed a single
`IdempotencyTestable` protocol with a `captureIdempotencyState()`
method; the shipped package replaced that with a more granular
two-tool design (return-equality via `#assertIdempotent` plus
effect-observation via `IdempotentEffectRecorder`). Both roads start
from the same problem.

### The state-capture problem

The instinct — generate a test that calls the function twice with
the same inputs and asserts equivalent outcomes — is correct. The
execution is harder than it first appears.

A naive generated test has a fundamental flaw:

```swift
// ❌ MockDatabase() and snapshot() are conjured from nothing
@Test func idempotency_test_upsertUser() throws {
    let database = MockDatabase()        // macro cannot know this type exists
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterFirst = database.snapshot()   // macro cannot know this method exists
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterSecond = database.snapshot()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

The macro has access to the function's *signature* — its name,
parameters, return type, and effect specifiers. It has no access to
the function's *dependencies*. A function returning `Void` gives the
macro nothing to compare automatically.

### Tiered solution (as shipped)

The package's tiered solution maps to the same three tiers the PRD
proposed but ships them as separate tools rather than one
auto-detecting macro:

**Tier 1 — non-`Void` `Equatable` return type → `#assertIdempotent`.**
When the function returns an `Equatable` value, comparing return
values directly is sufficient. This is what `#assertIdempotent`
does. Generation is fully automatic — the macro emits two
invocations and a `#expect` on equality.

```swift
let result = try await #assertIdempotent {
    try await processPayment(for: event)
}
```

Limitation: only captures the return value. A function that returns
a stable value but mutates external state passes this check
incorrectly. This is the gap Tier 2 closes.

**Tier 2 — observable side effects → `IdempotentEffectRecorder` +
`assertIdempotentEffects`.** When the return value is `Void`,
`HTTPStatus.ok`, or otherwise insufficient, conform test doubles to
`IdempotentEffectRecorder` and use `assertIdempotentEffects` to
compare snapshots across invocations.

```swift
try await assertIdempotentEffects(recorders: [coinRepo, userRepo]) {
    _ = try await handler.handleAddUser(entry: request)
}
```

The PRD's original `IdempotencyTestable` protocol was a single-shape
solution: every type that wanted state capture had to conform with
exactly one `Snapshot` type. The shipped `IdempotentEffectRecorder`
generalises this — each recorder has its own associated
`Snapshot: Equatable` (defaulting to `Int`-backed `effectCount`),
and `assertIdempotentEffects` compares across heterogeneous
recorders via a type-erased snapshot box.

**Tier 3 — generated stub with TODOs (deferred).** The PRD also
proposed a Tier 3 where, when the macro can't determine what to
compare, it generates a compilable stub with explicit TODOs. This
tier was deliberately *not* shipped: TODO-stubbed tests that pass by
default risk masking real bugs (the test passes because the TODO
comparison is `() == ()`, not because the function is idempotent).
The shipped equivalent is `@IdempotencyTests` declining to generate
anything for parameterised members — adopters use `#assertIdempotent`
or `assertIdempotentEffects` at explicit test sites instead.

### Actor-isolated functions

When `@IdempotencyTests` is applied to a `@Suite` that contains
actor methods, the generated peers cross the actor boundary for
state capture, requiring `async` on the generated test even if the
target method is synchronous. The macro detects actor context via
the `ActorDeclSyntax` parent and forces `async` on the generated
test regardless of the method's own `effectSpecifiers`.

### Property-based testing (deferred)

The fixed-input double-call pattern only tests one point in the
input space. A function that is idempotent for `name: "Alice"` but
not for `name: ""` will pass undetected.

The PRD proposed an `IdempotencyTestInputProvider` protocol that the
macro would consume to generate parameterised tests. This was not
shipped — the test target depends on `swift-property-based` for
property-based coverage of `IdempotencyKey`'s constructors, but
parameterised generation for `@IdempotencyTests`-marked functions
remains deferred. Use `#assertIdempotent` inside a parameterised
`@Test` for the same shape today:

```swift
@Test(arguments: [
    UserID("u1"), UserID("u2"), UserID("u3")
])
func upsertUserIsIdempotent(id: UserID) async throws {
    _ = try await #assertIdempotent {
        try await upsertUser(id: id, name: "Alice")
    }
}
```

---

## Protocol-based type safety: design alternatives

The PRD evaluated three protocol-based patterns for encoding
idempotency in the type system. The shipped package landed on the
strong-type approach (`IdempotencyKey`) for the *value* layer and
attribute macros (`@Idempotent` etc.) for the *declaration* layer,
without shipping any of the protocols below. This section documents
the alternatives considered and why they didn't ship — useful for
adopters wondering "why isn't there an `IdempotentOperation`
protocol?"

### Pattern A: marker protocols

```swift
public protocol IdempotentOperation {}
public protocol NonIdempotentOperation {}
```

Pure declarations of intent — no added interface, just a conformance
the linter and type system can detect. Analogous to `Sendable` or
`Hashable` without synthesis.

**Strength**: zero boilerplate; drop-in on existing types.
**Weakness**: protocols attach to *types*, not free functions. Most
Swift APIs are methods or free functions — neither is directly
addressable. The shipped `@Idempotent` macro covers free functions
and methods uniformly, which marker protocols cannot.

### Pattern B: operation objects (Command pattern)

```swift
public protocol IdempotentOperation {
    associatedtype Input
    associatedtype Output
    func execute(_ input: Input) throws -> Output
}
```

The killer feature is generic constraints at call sites:

```swift
// Compiler enforces idempotency — passing a NonIdempotentOperation here
// is a compile error.
func withRetry<Op: IdempotentOperation>(
    _ operation: Op,
    input: Op.Input,
    maxRetries: Int = 3
) throws -> Op.Output { /* ... */ }
```

No annotation system can do this. `/// @lint.effect idempotent`
produces a lint warning at best; `Op: IdempotentOperation` is a
hard compile error.

**Why it didn't ship as a package protocol**: requiring adopters
to restructure existing methods as `Operation` objects contradicts
the incremental-adoption design constraint. The shipped
`IdempotencyKey` strong type provides a similar compile-time
guarantee at the *parameter* level without requiring architectural
restructuring — passing `UUID()` where `IdempotencyKey` is required
is also a hard compile error.

### Pattern C: effect-tagged function wrappers

A middle ground — wrap free functions in typed containers without
requiring full operation objects:

```swift
public struct Idempotent<Input, Output> {
    public let run: (Input) throws -> Output
}

public struct NonIdempotent<Input, Output> {
    public let run: (Input) throws -> Output
}
```

This brings the effect into the *value* rather than the *type
definition*, which works for free functions and closures without
restructuring. Did not ship for the same reason as Pattern B: the
attribute-macro form (`@Idempotent`) on the function declaration is
less invasive on existing call-site shape.

### The critical limitation: protocols don't verify behaviour

Even when a protocol-based pattern ships, it shares the same
fundamental limitation as a doc-comment annotation:

```swift
struct LyingOperation: IdempotentOperation {
    func execute(_ id: UserID) throws -> User {
        try database.insert(User(id: UUID(), /* ... */))   // non-idempotent — but conforms
    }
}
```

This is the same problem as `Sendable` with `@unchecked` —
conformance is a *declaration*, not a *proof*. The linter's role
remains the same regardless of whether the marker is a protocol
conformance or an `@Idempotent` attribute: when the marker is
present, verify the body. The marker form is incidental; the
verification is the load-bearing piece.

### The `@unchecked` escape hatch

```swift
struct ExternalServiceCall: @unchecked IdempotentOperation {
    func execute(_ id: PaymentID) throws -> Receipt {
        // External API guarantees idempotency via idempotency key,
        // but we can't prove it from the body alone.
        try paymentGateway.charge(id, idempotencyKey: id.rawValue)
    }
}
```

`@unchecked` would suppress the body check while preserving the
type-system constraint. The shipped equivalent is
`@ExternallyIdempotent(by: "key")` — same shape (the function
asserts external-mechanism idempotency rather than intrinsic body
idempotency), expressed via attribute rather than protocol.

### Effect annotations on protocol requirements

The most powerful composition would be declaring an effect on a
protocol method *requirement*. The contract becomes a covariant
obligation on every conformer — every witness must supply a body
that satisfies at least the declared effect:

```swift
public protocol Repository {
    associatedtype Entity: Identifiable

    /// @lint.effect idempotent
    func upsert(_ entity: Entity) async throws

    /// @lint.effect non_idempotent
    func insert(_ entity: Entity) async throws

    /// @lint.effect externally_idempotent reason: "caller supplies key"
    func enqueue(_ entity: Entity, key: IdempotencyKey) async throws
}
```

When a type conforms to `Repository`, the linter checks every
witness against the corresponding requirement's declared effect:

- Witness's declared annotation stronger than or equal to
  requirement: ✅
- Witness's declared annotation weaker than requirement: ❌
  `protocolWitnessWeakerEffect`
- Witness has no annotation: inferred effect must meet the
  requirement, else ⚠️ or ❌ depending on strict mode
- Witness marked `@lint.unsafe`: ⚠️ — conformance by assertion,
  documented

This is the cleanest way to encode "every `Repository` implementation
has an idempotent `upsert`" as a *machine-checkable* constraint.
Generic callers can declare the effect they need, and the linter can
reason about it without inspecting the concrete type:

```swift
/// @lint.context retry_safe
func syncRemoteState<R: Repository>(_ repository: R, entities: [R.Entity]) async throws {
    for entity in entities {
        try await repository.upsert(entity)  // ✅ — requirement declares idempotent
        try await repository.insert(entity)  // ❌ — requirement declares non_idempotent
    }
}
```

**Rule identifiers** (linter-side; not enforced by this package):

```swift
case protocolWitnessWeakerEffect     // witness's effect is weaker than the requirement
case protocolRequirementUnannotated  // protocol method has no @lint.effect — suggestion in strict mode
```

### Honest trade-offs

| Dimension | Protocols | Attribute macros / annotations |
|---|---|---|
| Compiler enforcement | Hard errors via generic constraints | Never — lint only |
| Free functions | Can't attach directly (Pattern C works around this) | Works naturally |
| Refactoring safety | Conformances travel with the type | Comments can be orphaned |
| Incrementally adoptable | Requires operation-object restructuring | Additive, no restructuring |
| Composability | First-class via generics | No composition model |
| Existing codebase fit | Requires architectural buy-in | Drop-in on any function |

The right answer is **both**: the package ships strong types
(`IdempotencyKey`) for compile-time enforcement at parameter
boundaries, attribute macros (`@Idempotent` etc.) for declaration-
level markers, and the linter consumes both — plus doc-comment
forms — through a common `EffectAnnotationParser`. Protocols for new
operation-object code remain a future option for adopters who want
the architectural buy-in.

---

## Integration with SwiftProjectLint

This section documents the visitor architecture and rule-identifier
roster on the linter side. Adopters using only this package don't
need to know the internals; this section is here for completeness
and for adopters debugging cross-tool behaviour.

### `IdempotencyVisitor`

```swift
// In SwiftProjectLint:
// Sources/Core/Architecture/Visitors/IdempotencyVisitor.swift

final class IdempotencyVisitor: BasePatternVisitor {

    // Pass 1: extract annotations from doc comments and attribute lists.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let effects = EffectAnnotationParser.parse(from: node.leadingTrivia)
        symbolTable.register(node.name.text, effects: effects)
        return .visitChildren
    }

    // Pass 2: check call expressions in annotated contexts.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let currentContext = currentFunctionContext else { return .visitChildren }
        if currentContext.declaredEffect == .idempotent {
            checkCalleeIdempotency(node)
        }
        return .visitChildren
    }

    // Detect retry patterns (see Retry pattern detection section).
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        if isRetryPattern(node) {
            retryContextStack.push(.retryLoop(node))
        }
        return .visitChildren
    }

    // Detect IdempotentOperation conformance (future protocol-based extension).
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsTo(node, protocol: "IdempotentOperation") {
            scheduleBodyCheck(for: node, effect: .idempotent)
        }
        return .visitChildren
    }
}
```

### Rule identifier roster

Across the lattice, context, key, escape, retry, concurrency, and
suppression sections above, the linter exposes these rule
identifiers:

```swift
// Effect lattice
case idempotencyViolation                       // @effect idempotent calls @effect non_idempotent
case effectVariesByBranch                       // function's branches have different effects
case transactionalIdempotencyViolation          // @effect transactional_idempotent has writes outside the transaction

// Annotation grammar
case scopedIdempotencyParameterNotFound         // idempotent(by: <param>) — param doesn't exist
case closureArgumentFailsEffectRequirement      // body argument doesn't meet @lint.param requirement
case retryWrapperMissingBodyRequirement         // @lint.effect retry_safe_wrapper without declared body effect

// Suppression
case unusedSuppression                          // suppression directive with no violation in scope
case malformedSuppressionDirective              // unparseable // swift-idempotency: directive
case unknownAnnotationVersion                   // annotation not defined in pinned grammar version

// Context
case nonIdempotentInRetryContext                // non-idempotent call inside retry wrapper
case nonIdempotentInReplayableContext           // non-idempotent in @context replayable
case onceOperationInRetryContext                // @context once function called inside retry_safe / replayable body
case onceOperationInRetryLoop                   // @context once function called inside detected retry loop
case retryContextCallingOnce                    // retry_safe / replayable directly calls @context once
case dedupGuardedWithoutMechanism               // @context dedup_guarded with no visible key or guard mechanism
case unannotatedInStrictReplayableContext       // @context strict_replayable callee with no proven effect

// Idempotency keys
case unstableIdempotencyKey                     // UUID() or other fresh entropy used as key value
case idempotencyKeyGeneratedInRetry             // key binding created inside retry scope body
case missingIdempotencyKey                      // @lint.requires idempotency_key called without key in retry context
case idempotencyKeyMechanismMissing             // @lint.effect externally_idempotent declared but no key parameter

// Escape analysis
case uuidEscapesIdempotentFunction              // UUID() result persisted inside @effect idempotent
case mixedIdempotencyEffects                    // function has both idempotent and non-idempotent callees
case unannotatedSideEffectFunction              // function has side effects but no @effect annotation

// Concurrency
case actorReentrancyIdempotencyHazard           // guard-await-insert ordering in actor method
case nonIdempotentInTaskRetry                   // non-idempotent inside Task { } in retry loop
case nonIdempotentInTaskGroup                   // non-idempotent addTask inside counted retry loop
case nonIdempotentInRecursiveRetry              // non-idempotent in recursive catch-and-retry pattern
case nonIdempotentInSwiftUITask                 // non-idempotent in .task {} view modifier

// Protocol witness (proposed; not currently shipped)
case protocolWitnessWeakerEffect                // witness's effect is weaker than the requirement
case protocolRequirementUnannotated             // protocol method has no @lint.effect — suggestion in strict mode
```

### Cross-file support

Effect propagation that's truly meaningful requires cross-file
analysis — most violations span files. SwiftProjectLint's
`CrossFileAnalysisEngine` hosts the inter-file symbol table needed
for call-graph propagation. The `IdempotencyVisitor` populates the
table per-file; the engine computes the call graph and re-runs
violation checks across the whole project.

---

## Edge cases and implementation notes

A handful of secondary concerns that don't fit anywhere else but
matter for adopters working at the edges of the model.

### Empty and trivial function bodies

A function with an empty body, or a body containing only `return`,
is trivially idempotent — it has no observable effect. Body analysis
short-circuits to `pure` in this case rather than `unknown`. A
function whose body consists only of pure-declared callees is
similarly `pure`. This matters for initializer stubs, no-op protocol
witnesses, and generated code — defaulting to `unknown` would flood
such codebases with strict-mode warnings.

### Annotation grammar versioning

The `@lint.effect` grammar will evolve. A new tier (beyond
`transactional_idempotent`) or a new annotation must not silently
change the interpretation of existing annotations. The grammar is
versioned via configuration:

```yaml
# .swift-idempotency.yml
grammar_version: 1
```

Unrecognised annotations against a pinned grammar version are a
warning (`unknownAnnotationVersion`), not an error — a newer linter
reading an older project should be lenient. A newer annotation used
against a pinned older grammar is flagged so teams see when they're
reaching for a feature that isn't available under their current pin.

### Generated code

Code produced by Sourcery, Swift macros (including `@Idempotent`
itself), or protobuf code generators typically has no hand-written
doc comments. Two mechanisms support annotation on generated code:

1. **Generator-side annotation injection** — the generator's template
   emits `/// @lint.effect` comments based on the source
   specification. Preferred for team-owned generators.
2. **Symbol-level project annotation** — an `Assumptions.swift`-style
   file declares effects for generated symbols that cannot be
   modified at generation time. Fallback for third-party generated
   code.

Generated files may be excluded wholesale via
`// swift-idempotency:disable-file` or via project configuration
(`exclude_paths: [Generated/**]`), at the cost of losing cross-file
propagation into those files.

### Strict mode default for unannotated functions

In non-strict mode, an unannotated function is treated as `unknown`
— no diagnostic unless it participates in a conflict elsewhere. In
strict mode, all functions with observable side effects (detected
heuristically) must carry an annotation; missing annotations are a
warning. The recommended migration path:

1. Enable the linter in non-strict mode.
2. Get to green.
3. Annotate progressively as you encounter functions whose
   contracts you care about.
4. Flip strict mode on once coverage is acceptable.

Per-directory strict-mode configuration supports the common case of
"strict in the new domain module, lenient in legacy code."

### Project configuration shape

```yaml
# .swift-idempotency.yml
grammar_version: 1
strict_mode: false
exclude_paths:
  - Generated/**
  - Vendor/**
strict_paths:
  - Sources/Domain/**
known_retry_wrappers:
  - retry
  - withRetry
  - retryable
  - ledger.withTransaction
known_transaction_openers:
  - db.transaction
  - db.withTransaction
  - Connection.transaction
```

The package itself does not consume this configuration —
SwiftProjectLint does. Adopters using only this package's macros
without the linter don't need a config file.

---

## `SwiftIdempotency`

### `IdempotencyKey`

```swift
public struct IdempotencyKey: Hashable, Sendable, Codable, CustomStringConvertible
```

A deduplication key for externally-idempotent operations (Stripe
charges, Mailgun deliveries, SNS publishes, and similar APIs accepting
a client-provided idempotency token).

The struct's purpose is to make "passing a per-invocation generator
where a stable key is required" a *type error*. The type has
deliberately limited construction paths.

#### Properties

```swift
public let rawValue: String
```

The underlying string representation. Stable across retries by
construction.

#### Initialisers

```swift
public init<E: Identifiable>(fromEntity entity: E)
    where E.ID: CustomStringConvertible
```

Construct from an `Identifiable` whose `id` is `CustomStringConvertible`.
Intended for entities with durable identifiers — database primary keys,
webhook event IDs, upstream request IDs.

The label is `fromEntity` (not `from`) to avoid colliding with
`Codable`'s `init(from decoder: Decoder)` at call sites — the collision
was observed during round-7 validation when a consumer's
`IdempotencyKey(from: gift)` resolved to the Codable initialiser and
emitted "Gift does not conform to Decoder."

```swift
public init(fromAuditedString source: String)
```

Construct from a string the caller has *audited* as stable across
retries. The explicit label signals "I checked this" — use only when
no `Identifiable` entity is available. If you reach for this often,
consider introducing a typed ID wrapper for the domain concept.

#### Conformances

- `Hashable` — deduplicate keys in sets and dictionaries.
- `Sendable` — safe across actor / isolation boundaries.
- `Codable` — round-trips through JSON, webhook payloads, persistence.
  Serialised representation is the raw string; no wrapper.
- `CustomStringConvertible` — `description` is `rawValue`.

#### Deliberately not provided

- `init()` — cannot conjure a key from nothing.
- `init(_ uuid: UUID)` — UUID is per-invocation.
- `init(_ date: Date)` — same.
- `ExpressibleByStringLiteral` — would allow bare `"key-123"` and
  circumvent the audit signal.

#### Example

```swift
let event = WebhookEvent(id: "evt_abc123")
let key = IdempotencyKey(fromEntity: event)
// key.rawValue == "evt_abc123"

let manualKey = IdempotencyKey(fromAuditedString: "stripe-charge-2026-q2")
// manualKey.rawValue == "stripe-charge-2026-q2"
```

---

### `@Idempotent`

```swift
@attached(peer)
public macro Idempotent()
```

Marker attribute. Declares that re-invoking the function with the same
arguments produces the same observable result and no additional
effects. Equivalent to the doc-comment form `/// @lint.effect idempotent`.

Marker-only at runtime: the macro expands to nothing. SwiftProjectLint
reads it; without the linter, the attribute is documentation.

Test generation (when paired with `@IdempotencyTests` on the enclosing
suite type) is keyed off this marker.

#### Example

```swift
@Idempotent
func upsertUser(id: UserID, data: UserData) throws { /* ... */ }
```

---

### `@NonIdempotent`

```swift
@attached(peer)
public macro NonIdempotent()
```

Marker attribute. Declares that re-invoking produces additional
observable effects (sending email, inserting rows, publishing events).
Equivalent to `/// @lint.effect non_idempotent`.

#### Example

```swift
@NonIdempotent
func sendWelcomeEmail(to user: User) async throws { /* ... */ }
```

---

### `@Observational`

```swift
@attached(peer)
public macro Observational()
```

Marker attribute. Declares that the function's only side effects are
observation primitives (logger calls, metrics emission, span creation)
that are retry-safe by convention. Equivalent to
`/// @lint.effect observational`.

Observational functions may be called freely from
`@lint.context replayable` / `retry_safe` bodies without producing
idempotency diagnostics.

#### Example

```swift
@Observational
func logAudit(_ event: AuditEvent) { /* ... */ }
```

---

### `@ExternallyIdempotent(by:)`

```swift
@attached(peer)
public macro ExternallyIdempotent(by keyParameterName: String = "")
```

Marker attribute. Declares that the function is idempotent *only when*
routed through a caller-supplied dedup key, named by `keyParameterName`.
Equivalent to `/// @lint.effect externally_idempotent(by: <name>)`.

#### Parameters

- `keyParameterName` — the *external* parameter label as written in the
  function signature. When provided, SwiftProjectLint's
  `missingIdempotencyKey` rule verifies call sites pass a stable value
  at that parameter (rejecting `UUID()` / `Date()` per-invocation
  generators). When omitted (`@ExternallyIdempotent()`), the annotation
  still grants lattice trust but no key-routing verification is
  performed.

#### Constraints

- The `by:` argument must reference a real top-level parameter on the
  function. Dotted-path forms (`by: "envelope.messageId"`) are rejected
  at macro-expansion time.

#### Example

```swift
@ExternallyIdempotent(by: "idempotencyKey")
func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) async throws { /* ... */ }
```

---

### `@IdempotencyTests`

```swift
@attached(extension, names: arbitrary)
public macro IdempotencyTests()
```

Extension macro attached to a `@Suite` type. Scans the type's members
for `@Idempotent`-marked **zero-argument** functions and emits one
`@Test` method per match in a generated extension.

#### Constraints

- Only zero-argument members are eligible. Parameterised functions are
  ignored — use `#assertIdempotent` at test sites instead.
- The expansion is effect-aware: `try` and `await` appear at the call
  site only when the target's signature requires them.

#### Generated test shape

For each eligible member `foo`, the macro generates:

```swift
@Test func testIdempotencyOfFoo() async throws {
    let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
        foo()  // or `try foo()`, or `await foo()`, etc., per the target's effects.
    }
    #expect(first == second)
}
```

#### Example

```swift
@Suite
@IdempotencyTests
struct MaintenanceChecks {
    @Idempotent
    func currentSystemStatus() -> Int { 200 }

    @Idempotent
    func flushCaches() async throws { /* ... */ }
}
```

The generated extension contains
`testIdempotencyOfCurrentSystemStatus()` and
`testIdempotencyOfFlushCaches()`.

---

### `#assertIdempotent`

```swift
@freestanding(expression)
public macro assertIdempotent<Result: Equatable>(
    _ body: () throws -> Result
) -> Result

@freestanding(expression)
public macro assertIdempotent<Result: Equatable>(
    _ body: () async throws -> Result
) -> Result
```

Freestanding expression macro. Invokes `body` twice with the same
lexical bindings, asserts the two return values are equal via
`Equatable`, and returns the first invocation's result.

#### Overload selection

Two overloads coexist — sync (`() throws -> Result`) and async
(`() async throws -> Result`). Swift's overload resolution picks the
sync signature when the closure has no `await`, and the async
signature when it does. Adopters get the right behaviour without
choosing explicitly; the only visible difference is `try await` vs
`try` at the macro call site.

#### Failure mode

On mismatch, calls `Swift.precondition` with the message:

```
#assertIdempotent: closure returned different values on re-invocation — not idempotent
```

This aborts the process. To report without aborting, wrap in
`withKnownIssue` (Swift Testing) or use the alternative
`assertIdempotentEffects(failureMode: .issueRecord)` for effect
observation.

#### Constraints

- `Result` must conform to `Equatable`. Tuples do **not** satisfy this
  even when their elements are `Equatable` — Swift's tuple-`==`
  synthesis is not the same as protocol conformance. Project to a
  named struct.
- The closure's return type must be a value type whose `Equatable`
  is meaningful for idempotency. Raw bytes (`Data` of JSON output) are
  unstable across encodings — decode first.

#### Example

```swift
// Sync overload selected — no await in body.
@Test func chargeIsIdempotent() throws {
    let event = StripeEvent(id: "evt_abc123")
    let result = try #assertIdempotent {
        try processPayment(for: event)
    }
    #expect(result.status == .succeeded)
}

// Async overload selected — await in body.
@Test func webhookIsIdempotent() async throws {
    let payload = WebhookPayload(eventId: "evt_abc123", amount: 250)
    let result = try await #assertIdempotent {
        try await handleWebhook(payload: payload, store: store)
    }
    #expect(result.status == "succeeded")
}
```

---

### `IdempotentEffectRecorder`

```swift
public protocol IdempotentEffectRecorder: AnyObject {
    associatedtype Snapshot: Equatable = Int
    var effectCount: Int { get }
    func snapshot() -> Snapshot
}

extension IdempotentEffectRecorder where Snapshot == Int {
    public func snapshot() -> Int { effectCount }
}
```

A test-only protocol for recorders that observe side-effecting
operations during a test run. Test doubles (mock repositories, mock
HTTP clients, mock mail senders) conform and increment `effectCount`
on every observable mutation / write / network-send.

#### Why `AnyObject`

Class conformance is required because effect-count state must survive
closure captures by reference; struct conformance would lose updates
across closure boundaries.

#### Why this lives in `SwiftIdempotency`, not test support

Production mocks — observability shims, retry instrumentation — can
conform without forcing a `SwiftIdempotencyTestSupport` dependency
into production code. Only `assertIdempotentEffects` lives in the
test-support library.

#### Requirements

- `effectCount: Int` — count of state-changing operations witnessed.
  Reads must NOT be counted.
- `snapshot() -> Snapshot` — `Equatable` snapshot of current state.
  When `Snapshot == Int` (the default), the protocol extension
  provides `snapshot()` returning `effectCount` automatically. Adopters
  overriding `Snapshot` with a richer type must provide their own
  implementation.

#### `Snapshot` choice

The default `Snapshot = Int` detects most non-idempotency by counting
write-like operations. Override with a richer type to detect issues
counts can't see — e.g., retries that undo-then-redo (count unchanged
but call order diverged):

```swift
final class DetailedMock: IdempotentEffectRecorder {
    typealias Snapshot = [String]          // ordered call log
    private(set) var callLog: [String] = []
    var effectCount: Int { callLog.count }
    func snapshot() -> [String] { callLog }
}
```

#### Minimal example

```swift
final class MockCoinRepo: IdempotentEffectRecorder {
    private(set) var effectCount = 0
    private(set) var puts: [CoinEntry] = []

    func putItem(_ entry: CoinEntry) async throws {
        puts.append(entry)
        effectCount += 1   // WRITE — counted.
    }

    func getItem(id: String) async throws -> CoinEntry? {
        puts.first(where: { $0.id == id })
        // READ — NOT counted.
    }
}
```

---

### `IdempotencyFailureMode`

```swift
public enum IdempotencyFailureMode: Sendable {
    case preconditionFailure
    case issueRecord
}
```

How `assertIdempotentEffects` reports a detected non-idempotency.

| Case | Behaviour |
|---|---|
| `.preconditionFailure` | Calls `Swift.preconditionFailure(_:file:line:)`. Aborts the process. Default. Matches `#assertIdempotent`'s failure mode; usable outside Swift Testing. |
| `.issueRecord` | Reports via `Testing.Issue.record(_:sourceLocation:)`. Fails the enclosing `@Test` without aborting, so failure-path tests can be exercised via `withKnownIssue { }`. Only meaningful inside a Swift Testing run. |

---

## `SwiftIdempotencyTestSupport`

Add this product to **test targets** that use
`assertIdempotentEffects`. Production code never imports it.

### `assertIdempotentEffects(recorders:failureMode:body:)`

```swift
public func assertIdempotentEffects(
    recorders: [any IdempotentEffectRecorder],
    failureMode: IdempotencyFailureMode = .preconditionFailure,
    file: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    body: () async throws -> Void
) async rethrows
```

Runs `body` twice and asserts that the second invocation produced the
same snapshot as the first on every recorder.

#### Semantics

1. Captures each recorder's baseline snapshot.
2. Runs `body` once. Captures post-first-invocation snapshots.
   (First-call snapshots are diagnostic metadata; not compared — the
   first call may legitimately produce side effects.)
3. Runs `body` a second time. Captures post-second-invocation
   snapshots.
4. For each recorder, asserts post-first equals post-second.

When any recorder's snapshot changes across the second invocation, the
helper fires according to `failureMode`.

#### Parameters

- `recorders` — array of mocks conforming to `IdempotentEffectRecorder`.
  An empty array is allowed (useful for adopter code with no
  instrumentable effects), but in that case the helper is closer to a
  smoke test than an idempotency check.
- `failureMode` — see [`IdempotencyFailureMode`](#idempotencyfailuremode).
  Defaults to `.preconditionFailure`.
- `file`, `filePath`, `line`, `column` — caller source location, used
  for diagnostics. Defaults capture the call site.
- `body` — the handler invocation under test. Captures inputs from the
  enclosing scope.

#### Throwing

Rethrows any error `body` throws. If the second invocation throws but
the first didn't, that's itself a form of non-idempotency; the helper
does not intercept — the adopter's test framework reports it directly.

#### Diagnostic on failure

```
assertIdempotentEffects: handler is not idempotent.

Recorder <RecorderType> snapshot changed across the second invocation.
    baseline (pre-body):        <baseline-snapshot>
    after first invocation:     <after-first-snapshot>
    after second invocation:    <after-second-snapshot>

The second invocation must be a no-op relative to the first.
```

#### Example

```swift
@Test("addUser is idempotent when keyed on the request id")
func addUserIsIdempotent() async throws {
    let coinRepo = MockCoinRepo()
    let userRepo = MockUserRepo()
    let handler = UsersHandler(coinRepo: coinRepo, userRepo: userRepo)
    let request = UserRequest(id: "req-42", amount: 10)

    try await assertIdempotentEffects(
        recorders: [coinRepo, userRepo]
    ) {
        _ = try await handler.handleAddUser(entry: request)
    }
}
```

---

## `SwiftIdempotencyFluent`

Add this product when integrating with Vapor's Fluent ORM. Pulls in
`vapor/fluent-kit`; non-Fluent adopters should not depend on it.

### `IdempotencyKey.init(fromFluentModel:)`

```swift
public extension IdempotencyKey {
    init<M: Model>(fromFluentModel model: M) throws
        where M.IDValue: CustomStringConvertible
}
```

Construct an `IdempotencyKey` from a Fluent `Model`'s primary key.
Routes through `model.requireID()` to surface the pre-save state as a
clean Swift error rather than a force-unwrap crash.

#### Constraint

`M.IDValue: CustomStringConvertible` — `UUID`, `Int`, `String`, and
typed wrappers around those satisfy this. Models using `@CompositeID`
have a custom struct `IDValue` that typically does not conform; they
are rejected at compile time. For composite-keyed models, route
through `init(fromAuditedString:)` on a manually-composed string.

#### Throws

`FluentError.idRequired` when `model.id` is `nil` (pre-save state).
This is the same error `model.requireID()` throws, which the
initializer delegates to.

#### Why a separate initializer

The generic `init(fromEntity:)` is unreachable for Fluent `Model`
types: Fluent's `Model` does not inherit `Identifiable`, and `Model.id`
is `IDValue?` (Optional) — the `E.ID: CustomStringConvertible`
constraint on the generic init rejects the Optional wrap. This
specialised initializer takes a `Model` directly and routes through
FluentKit's primitives.

#### Example

```swift
import FluentKit
import SwiftIdempotency
import SwiftIdempotencyFluent

final class Acronym: Model {
    static let schema = "acronyms"
    @ID(key: .id) var id: UUID?
    @Field(key: "short") var short: String
    init() {}
}

func updateAcronym(_ acronym: Acronym) async throws {
    // Post-save: acronym.id is non-nil.
    let key = try IdempotencyKey(fromFluentModel: acronym)
    try await externalService.request(idempotencyKey: key)
}
```

#### Create-handler caveat

This initializer does **not** solve the create-handler bootstrap
problem — before the first save, `model.id` is `nil` and the init
throws. For create handlers, use `init(fromAuditedString:)` over a
client-supplied `Idempotency-Key` header or a stable business key.

---

## Compiler plugin

The macro implementations live in the `SwiftIdempotencyMacros` target
(macro plugin). Adopters never import this directly — the Swift
compiler loads it automatically when expanding macros declared in the
public `SwiftIdempotency` library.

The plugin currently exports:

- `IdempotentMacro` — backs `@Idempotent`.
- `NonIdempotentMacro` — backs `@NonIdempotent`.
- `ObservationalMacro` — backs `@Observational`.
- `ExternallyIdempotentMacro` — backs `@ExternallyIdempotent(by:)`.
- `IdempotencyTestsMacro` — backs `@IdempotencyTests`.
- `AssertIdempotentMacro` — backs the sync `#assertIdempotent`.
- `AssertIdempotentAsyncMacro` — backs the async `#assertIdempotent`.

If a future macro is added, its `#externalMacro(...)` declaration in
the public library will reference its plugin type by name.

---

## Underscored helpers

Public symbols prefixed with `__` (double underscore) are **macro
implementation details**, not adopter API. They live in the public
library so the macro expansions can reach them without requiring a
second library dependency. Adopter code should not call them directly.

```swift
@inlinable
public func __idempotencyAssertRunTwice<Result: Equatable>(
    _ body: () throws -> Result,
    file: StaticString = #file,
    line: UInt = #line
) rethrows -> Result
```

Backs the sync `#assertIdempotent`. Runs `body` twice, compares with
`==`, calls `precondition` on mismatch, returns the first result.

```swift
@inlinable
public func __idempotencyAssertRunTwiceAsync<Result: Equatable>(
    _ body: () async throws -> Result,
    file: StaticString = #file,
    line: UInt = #line
) async rethrows -> Result
```

Async counterpart of the above.

```swift
@inlinable
public func __idempotencyInvokeTwice<Result: Equatable>(
    _ body: () async throws -> Result
) async rethrows -> (Result, Result)
```

Backs `@IdempotencyTests`. Runs `body` twice and returns both results
as a tuple. The generated `@Test` then `#expect`s `first == second`.
The `async rethrows` signature lets sync, async, throwing, and
non-throwing closures all flow through; Swift's implicit conversions
absorb the effect polymorphism.

### `@_spi(Internals)` SPI

`SwiftIdempotency` exposes a small SPI surface
(`@_spi(Internals)`-marked) consumed only by `SwiftIdempotencyTestSupport`:

- `_IdempotencySnapshotBox` — type-erased snapshot box.
- `IdempotentEffectRecorder._snapshotBox()` — captures the current
  snapshot into a box.

These are **not** part of the public API. Adopter code must not
`@_spi(Internals)` import the library to reach them — the SPI is
specifically the `assertIdempotentEffects` integration boundary.

---

## Platform and tooling requirements

| Requirement | Version |
|---|---|
| Swift tools | 5.10+ |
| swift-syntax | `602.0.0..<604.0.0` (transitively, via the macro plugin) |
| Platforms | macOS 13+, iOS 16+, tvOS 16+, watchOS 9+ |
| Swift Testing | Required for `@Test`-based generation (`@IdempotencyTests`) and for `IdempotencyFailureMode.issueRecord`. |
| FluentKit | `1.48.0+` (only for `SwiftIdempotencyFluent`) |

The swift-syntax range matters because adopters who transitively
require swift-syntax 603+ (e.g., via DiscordBM's `@UnstableEnum`) need
SwiftIdempotency to allow that range. The upper bound stays exclusive
of 604 until verified on that version.

---

## Deferred and not-shipped features

This package implements a subset of the original PRD design. This
section consolidates everything that was proposed but didn't ship,
or shipped in a different shape than originally specified — useful
if you read the PRD and wondered why a particular surface isn't
here, or what to use instead.

### Macro test generation

| Proposed | Status | Shipped instead |
|---|---|---|
| `IdempotencyTestable` protocol with `captureIdempotencyState()` | ❌ Not shipped | `IdempotentEffectRecorder` with per-recorder `Snapshot` associatedtype |
| Tier 3 — auto-generated stub with TODO placeholders | ❌ Deliberately not shipped | `@IdempotencyTests` declines to generate anything for parameterised members; adopters use `#assertIdempotent` or `assertIdempotentEffects` at explicit test sites |
| `#assertIdempotent(capturing: { ... }) { ... }` form | ❌ Not shipped | `assertIdempotentEffects(recorders:body:)` as a separate helper |
| Parameterised `@IdempotencyTests` expansion | ⏳ Deferred | Use `#assertIdempotent` inside a parameterised `@Test`; needs an `IdempotencyTestArgs` protocol design |
| Property-based test expansion via `IdempotencyTestInputProvider` | ⏳ Deferred | Manual parameterised tests; `swift-property-based` is used in this package's own tests for `IdempotencyKey` constructor coverage but is not exposed to adopters |
| Auto-injection of effect recorders into `@IdempotencyTests` generation | ⏳ Deferred | Adopters add `assertIdempotentEffects` at explicit test sites |

### Protocol-based type safety

| Proposed | Status | Shipped instead |
|---|---|---|
| `IdempotentOperation` / `NonIdempotentOperation` marker protocols | ❌ Not shipped | `@Idempotent` / `@NonIdempotent` attribute macros on declarations |
| Operation-object protocol with `execute(_:)` | ❌ Not shipped | (no protocol surface — adopters keep their existing function shapes) |
| `Idempotent<I, O>` / `NonIdempotent<I, O>` effect-tagged value wrappers | ❌ Not shipped | (no value-level wrapper — function declarations carry the marker) |
| `@unchecked IdempotentOperation` escape hatch | ❌ Not shipped | `@ExternallyIdempotent(by:)` for the equivalent "asserted, not body-verified" case |
| `IdempotencyKeySource` protocol | ❌ Not shipped | `IdempotencyKey.init(fromEntity:)` constraints on `Identifiable` directly |
| Effect annotations on protocol method requirements | ❌ Not shipped | (would require linter-side `protocolWitnessWeakerEffect` rule that isn't in current SwiftProjectLint) |

See [Protocol-based type safety: design alternatives](#protocol-based-type-safety-design-alternatives)
above for the rationale on each.

### Lattice tiers and grammar — doc-comment-only (no macro counterpart)

These exist in the SwiftProjectLint grammar but have no macro form
in this package. Adopters who want them must use the doc-comment
form and rely on the linter to read them.

| Doc-comment form | Why no macro |
|---|---|
| `/// @lint.effect transactional_idempotent` | Macro can't verify the transaction-boundary requirement |
| `/// @lint.effect idempotent(by: <param>)` | Intrinsic-idempotent scoping; the macro counterpart `@ExternallyIdempotent(by:)` is the *externally*-idempotent variant (different lattice tier) |
| `/// @lint.context replayable` (and `retry_safe`, `strict_replayable`, `once`, `dedup_guarded`) | Context annotations describe execution context, not function effect — see [Context annotations](#context-annotations) |
| `/// @lint.assume <symbol> is <effect>` | Project-wide assumption ledger; needs linter-side symbol-table integration |
| `/// @lint.unsafe reason: "..."` | Semantic escape hatch for individual function bodies |
| `/// @lint.requires idempotency_key` | Enforced via linter-side regex matching on parameter labels |
| `/// @lint.param body requires <effect>` | Closure-argument effect requirement; needs linter-side flow analysis |
| `/// @lint.txn_boundary <identifier>` | Names the transaction opener for `transactional_idempotent` body analysis |

### Linter-side rules that depend on un-shipped features

These rules from the PRD's design require shipped features the
package doesn't yet provide:

| Rule | Blocked by |
|---|---|
| `protocolWitnessWeakerEffect` | No protocol-based modelling shipped |
| `protocolRequirementUnannotated` | Same |

### Out of scope by design

These were considered and explicitly rejected for the package
surface:

- **Production-runtime instrumentation.** Macros cannot inject into
  every call site silently. Runtime safety is covered by
  compile-time (types), test-time (generated / explicit tests), and
  lint-time (SwiftProjectLint rules) — not production AOP.
- **Auto-generated mocks or dependency injection.** The test that
  `@IdempotencyTests` generates calls the target literally twice.
  If the function touches the filesystem or a real database, the
  adopter is responsible for test isolation.
- **Dynamic equivalence checking by default.** `#assertIdempotent`
  uses Option C semantics (return-value equality). Effect
  observation is opt-in via `IdempotentEffectRecorder` +
  `assertIdempotentEffects` — handlers without instrumented mocks
  still pass `#assertIdempotent` even when their side effects
  diverge.

### Framework integrations beyond Fluent

`SwiftIdempotencyFluent` ships as the only framework-specific
opt-in product (provides `IdempotencyKey.init(fromFluentModel:)`).
Hummingbird, SwiftNIO, and other framework-specific integrations
would follow the same opt-in product pattern but haven't shipped.
Adopters using those frameworks today route through
`init(fromAuditedString:)` on a stable header / business key
(see [USER_GUIDE.md §Integrating with Vapor and Hummingbird](USER_GUIDE.md#integrating-with-vapor-and-hummingbird)).

---

## Q&A: addressing common critiques

These questions reflect critiques raised during review of the
original design. Most concern decisions that are already resolved in
the body above; they are answered here to prevent re-litigation.

**Q: Isn't binary classification (idempotent / not) too limiting for
real systems? What about idempotency per key, or within a time
window?**

The effect lattice is not binary. It has seven positions: `pure`,
`idempotent`, `observational`, `transactional_idempotent`,
`externallyIdempotent`, `non_idempotent`, and `unknown`. Scoped
idempotency (`idempotent(by: requestID)`) is part of the annotation
grammar and enforces that the scoping parameter is stable across
retry iterations. Key-based idempotency is separately modelled as
`externallyIdempotent`, with its own annotation
(`@ExternallyIdempotent(by:)` macro form;
`/// @lint.effect externally_idempotent reason: "..."` doc-comment
form) and enforcement rules that differ from intrinsic `idempotent`.
Telemetry / observation side effects (logger, metrics, tracing) have
their own position, `observational`, so they neither lie about being
`idempotent` nor flood retry contexts as `non_idempotent`.
Time-windowed or conditionally idempotent operations remain a gap —
they fall under `unknown` with `@lint.assume` or
`@lint.unsafe reason:` as the escape hatches.

**Q: Static analysis will always hit a ceiling — the linter can't
know about database constraints, external API guarantees, etc.**

Correct, and the design accounts for this explicitly. The static
body check is one layer of four. For operations where the
idempotency guarantee lives outside the function body,
`/// @lint.context dedup_guarded` suppresses the body check and
replaces it with a mechanism check (presence of an `IdempotencyKey`
parameter, a deduplication guard, or an explicit
`@lint.unsafe reason:`). `@lint.assume db.upsert is idempotent`-style
declarations cover third-party boundaries. The point of the static
layer is not complete verification — it's catching violations that
*are* locally visible, which is a significant subset of real bugs.
The runtime layer (`#assertIdempotent` / `assertIdempotentEffects`)
handles a complementary subset — bugs that surface only when the
function actually runs.

**Q: Macro-generated tests aren't strong enough — they don't catch
race conditions or distributed retries.**

Agreed. The macro tier is positioned as a heuristic that catches
the simplest class of idempotency violations: a function whose
return value differs on the second call (`#assertIdempotent`), or a
recorder whose snapshot differs on the second call
(`assertIdempotentEffects`). It is not a proof of idempotency. The
value proposition is *zero-cost test scaffolding that catches
obvious violations and makes the intent reviewable*, not exhaustive
verification. Concurrency and distributed-system testing require
purpose-built harnesses that are out of scope for a peer macro.

**Q: The type-level modelling is underdeveloped — shouldn't
protocols be a more central abstraction?**

The package considered three protocol patterns (marker, operation
object, effect-tagged wrapper), conditional conformance, the
`@unchecked` escape hatch, and an explicit trade-off table comparing
protocols to attribute / annotation forms. The conclusion is that
both are needed: protocols for new code structured around operation
objects where compile-time generic constraints are worth the
architectural buy-in; attributes and annotations for existing APIs
and free functions where structural change is not feasible. Making
protocols the *core* abstraction would require restructuring
existing codebases, which contradicts the incremental-adoption
constraint. The shipped package combines a strong type
(`IdempotencyKey` for parameter-level enforcement) with attribute
markers (`@Idempotent` etc. for declaration-level claims), getting
most of the protocol-route compile-time guarantee at the parameter
boundary without the architectural cost.

**Q: Concurrency integration is missing.**

See the [Swift concurrency interactions](#swift-concurrency-interactions)
section: actors don't imply idempotency; actor reentrancy breaks
check-then-act patterns (with a detectable rule and a fix pattern);
five additional async retry patterns (`Task { }` in a loop,
`withThrowingTaskGroup`, recursive async retry, SwiftUI `.task {}`,
at-least-once `AsyncSequence`); and how `effectSpecifiers`
propagate into generated test peers. The
`actorReentrancyIdempotencyHazard` rule is the concurrency section's
most original contribution — both detectable with SwiftSyntax and
absent from existing linting tools.

---

## Related work

This package and the SwiftProjectLint rules that consume it sit in a
crowded field of effect systems, purity annotations, and retry
framework conventions. A short survey situates the design.

**Koka (Microsoft Research)** formalises effects as a first-class
part of the type system. A function's type includes its effect row —
`io`, `exn`, `div`, user-defined — and the compiler verifies effect
composition. Koka is the closest academic ancestor of the effect
lattice. The trade-off is stark: Koka's system is total and
provable at the cost of requiring the language itself to support it.
SwiftProjectLint cannot change Swift's type system, so this package
re-uses Koka's intuition (effects as a lattice, composition rules,
conservative handling of unknown) in a layered form compatible with
existing Swift.

**Java's `@Idempotent` annotations** exist in several ecosystems —
Spring, MicroProfile Fault Tolerance, Resilience4j, JAX-RS. Most are
*runtime* annotations: they configure retry middleware rather than
feed a static checker. Spring's `@Retryable` marks a method for the
retry infrastructure; Resilience4j's `@Retry` does the same. None of
these verify that the method body is actually idempotent. The Swift
contribution here is treating the annotation as a *verifiable claim*
rather than a *runtime configuration directive*.

**Rust's effect discussion** centres on `const fn` (compile-time-
evaluable functions) and `unsafe fn` (functions with memory-safety
preconditions). Both are properties the compiler enforces, both
explicit about the escape hatch (`const fn` with runtime-only calls
is rejected; `unsafe` blocks are explicit and reviewable). The Rust
community has repeatedly discussed effect systems for purity, async
context, and "no-panic" — none have shipped. The lesson taken:
explicit effect declarations are more socially durable than inferred
effects, even when inference is technically possible.

**Haskell's IO monad** is the canonical example of effect tracking.
Every side-effecting computation has type `IO a`; the type system
prevents pure code from calling into effectful code without
acknowledgment. Same trade-off as Koka — total correctness at the
cost of structural demands on the language. Haskell's experience
also shows the limit: `IO` says "there is a side effect," not "this
side effect is idempotent." Finer-grained distinctions require
additional structure. This is why the lattice has five positions
rather than a binary pure/impure split.

**SwiftLint's custom rules** are the closest existing tooling in
the Swift ecosystem. They are pattern-based (regex, syntax matches)
rather than effect-based — a SwiftLint rule can flag "any call to
`UUID()` inside a function named `create*`" but cannot reason about
call graphs or composition. SwiftProjectLint's idempotency rules
are deliberately a layer above what SwiftLint can express, which is
why they ship there rather than as SwiftLint rules.

**Akka's at-least-once delivery** and **Kafka Streams' exactly-once
semantics** are distributed-systems frameworks that *make*
idempotency the responsibility of the application developer,
typically with helper APIs for deduplication keys and processed-ID
tracking. The `@lint.context replayable` annotation is the
static-analysis counterpart to the implicit "your handler had
better be idempotent" contract these frameworks impose.

---

## What's novel here

The Related work section above identifies prior systems that
overlap. This section walks through the specific contributions that
don't have direct equivalents, with the prior-art context for each.

### (a) Doc-comment annotations as the human/tooling interoperability surface

**What already exists.** Effect information is typically carried in
one of three places:

- *The type system itself* (Koka effect rows, Haskell's `IO`,
  Rust `async`/`unsafe`/`const`). Strong guarantees, but requires
  the language to cooperate.
- *Attributes/annotations tied to a framework* (Java's `@Retryable`,
  Spring's `@Idempotent`, JAX-RS, Resilience4j). These are runtime
  configuration directives — they tell the retry framework what to
  do, not the compiler or a checker what to verify.
- *Linter-specific DSLs* (SwiftLint custom rules, ESLint config,
  CodeQL queries). These live in tool-owned files, not the source;
  a human reading the function cannot see the claim.

**What this contribution adds.** It treats the Swift doc-comment
grammar (`/// @lint.effect idempotent`, `/// @lint.context replayable`,
`/// @lint.assume ...`) as a *shared surface* with three consumers
reading the same token:

1. The **human reviewer** reads the doc comment during code review.
   The claim is adjacent to the function signature, gets
   copy-pasted in PR descriptions, and renders in DocC.
2. The **linter** parses the same comment into structured effects
   and runs the body / call-graph checks described in the lattice
   section.
3. The **macro** (`@Idempotent`, `@IdempotencyTests`) reads the same
   annotation to decide whether to synthesise a double-call test
   peer, what equivalence check to emit, and whether to mirror
   `async` / `throws` into the generated `@Test`.

The novel part isn't inventing annotations — it's positioning them
as **interoperable data** rather than configuration for one specific
tool. Every annotation is simultaneously documentation, a verifiable
claim, and test-generation input. If any of the three consumers is
missing, the annotation still has value to the remaining two. That
asymmetry is why incremental adoption works: a team can start by
*just writing the comments*, add the linter later, and add the
macros last without rewriting the source.

This also explains why protocol-only modelling was rejected. A
protocol conformance carries the same information but *only* to the
type system; the human reading `struct ChargeCard: IdempotentOperation`
has no reason clause, no equivalence relation, no `@lint.assume`
escape hatch. The doc comment carries the same machine-readable
claim *plus* the prose context a reviewer needs.

### (b) `externallyIdempotent` and `transactional_idempotent` as first-class lattice positions

**What already exists.** Most prior systems use a binary split —
pure/impure, idempotent/non-idempotent, safe-to-retry/not. When
more nuance is needed, it's pushed into the framework layer:

- Stripe, AWS SDKs, and similar clients handle idempotency-key dedup
  as an *implementation detail* of the client library. The type
  signature doesn't distinguish `chargeCard(amount:)` from
  `chargeCard(amount:idempotencyKey:)` in a way the compiler or a
  linter can reason about.
- Database transaction boundaries are enforced at runtime (the DB
  throws if you commit twice) but don't propagate upward as a
  function-level property. A function that wraps several
  non-idempotent writes in `db.transaction { … }` has no standard
  way to declare "the composite is retry-safe."
- Akka's at-least-once delivery, Kafka's exactly-once semantics, and
  AWS Lambda's SQS trigger all *require* idempotency in the handler
  but provide no type- or annotation-level way to say "this handler
  satisfies that requirement via mechanism X."

**What this contribution adds.** It promotes these two
conditionally-idempotent modes to explicit, equally-ranked positions
in the lattice:

```
pure < { idempotent, observational } < { transactional_idempotent, externallyIdempotent } < non_idempotent
                                                                                      unknown (incomparable)
```

Each carries *different enforcement rules*:

| Effect position | What the body check verifies |
|---|---|
| `idempotent` | No non-idempotent callees on any path, including throw paths |
| `observational` | No callees beyond `pure`, other `observational`, and (by `@lint.assume`) known observation primitives — body mutates no business state |
| `transactional_idempotent` | All non-idempotent writes live inside a detected `db.transaction { }` / atomic-rename / single-publish boundary; demoted if any write escapes |
| `externallyIdempotent` | Function has an `IdempotencyKey` parameter; key is stable across retries; `reason:` clause names the external mechanism |
| `non_idempotent` | No check; but caller composition rules propagate it |

These aren't cosmetic labels. The composition table has separate
rows for each, the conflict-detection table has different lint
actions for each declared/inferred pairing, and the annotation
grammar has dedicated sub-directives
(`@lint.txn_boundary db.transaction`, `@lint.assume <symbol> is
externally_idempotent`, the `IdempotencyKey` strong type).

**Why this matters.** The two most common production idempotency
patterns are:

1. "It's idempotent *because* we pass an idempotency key to the
   provider." (`externallyIdempotent`)
2. "It's idempotent *because* multiple non-idempotent writes commit
   atomically in one transaction." (`transactional_idempotent`)

A binary lattice forces both into either `idempotent` (which lies
about the body) or `non_idempotent` (which over-reports and
suppresses the retry-safety information the caller needs). The
multi-tier model captures both accurately *and* generates distinct,
actionable diagnostics:

- A `transactional_idempotent` function whose body has a write
  outside the transaction block gets a specific "write escapes
  transaction boundary" error, not a generic "body is non-idempotent."
- An `externallyIdempotent` function whose key parameter is set
  from `UUID().uuidString` in a retry loop gets "key sourced from
  fresh entropy at call site," not a generic warning.

Most prior work treats these as "library-level concerns" outside
the scope of an effect system. Treating them as type-level
distinctions is the contribution.

### (c) `actorReentrancyIdempotencyHazard` — the guard-suspend-insert rule

**What already exists.** Swift actor reentrancy is documented in
the language (SE-0306), and the general hazard is known to
concurrency experts. But no shipped linter surveyed (SwiftLint,
swift-format, the Swift compiler's own warnings, SwiftSyntax-based
third-party rules) has a rule that specifically targets the
check-then-act-across-a-suspension pattern.

**The pattern.** In an actor method:

```swift
guard !processedIDs.contains(id) else { return }   // check
try await chargeCard(id)                           // suspension point — actor reopens
processedIDs.insert(id)                            // act, too late
```

Actor isolation serialises *each individual await-free segment* of
the method, but at the `await` the actor is open to other callers.
Two concurrent callers with the same `id` both pass the guard, both
`await chargeCard`, both charge the card. The runtime won't catch
this — the actor did serialise reads; it just couldn't serialise the
check-suspend-act sequence as a unit. The usual "actors prevent
races" mental model fails silently here.

**Why this is AST-detectable.** The pattern has a precise
structural signature:

- Inside a `FunctionDeclSyntax` whose parent is an `ActorDeclSyntax`
- A `GuardStmtSyntax` whose condition contains a membership check
  against a stored property (`!self.X.contains(...)`,
  `self.X[...] == nil`)
- Followed by one or more `AwaitExprSyntax` nodes on the
  fall-through path
- Followed by an insertion into the *same* stored property
  (`self.X.insert(...)`, `self.X[...] = ...`)

SwiftSyntax has all these node types directly. The rule is a
single-pass AST traversal — no call graph, no type inference, no
cross-file analysis.

**Why this is the highest-value original rule.** The other
concurrency rules (`nonIdempotentInTaskRetry`, etc.) depend on
having classified the callee as `non_idempotent` — they are
downstream of the effect lattice. `actorReentrancyIdempotencyHazard`
is different: it fires on structural grounds alone, independent of
any annotation on `chargeCard`. That means it delivers value on day
one of enabling the linter, before any team has annotated anything.
It's also a bug pattern that very few Swift developers recognise —
actor reentrancy interacting with idempotency is subtle enough that
even careful concurrency code gets it wrong, and the bug is
invisible in single-threaded tests.

The fix pattern is as detectable as the bug pattern (claim the slot
before the suspension, compensate in `catch`), so the linter can
offer a targeted diagnostic with a concrete rewrite, not just a
warning.

### Why the combination is the contribution

Each piece has partial analogs in prior work:

- Effect annotations exist in Java-land (but as runtime config).
- Multi-tiered idempotency is discussed in distributed systems
  literature (but not as a type-level lattice).
- Actor reentrancy hazards are documented (but not mechanically
  checked).

The claim is that pulling the three together — **annotations as the
shared surface**, **a lattice rich enough to model the real
patterns**, **and at least one concurrency rule that is detectable
without the lattice** — produces a system that is adoptable
incrementally (unlike Koka), verifiable (unlike Spring's
`@Retryable`), and catches a class of bug (actor reentrancy
idempotency) that no existing Swift tool catches. None of the three
alone is the novelty; the synthesis is.
