# Penny — Package Integration Trial Scope (Option B probe)

Fifth package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
**First trial with a dual purpose**: validate v0.2.0's shipped
surface on Penny AND design the Option B API (effect-observation
based `#assertIdempotent`-complement). Option B addresses the
pathologies identified in prior trials — trivial returns
(luka-vapor's `HTTPStatus.ok`), invisible effects (email sends,
metric publishes), and non-Equatable reference returns —
that Option C (return-value equality) cannot catch.

## Research question

> **Does the Option B prototype
> (`assertIdempotentEffects(recorders:body:)` in
> `SwiftIdempotencyTestSupport`) catch Penny's known coin-double-grant
> bug shape, and what is the adopter-side refactor cost (protocol
> extraction on concrete repositories) to make the handler
> mockable?**

## Why Penny specifically

Penny is the canonical Option-B-pathology target:

- **Real-adopter status.** Linter round 6 against Penny surfaced
  four real-bug shapes (coin double-grant, OAuth error-path
  Discord noise, sponsor-welcome DM duplication, GHHooks
  error-path dup). All four fit the Option B shape —
  non-idempotent side effects behind handlers whose return value
  doesn't reveal the duplication.
- **DI-friendly at the top.** `SharedContext` already injects
  `HTTPClient` + `AWSClient` + `Logger` into `UsersHandler` et al.
  The architectural precondition for Option B (mockable side-
  effecting dependencies) is satisfied at the context level —
  but not at the repository level (repos are concrete types
  constructed inline). Protocol extraction is required to mock
  the specific non-idempotent calls.
- **Fork and linter trial already done.** Saves ~45-60 min of
  baseline-verification overhead vs. a fresh target. Fork at
  `Joseph-Cursio/penny-bot-idempotency-trial`.

## Pinned context

- **SwiftIdempotency tip:** `423548e` (prototype of
  `SwiftIdempotencyTestSupport.assertIdempotentEffects`, committed
  specifically for this trial — not in v0.2.0 tagged release).
- **Upstream target:** `vapor/penny-bot` @ `e0d2752` (main).
- **Trial fork:** `Joseph-Cursio/penny-bot-idempotency-trial`.
- **Trial branch:** `package-integration-trial`, forked from
  upstream `main` @ `e0d2752`. Separate from the
  pre-existing `trial-penny-bot` linter-trial branch.
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64. Penny declares
  `swift-tools-version:6.3` and `platforms: [.macOS(.v15)]`.

## Option B prototype design (`SwiftIdempotencyTestSupport`)

Two public symbols:

### 1. `IdempotentEffectRecorder` protocol

```swift
public protocol IdempotentEffectRecorder: AnyObject {
    var effectCount: Int { get }
}
```

Class-typed (`AnyObject`) — effect counts must survive closure
captures by reference. Minimal surface: just a count, not a full
state snapshot.

### 2. `assertIdempotentEffects` helper

```swift
public func assertIdempotentEffects(
    recorders: [any IdempotentEffectRecorder],
    file: StaticString = #fileID,
    line: UInt = #line,
    body: () async throws -> Void
) async rethrows
```

Runs `body` twice. Asserts each recorder's `effectCount` is
equal between invocations (second call must be a no-op).
Failure mode: `preconditionFailure` — matches the existing
Option C runtime helper's failure shape.

## Migration plan (test-target-only)

**No Penny source files modified.** The trial declares a minimal
`CoinEntryRepositoryProtocol` inline in the test file — this
represents what a real Penny adoption would extract from the
concrete `DynamoCoinEntryRepository`. The refactor cost is
documented in the trial-findings rather than executed.

1. Add `SwiftIdempotency` + `SwiftIdempotencyTestSupport` to
   `Tests/PennyTests/` target in `Package.swift`. Reference
   the prototype commit `423548e`.
2. New test file
   `Tests/PennyTests/OptionBIdempotencyTrialTests.swift`:
   - Minimal `CoinEntryRepositoryProtocol` + mock conforming to
     both the protocol AND `IdempotentEffectRecorder`.
   - Test 1: **bug-shape detection** — manual two-call + delta
     check demonstrating the Option B detection logic identifies
     the coin-double-grant pattern (CoinEntry.id = fresh UUID
     per construction → second call creates a distinct row).
   - Test 2: **dedup-guarded happy path** — exercises
     `assertIdempotentEffects` end-to-end on a corrected handler
     shape (in-memory dedup cache keyed on
     `IdempotencyKey(fromAuditedString:)`).

Test 1 is a **manual delta check** rather than a direct call to
`assertIdempotentEffects`, because the helper's failure path
terminates the process via `preconditionFailure`. A future
Option-B-ships variant may add a non-aborting failure mode
(`Testing.Issue.record`) to allow failure-path tests.

## Pre-committed questions

1. **Does the Option B API surface compile on Penny's test
   target?** First real-adopter integration of the prototype —
   any cross-module / Swift-Testing-version issues surface here.
2. **Does the bug shape delta check fire as expected?** Penny's
   `CoinEntry.id: UUID = UUID()` produces fresh identifiers on
   each construction. Option B's delta-check should observe
   `firstDelta == 1, secondDelta == 1` — detecting the bug.
3. **Does the dedup-gated happy-path pass?** Adopter-side
   dedup guard (IdempotencyKey → in-memory cache) should make
   `assertIdempotentEffects` pass (secondDelta == 0). Validates
   the API's happy path on an adopter-realistic shape.
4. **What's the refactor cost Penny would pay for full Option B
   adoption?** Protocol extraction on `DynamoCoinEntryRepository`
   + `DynamoUserRepository`, `InternalUsersService.init` signature
   change to accept protocol-typed repositories. Documented
   quantitatively in findings.

## Scope commitment

- **Test-target-only.** No Penny source file changes. All
  refactor costs are documented, not executed.
- **No upstream PR.** Non-contribution fork per the test plan.
- **Option B prototype = experimental.** API surface may change
  based on this trial's findings. Ship decision is Phase 4
  output.
- **Coin-double-grant shape only.** Trial doesn't exercise the
  other three Penny bug shapes (OAuth, sponsor DM, GHHooks).
  Bug-shape-coverage generalization is secondary to API-shape
  validation.

## Predicted outcome

- **Q1 (compile):** ✅ expected clean. Prototype is 80 LOC with
  no exotic deps.
- **Q2 (bug detection):** ✅ expected. `CoinEntry.id` is
  `UUID()`-defaulted; the two rows will have distinct ids.
- **Q3 (dedup happy path):** ✅ expected. `DedupCache` +
  `IdempotencyKey(fromAuditedString:)` is a minimal valid
  dedup gate; second call returns early, zero new effects.
- **Q4 (refactor cost):** two protocol extractions + one
  initializer-signature change. Estimated ~15-25 lines of
  adopter-side code per repository. Tractable for a motivated
  adopter; non-trivial enough that it's a real cost.

## What the trial decides

The trial's output is a **ship/refine/abandon recommendation**
for the Option B prototype:

- **Ship as-is:** if all four pre-committed questions pass and
  the refactor cost estimate is acceptable, stabilize the API in
  a v0.3.0 release.
- **Refine:** if the API shape feels wrong (e.g., `effectCount:
  Int` is too coarse — adopters want per-op-type counters, or
  the precondition-on-failure semantics block failure-path
  tests), iterate on the prototype and re-trial.
- **Abandon:** if the refactor cost is prohibitive or Option B
  doesn't actually catch a material set of bugs Option C
  misses, drop the prototype and document Option C's known
  pathologies as accepted limits.

## Scope boundaries — NOT in this trial

- **Other three Penny bug shapes.** OAuth error-path, sponsor
  DM, GHHooks error-path. A future Penny variant trial could
  exercise these with broader Option B coverage.
- **Full Penny refactor** (protocol extraction on repos). The
  trial measures the *cost* but doesn't pay it.
- **Option B + Option C hybrid.** Shape 3 from the earlier
  design discussion (hybrid API combining return-equality and
  effect-observation). Deferred — the pure Option B surface
  comes first; hybrid is a follow-up design slice if Option B
  ships.
- **Production-grade mock implementations.** The trial's mocks
  count calls but don't emulate the DynamoDB semantics. Full
  emulation (PutItem with ConditionExpression, etc.) is
  per-adopter work.
