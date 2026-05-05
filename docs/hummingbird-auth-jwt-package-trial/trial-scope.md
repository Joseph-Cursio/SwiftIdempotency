# Hummingbird auth-jwt — Package Adoption Trial Scope (Option B Hummingbird probe)

Per [`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
**Hummingbird's first Option B (effect-observation) trial.** Validates that
`SwiftIdempotencyTestSupport.assertIdempotentEffects` and
`IdempotentEffectRecorder` attach cleanly to Hummingbird-shaped handler
code (Hummingbird `Router` + `Fluent` repository pattern), and that the
two-call snapshot mechanism behaves correctly on the framework's
canonical "create handler with intrinsic dedup-via-throw" shape.

Closes the standing CLAUDE.md memory note that "Hummingbird is the leading
framework target for validating the proposal against real code." Option B
shipped in v0.3.0 against Penny (Lambda) only; this round adds the
Hummingbird/Fluent shape to the validation set.

## Research question

> **Does `SwiftIdempotencyTestSupport.assertIdempotentEffects` attach
> cleanly to a Hummingbird `Router` + `Fluent` `Model` handler, and what
> does it tell us about a handler whose intrinsic dedup mechanism
> (`existingUser != nil → throw .conflict`) makes the second call's
> *snapshot* identical but its *return* divergent?**

## Why hummingbird-examples/auth-jwt specifically

Three structural reasons that make it a clean Hummingbird Option B
target:

- **Two contrasting handlers in 80 lines.** `UserController.create`
  exercises the real-DB-write shape (Option B's design center);
  `UserController.login` exercises the `Date()`-in-payload shape
  (Option C's pathology — returns differ on retry by construction).
  Both shapes appear without scaffolding noise.
- **Fluent repository surface.** Direct `User.query(on: db)` /
  `user.save(on: db)` calls — the same idiom the Vapor adopters
  use, but in a Hummingbird `RouterGroup` rather than `routes.post`.
  Validates that the `assertIdempotentEffects` recorder pattern
  ports across the Vapor↔Hummingbird boundary unchanged.
- **In-memory SQLite via `inMemoryDatabase: true`.** No external
  service to mock; tests can use a real DB and assert on actual
  row counts. Reduces the trial's mock-construction surface to the
  handler-side recorder only.

## Pinned context

- **SwiftIdempotency tip:** `4446a06` (post-PRD-rename docs commit on
  `main`). Includes the v0.3.0 Option B surface
  (`IdempotentEffectRecorder` + `assertIdempotentEffects`).
- **Upstream target:** `hummingbird-project/hummingbird-examples` —
  shallow-cloned at `--depth 1` to `/tmp/hummingbird-examples` for this
  round. Specific subdirectory: `auth-jwt/`.
- **Toolchain:** Swift 6.0 (auth-jwt declares
  `swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`). The host
  toolchain on this machine is 5.10+ per `Package.swift`'s tools
  declaration, so the actual `swift build` step is performed from
  the auth-jwt directory.
- **Trial fork:** *Not created this session* — the trial deliverable
  is documented integration plus inline code, not a pushed branch.
  Future round may fork to `Joseph-Cursio/hummingbird-examples-idempotency-trial`
  if upstream-PR consideration becomes relevant.
- **Testing layer:** `HummingbirdTesting` + `HummingbirdAuthTesting`
  (already in the example's test target).

## Handler shapes under test

### Primary subject — `UserController.create` (PUT /user)

```swift
@Sendable func create(
    _ request: Request, context: Context
) async throws -> EditedResponse<UserResponse> {
    let createUser = try await request.decode(as: CreateUserRequest.self, context: context)
    let db = self.fluent.db()
    let existingUser = try await User.query(on: db)
        .filter(\.$name == createUser.name)
        .first()
    guard existingUser == nil else { throw HTTPError(.conflict) }
    let user = try await User(from: createUser)
    try await user.save(on: db)
    return .init(status: .created, response: UserResponse(from: user))
}
```

Effect analysis:

- First call (user doesn't exist): `User.query` (read), `user.save`
  (WRITE), returns `.created`.
- Second call (user now exists): `User.query` (read), `throw HTTPError(.conflict)`.

The handler's intrinsic dedup is **strong on observable effect** —
the second call never hits `user.save` — but **divergent on return** —
the second call throws instead of returning. This is exactly the
shape Option B's snapshot mechanism is designed to surface as
distinct from Option C's return-equality:

- Option B snapshot delta: `effectCount == 1` after first call;
  `effectCount == 1` after second call (the throw aborts before the
  write). Snapshots equal → `assertIdempotentEffects` passes.
- Option C return equality: first call returns
  `EditedResponse<UserResponse>` with `status: .created`; second
  call throws. The two are not comparable; `#assertIdempotent`
  would rethrow.

Whether this counts as "idempotent" depends on the observer
contract (see USER_GUIDE §Foundational concepts). For the **DB
observer**, yes — single row exists either way. For the **HTTP
client**, no — first call gets 201, second gets 409. The package
should let the test suite express both readings cleanly.

### Secondary subject — `UserController.login` (POST /user/login)

```swift
@Sendable func login(_ request: Request, context: Context) async throws -> [String: String] {
    guard let user = context.identity else { throw HTTPError(.unauthorized) }
    let payload = JWTPayloadData(
        subject: .init(value: try user.requireID().uuidString),
        expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)),
        userName: user.name
    )
    return try await ["token": self.jwtKeyCollection.sign(payload, kid: self.kid)]
}
```

Effect analysis:

- No DB writes — `user` comes from middleware-resolved
  `context.identity`. JWT signing is intrinsically pure given the
  same key + payload.
- But the payload uses `Date(timeIntervalSinceNow: 12 * 60 * 60)` —
  a fresh wall-clock at every call. So two consecutive `login` calls
  with identical inputs produce **different JWTs** (different
  `expiration` claims).
- Return type `[String: String]` IS `Equatable`, so
  `#assertIdempotent` *will* fire on this handler.

This is the textbook **"intentionally non-idempotent return, not a
bug"** case. It exercises the Option C pathology in reverse: Option
C correctly identifies the non-idempotency, but the handler is
*designed* this way (login tokens have rolling expirations). The
trial should document how to express "this is non-idempotent by
design" cleanly — `@NonIdempotent` is the right marker; the test
should then *not* wrap login in `#assertIdempotent`.

## Migration plan (test-target-only)

**No auth-jwt source files modified.** The trial declares a minimal
mock-conforming type inline in the test file — what real adoption
would need to extract (`UserRepositoryProtocol`) is *documented*
rather than executed. This matches the Penny precedent.

1. Conceptually add `SwiftIdempotency` + `SwiftIdempotencyTestSupport`
   to `Tests/AppTests/` in `auth-jwt/Package.swift`. The trial
   deliverable shows what that diff looks like; whether to actually
   commit it depends on whether a fork is created.
2. New test file
   `Tests/AppTests/OptionBIdempotencyTrialTests.swift` (inline in
   the trial-findings doc):
   - **Test 1 — bug-shape detection**: a synthetic
     `NaiveUserController` variant that *removes* the existence
     check (introduces a double-write bug); demonstrate that
     `assertIdempotentEffects` against a `MockUserRepo` catches the
     resulting `effectCount` divergence.
   - **Test 2 — dedup-via-throw shape**: the actual `create`
     handler shape; demonstrate that `assertIdempotentEffects`
     *passes* (no double-write because of the existence check) but
     a separate test catches the throw on retry as a distinct
     concern.
   - **Test 3 — Option C on login**: demonstrate that
     `#assertIdempotent` correctly *fires* on `login` because of
     the `Date()` in the payload; document that `@NonIdempotent`
     is the right annotation rather than `#assertIdempotent`.

## Pre-committed questions

1. **Does `IdempotentEffectRecorder` mock idiomatically over a
   Fluent `User` Model?** Penny used `@DynamoDB` repositories;
   Hummingbird+Fluent uses `User.query(on: db)`. The mock surface
   is structurally different. Does protocol extraction look
   different than on Penny?
2. **Does Option B correctly handle the "throw on retry" shape?**
   The create handler's second call throws. Does
   `assertIdempotentEffects` rethrow as expected? Does the
   resulting test failure read clearly to a reader who doesn't
   know Option B's design?
3. **Does Option C give a useful diagnostic on `login`?** The
   handler is *intentionally* non-idempotent. Does the resulting
   `#assertIdempotent` failure message at least name the
   non-idempotent shape (different return values) clearly enough
   to lead the reader to `@NonIdempotent`?
4. **What's the refactor cost for full Option B adoption?**
   `UserController` takes a concrete `Fluent` (not a protocol).
   Extracting `UserRepositoryProtocol` from
   `User.query`/`user.save` is the cost. Estimate
   lines-of-code-changed; compare to Penny's ~15-25 LOC per repo.

## Scope commitment

- **Test-target-only.** No upstream auth-jwt source files modified.
- **No fork pushed this session.** The trial deliverable is the
  scope + findings docs plus inline code; if it warrants pushing
  later, a separate session creates the fork.
- **One handler family.** `UserController` only. No exploration of
  the JWTAuthenticator middleware, the `auth/` route, or other
  Hummingbird examples (jobs, websocket-chat, etc.).
- **Inline mock implementation** rather than a full Hummingbird-
  shaped abstraction layer. The trial measures fit and friction;
  per-adopter abstraction work is the adopter's responsibility.

## Predicted outcomes

- **Q1 (Fluent mock idiom):** ⚠️ partial. Fluent's repository
  pattern is implicit (`User.query(on: db)` is a static method on
  the Model, not a method on a repository object). Adopters can't
  protocol-extract the way Penny did. Two workarounds: mock the
  `Fluent` itself (intercept at the DB level, more work), or
  refactor handlers to take an injected protocol-typed repository
  (more invasive). Document both, recommend the latter for new
  code.
- **Q2 (throw on retry):** ✅ expected pass. The helper `rethrows`
  on the second invocation's throw, surfacing the divergent return
  to the test framework. The test is responsible for asserting
  whether-it-should-throw separately; Option B is silent on it
  because the snapshot didn't change.
- **Q3 (Option C on login):** ⚠️ ambiguous diagnostic. The
  precondition message is "closure returned different values on
  re-invocation — not idempotent" — accurate but doesn't lead the
  reader to `@NonIdempotent` specifically. Documentation
  improvement opportunity: the failure path should hint at
  marking the function `@NonIdempotent` if the divergence is by
  design.
- **Q4 (refactor cost):** higher than Penny per-handler — Penny's
  controllers already took protocol-injected repos; auth-jwt's
  controller takes a concrete `Fluent`. Estimated 30-40 LOC for
  protocol extraction + DI rewiring per controller. Higher cost
  per handler, but only because Hummingbird's example code
  doesn't follow DI conventions; production Hummingbird apps
  typically do.

## What the trial decides

This trial is **API-validation, not bug-finding**. The output is:

- ✅ **Confirm**: Option B's API surface attaches cleanly to a
  Hummingbird/Fluent codebase, with the same recorder shape used
  in the Penny trial.
- 🔍 **Surface**: any Hummingbird-specific friction (Fluent
  static-method idiom, RouterGroup vs routes.post differences in
  registration shape).
- 📋 **Document**: the create-handler-with-intrinsic-dedup shape
  as a distinct case from the simple-double-write shape. Penny's
  trial implied Option B catches "double write"; auth-jwt's
  trial documents that Option B is silent on "intrinsic dedup
  via early throw" — both readings are correct interpretations of
  the snapshot mechanic.

## Scope boundaries — NOT in this trial

- **Other Hummingbird example apps.** Jobs, websocket-chat,
  todos-fluent, etc. — all framework-shape variants worth probing
  in future rounds, but each its own trial.
- **Linter pass against auth-jwt.** This is a package-adoption
  trial, not a `road_test_plan.md` linter round. Linter rules
  fire only on annotated handlers; un-annotated example code
  produces a Run A yield of zero by construction.
- **Production hummingbird app validation.** Confirms framework
  shape only. A production-app round (still standing as a TODO
  in the targets file) addresses the FP-rate question.
- **Macro-form variant exercise.** auth-jwt is not currently a
  SwiftIdempotency consumer; adding the package dependency just
  for an attribute-form check inflates trial scope. Skipped per
  the package_adoption_test_plan §Macro-form variant.
- **`trial-retrospective.md`.** Deferred to the next session per
  the agreed session-boundary scope. Findings doc captures the
  per-question answers; retrospective synthesises lessons across
  questions and feeds them back to the test plan.
