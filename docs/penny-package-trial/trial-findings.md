# Penny — Package Integration Trial Findings (Option B probe)

Fifth package-adoption trial — the Option B prototype's first
real-adopter application. See [`trial-scope.md`](trial-scope.md)
for pinned context and pre-committed questions.

## Overall outcome

**2/2 tests green.** Option B prototype works end-to-end on
Penny's real `CoinEntry` Model type via a minimal inline protocol
extraction. All four pre-committed questions answered positively.

**Trial-fork commit:** [`Joseph-Cursio/penny-bot-idempotency-trial@c121ced`](https://github.com/Joseph-Cursio/penny-bot-idempotency-trial/commit/c121ced)
on `package-integration-trial`. SwiftIdempotency dep pinned at
`bfcad8c` (Option B prototype + SwiftLint cleanup).

## Test outcome

| Test | Duration | Verdict |
|---|---|---|
| `bugShapeIsDetectable` — manual two-call + delta check on the coin-double-grant pattern | 0.001s | ✅ pass |
| `dedupGuardedHandlerPassesOptionB` — full `assertIdempotentEffects` call on a dedup-guarded handler shape | 0.001s | ✅ pass |

Build wall-clock:

- Initial PennyTests build (fresh derived-data, SwiftIdempotency
  deps resolved + compiled): **~58s** (2138 compile units).
- Incremental test-run after source edit: **26.8s** rebuild +
  <1s test execution.

Penny's dep graph is large (DiscordBM, Soto, swift-openapi,
FluentKit, SwiftNIO, ~40 packages). SwiftIdempotency +
SwiftIdempotencyTestSupport add ~6 compile units on top — a
~0.3% overhead.

## Pre-committed questions — answers

### 1. Does the Option B API surface compile on Penny's test target?

**Yes.** After adding `SwiftIdempotency` + `SwiftIdempotencyTestSupport`
products to the `PennyTests` target dependencies, the import
resolved cleanly on first build attempt (modulo one trivial fix —
see "API friction" below). The prototype's module graph
(SwiftIdempotencyMacros → SwiftIdempotency → SwiftIdempotencyTestSupport)
slotted into Penny's existing graph without version conflicts.

### 2. Does the bug shape delta check fire as expected?

**Yes.** The `bugShapeIsDetectable` test reproduces the
coin-double-grant pattern exactly:

```swift
let baseline = coinRepo.effectCount       // 0
try await addCoinEntry(...)                // first call
let afterFirst = coinRepo.effectCount     // 1
try await addCoinEntry(...)                // retry
let afterSecond = coinRepo.effectCount    // 2 — BUG

#expect(firstDelta == 1)
#expect(secondDelta == 1)  // ← the bug: retry did new work
#expect(coinRepo.entries[0].id != coinRepo.entries[1].id)  // two distinct rows
```

The delta inspection reveals exactly the shape `assertIdempotentEffects`
would flag: second invocation produced a non-zero effect count
delta. Confirms the detection logic is sound on real adopter data.

**Manual delta rather than a direct `assertIdempotentEffects` call**
because the helper's failure path terminates the test process via
`preconditionFailure`. This is a known design limitation
documented in the retrospective — shipping Option B likely wants a
`Testing.Issue.record`-based variant that fails the test without
aborting the process.

### 3. Does the dedup-gated happy-path pass?

**Yes.** The `dedupGuardedHandlerPassesOptionB` test wraps a
`DedupCache` around the handler call, keyed on
`IdempotencyKey(fromAuditedString: "client-req-42")`. First
invocation: gate claimed, `coinRepo.effectCount` → 1. Second
invocation: gate already taken, early return, `effectCount`
stays at 1. `assertIdempotentEffects` sees a `secondDelta == 0`
and returns cleanly.

This is the **adopter-realistic fix shape**: the dedup cache
stands in for whatever production dedup mechanism the adopter
would use (DynamoDB conditional-put + PK = idempotency-key,
Redis SETNX + TTL, request-deduplication middleware, etc.). The
API doesn't care about the cache's implementation; it cares
about the observable property (zero new effects on retry).

### 4. Refactor cost quantified

**Measured against Penny's current architecture** (no refactor
executed):

| Adopter-side change | LOC estimate | Notes |
|---|---|---|
| Extract `CoinEntryRepositoryProtocol` | ~3-5 | Just the `createCoinEntry(_:)` signature |
| `DynamoCoinEntryRepository: CoinEntryRepositoryProtocol` conformance | 0 (already conforms structurally) | Add `protocol` conformance annotation |
| Extract `UserRepositoryProtocol` | ~6-8 | More methods: get/create/update |
| `InternalUsersService.init` signature change | ~5 diff | accept protocol-typed deps |
| Mock implementations in test target | ~20-30 | Shared with other test suites |

**Total: ~35-50 LOC of adopter-side code** (~20 LOC diff on
existing files + ~15-30 LOC new mock implementations, reusable
across tests). A real Penny migration is **tractable** — not a
week-long refactor, not a 30-minute polish either. Fair mid-
weight refactor.

The trial did NOT execute this refactor (test-target-only scope);
the estimate comes from reading the source carefully. An actual
Penny PR would surface additional friction the estimate misses
(migration conflicts with in-flight branches, CI configuration,
internal consumer impact, etc.).

## API friction log

### Finding 1 — `Foundation` import required for `UUID`

**Evidence:** first build of `OptionBIdempotencyTrialTests.swift`
failed with five `cannot find type 'UUID' in scope` errors. Fixed
by adding the standard FoundationEssentials-preferred import:

```swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
```

**Root cause:** not SwiftIdempotency-related — my initial test
file used `UUID` in signatures without the import. Penny's own
source uses the same `FoundationEssentials` canImport pattern;
reproducing it fixed the error.

**Severity:** P3 (documentation-only). Doesn't inform Option B
design; just a reminder that adopter-test imports need the same
`Foundation` discipline as adopter source.

### Finding 2 — `preconditionFailure` vs. `Issue.record` on failure path

**Evidence:** the bug-shape detection test can't call
`assertIdempotentEffects` directly because the helper's
`preconditionFailure` would terminate the test process on
detection. The bug-shape test uses manual delta inspection
instead.

**Trade-off:**

- **`preconditionFailure` (current prototype):** matches
  existing Option C runtime helper's failure mode
  (`__idempotencyAssertRunTwice` uses precondition). Works
  outside Swift Testing context (CLI scripts, debug binaries).
  Loses the ability to test the failure path without process
  termination.
- **`Issue.record` alternative:** Swift-Testing-specific but
  integrates cleanly with the test runner — failures become
  reported issues without aborting. Breaks the
  non-Swift-Testing-context use case.

**Recommendation for ship:** offer **both** via a trait or
parameter. `assertIdempotentEffects(..., failureMode: .record)`
for Swift Testing use; `assertIdempotentEffects(...)` defaults
to `.preconditionFailure` for other contexts. See retrospective's
"API recommendations" section for the shape proposal.

### Finding 3 — effect-count granularity is coarse but sufficient

**Evidence:** the `effectCount: Int` protocol requirement is
one integer per recorder. This is coarse enough that two very
different call shapes (e.g., an email-send followed by a log-
write, vs. two email-sends) produce the same effect count and
can't be distinguished.

**Was it a problem for the Penny trial?** No. The
coin-double-grant bug is a **single-op shape** — one
`createCoinEntry` call per invocation. An `effectCount` delta
of 0 vs. 1 was sufficient to detect the bug.

**Would it matter for richer bug shapes?** Yes, potentially:
OAuth handler runs three Discord posts per failure branch —
`effectCount` deltas of 0 vs. 3 look worse than 0 vs. 1, but
both are detected as non-idempotent. Fine. Where coarseness
becomes a problem is **mixed-idempotency**: some ops idempotent
at the service layer, some not. The recorder can't distinguish
"the idempotent ones re-ran" (acceptable) from "the
non-idempotent ones re-ran" (bug) with just a count.

**Recommendation for ship:** keep `effectCount: Int` as the
minimum protocol requirement. Adopters who need finer-grained
detection can **extend** the protocol with an `associatedtype
Snapshot: Equatable` + `func snapshot() -> Snapshot` overload.
Implementing with `Int` as the Snapshot is backward-compatible.
Adopt-when-needed; don't force boilerplate up front.

## API-shape assessment (from the trial's inside view)

Subjective take after writing ~80 LOC of trial test code:

- **Protocol declaration is minimal.** `var effectCount: Int`
  is one line. Mocks that already count calls internally (which
  most DynamoDB/HTTP mocks do) get a free conformance.
- **Call-site ergonomics are clean.**
  `try await assertIdempotentEffects(recorders: [a, b]) { ... }`
  reads naturally. The `recorders:` array is flexible for
  multi-dependency handlers.
- **The failure-path limitation is a real paper cut.** Having
  to write manual delta checks for bug-shape tests (instead of
  using `assertIdempotentEffects` directly with expected-failure
  semantics) is awkward. `Testing.Issue.record` alternative
  fixes this.
- **Opt-in model works.** Adopters with no mocks / no effect
  recorders can ignore Option B entirely and keep using
  `#assertIdempotent` (Option C). Opt in is a package-dep
  addition, not an API break.

No fundamental redesign warranted. Two incremental
improvements queued for a ship-path iteration: `Issue.record`
failure-mode variant, optional `Snapshot` overload.

## Ship recommendation

**Ship Option B in v0.3.0**, with two pre-ship refinements:

### R1 — Add `Issue.record` failure mode

```swift
public enum IdempotencyFailureMode {
    case preconditionFailure  // default — matches Option C
    case issueRecord          // Swift-Testing-specific, no process abort
}

public func assertIdempotentEffects(
    recorders: [any IdempotentEffectRecorder],
    failureMode: IdempotencyFailureMode = .preconditionFailure,
    file: StaticString = #fileID,
    line: UInt = #line,
    body: () async throws -> Void
) async rethrows
```

Unlocks failure-path tests; keeps default behavior unchanged
for non-Swift-Testing contexts. Requires conditional
`import Testing` in the implementation (macro `#if canImport(Testing)`).

### R2 — Extensible `Snapshot` overload

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

Adopters with richer mock state (call-log, argument history)
override `snapshot()` to return their richer type. Helper
compares snapshots instead of counts when `Snapshot != Int`.
Backward-compatible: existing conformers get `Snapshot = Int`
from the default.

### R3 — Move the `effectCount` protocol to `SwiftIdempotency` main target (not `TestSupport`)

Adopters' production mock types might conform for observability
purposes (monitoring retry counts in production). The protocol
itself is zero-runtime-cost; the helper can stay in `TestSupport`.

### Release mechanics

- Ship as v0.3.0 — additive API, no breaking changes from v0.2.0.
- `SwiftIdempotencyTestSupport` target becomes non-placeholder
  (already there post-prototype).
- README "Using with Option B" subsection mirroring the
  Fluent/SwiftData sections.
- Update `#assertIdempotent` (Option C) docs to cross-reference
  when to reach for Option B vs. Option C.

### Do NOT ship

- A macro-wrapping variant of Option B (`#assertIdempotentEffects
  { ... }` as a freestanding expression macro). The free
  function form is clearer; the macro's argument-list shape
  would need to serialize the recorders-array through macro
  syntax, which is awkward. Revisit if adopters specifically
  ask for the macro form.
- Hybrid Option-B/Option-C (`assertIdempotent(returning: ...,
  effects: [...])`). Nice-to-have but low-priority —
  adopters can compose by writing both checks in one test:

  ```swift
  let result = try await #assertIdempotent { await handler(...) }
  try await assertIdempotentEffects(recorders: [db]) { _ = try await handler(...) }
  ```

  Two separate calls read fine for the dual-check case.

## Cross-trial pattern: Option B catches shapes Option C misses

Penny's coin-double-grant is the canonical shape the prior
trials flagged as Option-C-blind:

- `handleAddUserRequest` returns `APIGatewayV2Response(status: .ok, content: coinResponse)` — a rich return, but
  `coinResponse.newCoinCount` would differ between first and
  second call (first: baseline+amount; second: baseline+amount*2).
  So Option C *would* catch this via return-inequality ...
  **if the Equatable comparison included the mutated field**.
  Adopter-side projections (tuple or struct) would work.
- **But** Option C fails silently when the adopter's projection
  omits `newCoinCount`, or when the retry is guarded but an
  unrelated field mutates (e.g., `updatedAt: Date()` drifts
  between calls even on a clean retry — false positive on
  Option C).

Option B is the cleaner check for the DB-write-level invariant:
"exactly one row inserted per logical request." Doesn't matter
what the return value contains; the mock counts the writes.

The other three Penny bug shapes (OAuth, sponsor DM, GHHooks)
follow the same pattern — side effects invisible in the return.
A future trial variant could exercise them for breadth, but
the API validation from this trial generalizes.

## Trial-completion status

Per [`../package_adoption_test_plan.md`](../package_adoption_test_plan.md):

1. **Three adopter integrations complete** — this is the fifth
   (luka-vapor + hellovapor + synthetic-swiftdata + vreader +
   Penny).
2. **No new P0 API-change requirements** — two incremental
   refinements (R1 + R2) surfaced but both are API-additive,
   not API-breaking.
3. **Linter parity** — already met; not re-verified here
   (Option B is test-runtime, not linter-shape).

**Methodology:** first trial with a **dual purpose** (validate
v0.2.0 + design v0.3.0 Option B simultaneously). Trial plan
§"Per-trial protocol" could be extended to note that
prototype-exercising trials are a legitimate shape —
`package_adoption_test_plan.md` assumes stable-API trials today.
