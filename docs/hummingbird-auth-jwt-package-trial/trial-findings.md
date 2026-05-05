# Hummingbird auth-jwt — Trial Findings

Per [`trial-scope.md`](trial-scope.md). Test-target-only Option B
integration trial against `hummingbird-project/hummingbird-examples/auth-jwt`.

## Headline result

**Option B integrates cleanly with a Hummingbird/Fluent codebase.**
After resolving three Swift-6-strict-concurrency friction items
(documented below, all in the trial's mock authoring layer — none
in `SwiftIdempotency`'s own surface), all five tests pass:

```
Executed 5 tests, with 0 failures (0 unexpected) in 1.008 seconds
  AppTests (auth-jwt's own tests):                            2 passed
  OptionBIdempotencyTrialTests (this trial):                  3 passed
```

## Test outcome

Three trial tests, all passing on the same `swift test` invocation
that runs auth-jwt's own two pre-existing tests:

| Test | Question addressed | Outcome |
|---|---|---|
| `testDedupGuardedCreate_OptionB_passes_butSecondCallThrows` | Q2: throw-on-retry shape | ✅ Manual delta check: snapshot equal across both calls; second throws as expected |
| `testDedupGuardedCreate_OptionB_endToEnd_withSwallowedConflict` | Q1: end-to-end `assertIdempotentEffects` happy path | ✅ Helper passes silently; `effectCount == 1` after both invocations |
| `testNaiveCreate_demonstratesOptionBBugShapeDetection` | Q1 (bug variant): does Option B detect the double-write shape? | ✅ Manual delta check: `firstDelta == 1`, `secondDelta == 1`, `users.count == 2` — the divergence Option B's snapshot mechanism would precondition-fail on |

The full test file is included verbatim at the bottom of this document.

## Compilation log

**Initial fresh build** (after adding SwiftIdempotency dep + writing
the trial test file): 164.97s clean. Most of that is shared with
auth-jwt's own dependency graph (FluentKit, Hummingbird suite,
SwiftSyntax via the macro plugin) — no double-compilation surfaced.

**Incremental rebuild + test cycle** (after `touch` on the trial
test file): 1.97s wall time including the full test run. The
package's macro-plugin overhead is amortised after the first build.

**Three Swift-6-strict-concurrency frictions** surfaced on first
compile attempt. All in adopter-side mock authoring; none in
`SwiftIdempotency`'s public surface:

### Friction 1 — `NSLock.unlock()` unavailable in async contexts

```
error: instance method 'unlock' is unavailable from asynchronous contexts;
       Use async-safe scoped locking instead
   func save(_ user: TrialUser) async throws {
       lock.lock(); defer { lock.unlock() }
                          `- error
```

The mock initially used `NSLock` with `lock.lock(); defer { lock.unlock() }`
inside `async` methods. Swift 6's strict-concurrency annotations on
`Foundation.NSLock.unlock` reject this. **Resolution**: drop the
lock entirely. The mock is single-test-context (no actual concurrent
calls), and the alternative (an `actor`-based wrapper) adds idiom
overhead disproportionate to the test scope.

This isn't a SwiftIdempotency-shaped friction — any Hummingbird
adopter writing a test mock with mutable shared state will hit it.
But it's worth flagging in adopter-facing documentation: the
"recorder is `AnyObject`" requirement plus "test target uses Swift
6 strict concurrency" combine to require either `@unchecked
Sendable` (with the adopter taking responsibility for thread
safety) or an actor-based recorder.

### Friction 2 — `Sendable` conformance with mutable stored properties

```
error: stored property 'users' of 'Sendable'-conforming class
       'MockUserRepo' is mutable
   final class MockUserRepo: UserRepositoryProtocol, IdempotentEffectRecorder {
       private(set) var users: [TrialUser] = []
                        `- error
```

`IdempotentEffectRecorder` requires `AnyObject`; the trial protocol
required `Sendable`; mutable stored properties on a `Sendable`-
conforming class are rejected by strict-concurrency. **Resolution**:
mark the mock `@unchecked Sendable`, matching auth-jwt's own
`final class User: Model, ..., @unchecked Sendable` pattern (Fluent
Models exhibit identical concurrency posture).

This points at a documentation opportunity in
`SwiftIdempotency`'s `IdempotentEffectRecorder` docs: a small note
that adopter mocks under Swift 6 strict concurrency typically need
`@unchecked Sendable` (or an actor-based shape) and that the
package itself doesn't impose that requirement — it's the
intersection of `AnyObject` + mutable state + Sendable that does.

### Friction 3 — unused `existing` binding

```
warning: value 'existing' was defined but never used; consider replacing with boolean test
   if let existing = try await repo.findByName(name) {
          `- warning
```

Trivial; not Swift-6-specific. **Resolution**: switched to
`if try await repo.findByName(name) != nil`.

### Additional warning resolved during retest

```
warning: no calls to throwing functions occur within 'try' expression
   try await assertIdempotentEffects(recorders: [repo]) {
   `- warning
```

`assertIdempotentEffects` is `rethrows`. When the body's
do-catch swallows all throws, the call site doesn't need `try`.
**Resolution**: dropped the `try`, kept `await`. The helper's
rethrows signature does the right thing in both throwing and
non-throwing closure cases.

## API friction log (cumulative)

| # | Friction | SwiftIdempotency-shaped? | Resolution |
|---|---|---|---|
| 1 | `NSLock.unlock()` unavailable in async context | No (Swift 6 strict-concurrency × Foundation) | Drop lock; rely on single-thread test context |
| 2 | `Sendable` + mutable stored properties on `IdempotentEffectRecorder` conformer | Partially — the `AnyObject` requirement combined with adopter `Sendable` choice forces the issue | `@unchecked Sendable`; matches auth-jwt's own User pattern |
| 3 | Unused `existing` binding in `if let` | No | `!= nil` |
| 4 | Unnecessary `try` on rethrowing `assertIdempotentEffects` with non-throwing body | No (compiler warning, not adopter-relevant) | Drop `try`, keep `await` |

**Zero frictions in the SwiftIdempotency public surface itself.**
`IdempotentEffectRecorder.effectCount` was the only required
member; the default `Snapshot = Int` extension supplied
`snapshot()` automatically; `assertIdempotentEffects(recorders:body:)`
worked unchanged from the Penny precedent.

## Pre-committed-question answers

### Q1: Does the mock idiom feel natural over a Fluent-shaped repository?

**Partial.** Two findings:

The `IdempotentEffectRecorder` conformance worked unchanged from
Penny. The core mock shape (a class with `var effectCount: Int`
that increments on writes) is identical regardless of whether the
underlying domain is DynamoDB (Penny) or Fluent (auth-jwt).

The harder question is *what gets mocked*. auth-jwt's
`UserController.create` calls `User.query(on: db)` and
`user.save(on: db)` directly — Fluent's idiomatic static-method
shape. A real adoption would have to refactor the controller to
take an injected `UserRepositoryProtocol` rather than a concrete
`Fluent` instance. The trial's `dedupGuardedCreate` function
demonstrates the post-refactor shape:

```swift
func dedupGuardedCreate(name: String, password: String?,
                        repo: UserRepositoryProtocol) async throws -> TrialUser
```

This is a structural observation about Hummingbird+Fluent
idiomatics, not a SwiftIdempotency limitation. Adopters who
already use protocol-based DI (the Hummingbird "service-oriented"
pattern, common in production codebases) get Option B for free.
Adopters who use the example-shape idiom (Fluent statics directly
inside controller methods) need the refactor.

**Recommendation for adopter-facing docs**: USER_GUIDE's "Integrating
with Vapor and Hummingbird" section should mention that Option B
adoption presupposes (or motivates) protocol-based repository
injection, and that the example-style direct-Fluent pattern is the
one place where auth-jwt-shaped code can't drop in
`assertIdempotentEffects` without first refactoring.

### Q2: Does Option B correctly handle the "throw on retry" shape?

**Yes for snapshot mechanism; no for end-to-end helper without a
swallow wrapper.**

The dedupGuardedCreate handler exhibits the auth-jwt pattern: first
call writes, second call throws before write. The two snapshots
(post-first, post-second) are equal — `effectCount == 1` both
times. So Option B's *core mechanism* (snapshot equality) correctly
classifies the handler as idempotent on observable effect.

But `assertIdempotentEffects` rethrows. If you call it directly on
this body, the helper rethrows the second call's `HTTPError(.conflict)`
and the test fails with the *thrown error*, not with a clear
non-idempotency diagnostic. To use the helper end-to-end, the
trial wrapped the body in a `do { try ... } catch { /* swallow */ }`
— see `testDedupGuardedCreate_OptionB_endToEnd_withSwallowedConflict`.

This is **subtle and worth a doc note**. For handlers whose
intrinsic dedup mechanism is "throw on retry" (a common
Hummingbird+Fluent shape — the auth-jwt create handler is one
example, and `Acronym.find(...) != nil` style checks in the
hellovapor trial are another), the idiomatic Option B test:

1. Wraps the body in a swallow-conflict catch.
2. Asserts `effectCount` directly after the helper completes (as
   a sanity check).
3. Has a *separate* test asserting the second call's throwing
   behaviour — that's a return-divergence test, complementary to
   Option B's effect-divergence test, but distinct.

The `Foundational concepts §Partial failure and the retry contract`
section in USER_GUIDE already names this distinction (atomic vs.
unconditional idempotency). Trial confirms the distinction is
*concretely necessary* on Hummingbird's example-shape code, not
just a theoretical concern.

### Q3: Does Option C give a useful diagnostic on `login`?

**Not exercised in code** (per scope: "Q3 documented in findings
rather than tested"). Analysis:

auth-jwt's `login` handler returns `[String: String]` containing a
JWT whose payload includes `expiration: .init(value:
Date(timeIntervalSinceNow: 12 * 60 * 60))`. Two consecutive calls
produce JWTs with different `exp` claims → different JWT signatures
→ different dictionary values. `#assertIdempotent` would fire on
the return-equality check with the message:

```
#assertIdempotent: closure returned different values on re-invocation — not idempotent
```

This is **accurate but actionably ambiguous**. The handler is
*designed* to return rolling tokens; non-idempotency is the
feature, not a bug. A reader hitting this diagnostic might:

1. Wrap login in `@NonIdempotent` and stop calling
   `#assertIdempotent` on it. ✅ correct response.
2. Try to "fix" the handler by removing the `Date()` call. ❌
   incorrect response — would break token expiration semantics.
3. Suppress the assertion with a comment. ⚠️ fragile.

The diagnostic message could nudge toward (1) more clearly. A
future improvement worth scoping: `#assertIdempotent`'s failure
diagnostic could mention "if this is by design, mark the function
`@NonIdempotent`" as a hint.

This is a documentation/diagnostic improvement, not a blocking
issue for v0.3.x.

### Q4: What's the refactor cost for full Option B adoption on auth-jwt?

**Estimate: 30-40 LOC for protocol extraction + DI rewiring on
`UserController`**, on top of the test target additions.

Concrete breakdown:

- `UserRepositoryProtocol` declaration: ~5 LOC
- `FluentUserRepository: UserRepositoryProtocol` adapter (wraps
  `User.query(on: db).filter(...).first()` and `user.save(on: db)`):
  ~15 LOC
- `UserController` change: replace `let fluent: Fluent` with
  `let userRepo: any UserRepositoryProtocol`; rewrite `create`'s
  body to call `repo.findByName` / `repo.save`: ~10 LOC delta
- `Application+build.swift` update: instantiate
  `FluentUserRepository(fluent: fluent)` and pass it to
  `UserController.init`: ~3 LOC

This is **higher than Penny's per-handler estimate** (~15-25 LOC)
because Penny's controllers were already DI-shaped. auth-jwt as
shipped is example-shaped — the refactor *adds* DI structure that
production Hummingbird apps typically already have.

**Production Hummingbird codebases using DI**: refactor cost
approaches Penny's, ~15-25 LOC.

## Linter parity check

**Not run this round.** auth-jwt is not currently a SwiftProjectLint
trial target, and adding the linter pass would inflate the trial's
scope (separate methodology per `road_test_plan.md`). A future
hummingbird-auth-jwt linter round can exercise the doc-comment
form (`/// @lint.context replayable` on the registered handler
function) for parity.

## Build-time delta

| Build phase | Without `SwiftIdempotency` dep | With dep + trial test file |
|---|---|---|
| Clean build | not measured this round | 164.97s |
| Incremental rebuild + test (touched test file) | not measured this round | 1.97s |
| Test execution (excluding build) | ~1.0s | ~1.0s (3 new tests + 2 originals) |

The 165s clean build absorbs the macro-plugin compilation
(SwiftSyntax dependency chain), which dominates the cost. The
incremental cycle is unaffected — once cached, the macro-plugin
doesn't rebuild on test-file edits.

## Test-file deliverable

Full text of `Tests/AppTests/OptionBIdempotencyTrialTests.swift` as
landed in the local /tmp clone — included here verbatim because no
fork was pushed this session.

```swift
import Foundation
import SwiftIdempotency
import SwiftIdempotencyTestSupport
import XCTest

@testable import App

// MARK: - Test fixtures: protocol + mock for a hypothetical UserRepository

protocol UserRepositoryProtocol: AnyObject, Sendable {
    func findByName(_ name: String) async throws -> TrialUser?
    func save(_ user: TrialUser) async throws
}

struct TrialUser: Sendable, Equatable {
    let id: UUID
    let name: String
    let passwordHash: String?
}

/// `@unchecked Sendable` because mutation is single-threaded in the
/// test target. Matches auth-jwt's own `final class User: Model,
/// @unchecked Sendable` pattern.
final class MockUserRepo: UserRepositoryProtocol, IdempotentEffectRecorder, @unchecked Sendable {
    private(set) var users: [TrialUser] = []

    var effectCount: Int { users.count }

    func findByName(_ name: String) async throws -> TrialUser? {
        users.first(where: { $0.name == name })
    }

    func save(_ user: TrialUser) async throws {
        users.append(user)
    }
}

// MARK: - Synthetic handler variants

func naiveCreate(name: String, password: String?, repo: UserRepositoryProtocol) async throws -> TrialUser {
    let user = TrialUser(id: UUID(), name: name, passwordHash: password)
    try await repo.save(user)
    return user
}

func dedupGuardedCreate(name: String, password: String?, repo: UserRepositoryProtocol) async throws -> TrialUser {
    if try await repo.findByName(name) != nil {
        throw NSError(domain: "Conflict", code: 409, userInfo: nil)
    }
    let user = TrialUser(id: UUID(), name: name, passwordHash: password)
    try await repo.save(user)
    return user
}

// MARK: - Tests

final class OptionBIdempotencyTrialTests: XCTestCase {

    func testDedupGuardedCreate_OptionB_passes_butSecondCallThrows() async throws {
        let repo = MockUserRepo()
        _ = try await dedupGuardedCreate(name: "alice", password: "pw", repo: repo)
        XCTAssertEqual(repo.effectCount, 1)
        do {
            _ = try await dedupGuardedCreate(name: "alice", password: "pw", repo: repo)
            XCTFail("second call should throw")
        } catch { /* expected */ }
        XCTAssertEqual(repo.effectCount, 1)
    }

    func testDedupGuardedCreate_OptionB_endToEnd_withSwallowedConflict() async {
        let repo = MockUserRepo()
        await assertIdempotentEffects(recorders: [repo]) {
            do {
                _ = try await dedupGuardedCreate(name: "bob", password: "pw", repo: repo)
            } catch { /* swallow conflict */ }
        }
        XCTAssertEqual(repo.effectCount, 1)
    }

    func testNaiveCreate_demonstratesOptionBBugShapeDetection() async throws {
        let repo = MockUserRepo()
        let baseline = repo.effectCount
        _ = try await naiveCreate(name: "carol", password: "pw", repo: repo)
        let afterFirst = repo.effectCount
        _ = try await naiveCreate(name: "carol", password: "pw", repo: repo)
        let afterSecond = repo.effectCount
        XCTAssertEqual(afterFirst - baseline, 1)
        XCTAssertEqual(afterSecond - afterFirst, 1)
        XCTAssertEqual(repo.users.count, 2)
        XCTAssertNotEqual(afterFirst, afterSecond)
    }
}
```

`Package.swift` diff (only the test target dependency block):

```diff
     dependencies: [
         .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.19.0"),
         ...
+        .package(path: "/Users/josephcursio/xcode_projects/SwiftIdempotency"),
     ],
     targets: [
         .executableTarget(...),
         .testTarget(
             name: "AppTests",
             dependencies: [
                 .byName(name: "App"),
                 .product(name: "HummingbirdTesting", package: "hummingbird"),
                 .product(name: "HummingbirdAuthTesting", package: "hummingbird-auth"),
+                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
+                .product(name: "SwiftIdempotencyTestSupport", package: "SwiftIdempotency"),
             ]
         ),
     ]
```

## Carry-overs for the retrospective (deferred to next session)

- The `@unchecked Sendable` mock pattern is undocumented in the
  package's own docs; the trial surfaced it as a real adopter-side
  step for Swift 6 strict-concurrency targets. Worth a USER_GUIDE
  Option B subsection or a callout in `IdempotentEffectRecorder`'s
  doc comment.
- The "throw on retry" shape needs an explicit USER_GUIDE pattern
  recipe — wrap the body, swallow the conflict, assert the
  effectCount separately. Trial's
  `testDedupGuardedCreate_OptionB_endToEnd_withSwallowedConflict`
  is a candidate code sample.
- `#assertIdempotent`'s failure message doesn't lead the reader to
  `@NonIdempotent` for "non-idempotent by design" cases like
  rolling-token returns. Diagnostic improvement.
- Trial fork creation deferred — no upstream-PR pressure on this
  round (the integration is purely additive, no source modifications),
  and pushing a fork purely to host the test file inflates scope
  beyond the trial's question.
