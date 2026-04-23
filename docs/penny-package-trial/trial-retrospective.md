# Penny — Package Integration Trial Retrospective (Option B probe)

Session-end summary. See [`trial-findings.md`](trial-findings.md)
for the empirical record; this doc is the "did Option B earn a
ship" layer + API refinement design.

## Did the scope hold?

**Yes, and the dual-purpose framing worked.** The trial was both
a Penny v0.2.0 package-integration validation AND an Option B API
design probe. Both outputs landed:

- Penny integration: SwiftIdempotency + SwiftIdempotencyTestSupport
  compile in Penny's heavy dep graph (DiscordBM + Soto + OpenAPI
  + FluentKit + NIO) with zero version conflicts. 2/2 tests green.
- Option B validation: the prototype catches the real
  coin-double-grant bug shape on adopter-realistic code. API
  surface is minimal (one protocol, one function), ergonomically
  clean at call sites, and has two well-scoped refinements
  surfaced before ship.

**What scoped in unexpectedly:** not much. The pre-commit hook
friction on the first Penny commit attempt was session-workflow
noise (SwiftLint found an unrelated serious `i` name in the
prototype), not trial-scope creep. Fixed in-session.

**What scoped out:** the other three Penny bug shapes (OAuth,
sponsor DM, GHHooks error-path). Coverage-breadth trial for
Option B was deferred — the API shape generalized from the one
coin-double-grant shape that was exercised. A future trial
variant could widen coverage if Option B ships and sees friction.

## Ship-or-defer decision

**Ship Option B in v0.3.0**, per the three refinements captured
in [`trial-findings.md`](trial-findings.md) §"Ship
recommendation":

- **R1** — Add `Issue.record` failure mode alongside
  `preconditionFailure`. Unlocks failure-path tests without
  process termination.
- **R2** — Extensible `Snapshot` associatedtype overload.
  Backward-compatible default is `Int = effectCount`;
  adopters with richer mock state get opt-in precision.
- **R3** — Move the `IdempotentEffectRecorder` protocol from
  `SwiftIdempotencyTestSupport` to the main `SwiftIdempotency`
  target, so production mocks (observability, retry
  instrumentation) can conform without depending on the
  test-support library.

These are **incremental** refinements, not redesigns. The
prototype's API shape is the shipping shape with two additive
fields (failureMode parameter; Snapshot associatedtype).

**Deferred explicitly:**

- Macro-wrapping variant (`#assertIdempotentEffects`) — free
  function is clearer for this API shape.
- Hybrid Option-B/Option-C (`assertIdempotent(returning:,
  effects:)`) — adopters can compose two separate calls when
  they want both checks.

## Option B — API recommendations (consolidated)

Full v0.3.0 API surface:

```swift
// In SwiftIdempotency (moved from SwiftIdempotencyTestSupport per R3)
public protocol IdempotentEffectRecorder: AnyObject {
    associatedtype Snapshot: Equatable = Int
    var effectCount: Int { get }
    func snapshot() -> Snapshot
}

extension IdempotentEffectRecorder where Snapshot == Int {
    public func snapshot() -> Int { effectCount }
}

public enum IdempotencyFailureMode: Sendable {
    case preconditionFailure
    case issueRecord
}

// In SwiftIdempotencyTestSupport (R1 + R2)
public func assertIdempotentEffects(
    recorders: [any IdempotentEffectRecorder],
    failureMode: IdempotencyFailureMode = .preconditionFailure,
    file: StaticString = #fileID,
    line: UInt = #line,
    body: () async throws -> Void
) async rethrows
```

Call-site shapes:

```swift
// Default: precondition-fail on detection (matches Option C)
try await assertIdempotentEffects(recorders: [mockDB]) {
    try await handler.run()
}

// Swift Testing: fails the test via Issue.record (no process abort)
try await assertIdempotentEffects(
    recorders: [mockDB],
    failureMode: .issueRecord
) {
    try await handler.run()
}

// Richer snapshot for mixed-idempotency cases
final class DetailedMock: IdempotentEffectRecorder {
    typealias Snapshot = [String]  // call log
    var effectCount: Int { callLog.count }
    private(set) var callLog: [String] = []
    func snapshot() -> [String] { callLog }
}
```

## Option B — refactor cost summary

Adopter-side cost to make a handler Option-B-testable, estimated
from Penny's `UsersHandler` → `InternalUsersService` →
`DynamoCoinEntryRepository` call chain:

| Layer | LOC diff | Reusability |
|---|---|---|
| Extract `CoinEntryRepositoryProtocol` | +3-5 | One-time per repo. |
| Add `UserRepositoryProtocol` (if Service uses both) | +6-8 | One-time. |
| Modify `InternalUsersService.init` to accept protocol deps | ±5 | One-time. |
| Create `MockCoinEntryRepository` + `MockUserRepository` | +20-30 | Shared across all tests touching these repos. |

**Total: ~35-50 LOC of adopter-side code.** The protocol
extractions are tiny (matching the existing repo API exactly);
the mock implementations are the bulk of the work but are
reusable across the entire test suite.

Compared to the status quo (adopter writes ad-hoc mocks per
test, or uses AWSClient-level mocking which is more intricate),
Option B's protocol-extraction approach is **cleaner per unit
effort** — the abstraction earns its keep beyond idempotency
testing.

## Follow-ups on what we found

### v0.3.0 workstream

Implementation order for shipping Option B:

1. Move `IdempotentEffectRecorder` protocol from
   `SwiftIdempotencyTestSupport` to `SwiftIdempotency` main
   target (R3).
2. Add `Snapshot` associatedtype with default `Int` + default
   implementation (R2). Update `assertIdempotentEffects` to
   compare snapshots when non-`Int`.
3. Add `failureMode: IdempotencyFailureMode` parameter to
   `assertIdempotentEffects` (R1). Implement
   `preconditionFailure` (existing) + `issueRecord` branches.
4. New unit tests:
   - `Snapshot`-overload happy path (richer state)
   - `failureMode: .issueRecord` — failure path observable via
     Swift Testing's `#expect(throws: ...)`-style mechanism
5. Migrate existing `AssertIdempotentEffectsTests` to remove
   the "throwing body rethrows" throw-only dance (now we can
   test failure directly).
6. README "Using Option B for effect-observation testing"
   section — parallels the existing Fluent/SwiftData sections.
7. Update `examples/` with `option-b-sample/` SPM package —
   mirrors the other consumer samples.
8. v0.3.0 tag, release notes, SPI auto-ingest.

Estimated session budget: 2-3 hours for the code-side (R1 +
R2 + R3 + tests); 1-2 hours for docs + example sample;
30 min for release prep. Total ~4-5 hours — manageable as a
single-session slice or a two-session split.

### Penny cross-bug-shape coverage (if Option B ships)

The Penny trial only exercised the coin-double-grant shape. If
Option B goes GA, a **Penny bug-sweep trial** exercising all
four shapes (coin, OAuth × 7 call sites, sponsor DM, GHHooks
error-path) would be valuable evidence for the README and for
the linter's cross-reference docs. One session of work, low
risk.

### Option B vs. Option A reconciliation

The original design space had Option A (abstract "observable-
equivalence" bucket) that was never concretely specified.
Option B is effectively the concrete form of Option A. The
docs should be updated to note that Option A no longer
meaningfully exists as a separate bucket — A and B are the
same idea; the "observable-equivalence" phrasing was premature
and was subsumed by the concrete effect-recorder shape.

### Policy note for the test plan

Fold into `package_adoption_test_plan.md` §"Per-trial
protocol": **dual-purpose trials are legitimate** when the
prototype API surface is small enough (< 200 LOC) and the
validation target's real-bug shapes directly inform the API
design. The Penny trial demonstrates the shape: prototype
commits to main (experimental-labeled), adopter trial pulls
via SHA pin, trial findings inform ship/refine/abandon
decision, prototype stabilizes in a subsequent release or
reverts to placeholder.
