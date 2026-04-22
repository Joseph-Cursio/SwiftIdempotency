# luka-vapor — Package Integration Trial Scope

First package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
Migrates one real handler in `kylebshr/luka-vapor` to use the
`SwiftIdempotency` macro surface end-to-end. Unlike the prior
[linter trial](../luka-vapor/trial-scope.md) which was
measurement-only (one doc-comment annotation), this trial adds
the package as a dependency and rewrites adopter source to
exercise the API.

## Research question

> **Does the SwiftIdempotency macro surface (specifically
> `IdempotencyKey` + `@ExternallyIdempotent(by:)` + `#assertIdempotent`)
> integrate cleanly with a real Vapor handler that takes a
> Codable request body, hits Redis + APNS side effects, and
> returns `HTTPStatus.ok`? What API frictions surface in the
> migration, and does `#assertIdempotent`'s Option C (return-
> equality) silently pass on the non-idempotent path because
> both calls return `.ok` regardless of the underlying Redis
> state change?**

## Pinned context

- **SwiftIdempotency tip:** `fffb813` (v0.1.0 pre-release, includes
  Apache-2.0 license, `Using without SwiftProjectLint` README
  section, and the package adoption test plan).
- **SwiftProjectLint tip:** `db4d576` (post-slot-18 merge).
- **Upstream target:** `kylebshr/luka-vapor` @ `8a6fd42` (main,
  2026-04-18, "Merge pull request #19 from kylebshr/kb/fly-app-name").
- **Trial fork:** `Joseph-Cursio/luka-vapor-idempotency-trial`
  (already exists from prior linter trial).
- **Trial branch:** `package-integration-trial`, forked from
  upstream `main` tip `8a6fd42`. Sibling to `trial-luka-vapor`
  (the linter-trial branch) — they do not share state, the
  linter artifacts stay intact.

## Migration plan

**Target: `start-live-activity` POST handler** in
`Sources/LukaVapor/routes.swift`.

Current shape (upstream):

```swift
app.post("start-live-activity") { req async throws -> HTTPStatus in
    let body = try req.content.decode(StartLiveActivityRequest.self)
    // ... Redis hget/hset/zadd + session mutation
    return .ok
}
```

Target shape (post-migration):

```swift
// In Sources/LukaVapor/Models/StartLiveActivityRequest.swift:
struct StartLiveActivityRequest: Content {
    // ... existing fields
    let idempotencyKey: IdempotencyKey   // new field
}

// In Sources/LukaVapor/routes.swift:
app.post("start-live-activity") { req async throws -> HTTPStatus in
    let body = try req.content.decode(StartLiveActivityRequest.self)
    return try await startLiveActivity(
        app: app,
        req: req,
        body: body,
        idempotencyKey: body.idempotencyKey
    )
}

// In Sources/LukaVapor/Handlers/StartLiveActivity.swift (new file):
@ExternallyIdempotent(by: "idempotencyKey")
func startLiveActivity(
    app: Application,
    req: Request,
    body: StartLiveActivityRequest,
    idempotencyKey: IdempotencyKey
) async throws -> HTTPStatus {
    // ... moved handler body
    return .ok
}
```

**Expected refactor frictions:**

1. **Inline-closure handler → named func** — `@ExternallyIdempotent(by:)`
   is an attribute macro; attribute macros attach to declarations
   (`func`, `var`, etc.), not to expressions. The existing inline-
   trailing-closure shape requires a named-func refactor. This is
   a **structural API friction** and the first thing the findings
   should capture.
2. **`IdempotencyKey` on a non-Identifiable request body** —
   `StartLiveActivityRequest` is `Content` (Vapor's
   `Decodable+Encodable`), not `Identifiable`. The `init(fromEntity:)`
   constructor on `IdempotencyKey` requires `Identifiable`;
   adopters will reach for `init(fromAuditedString:)` instead. This
   tests the prediction that `init(fromAuditedString:)` is the
   actual primary path for typical adopter shapes.
3. **`IdempotencyKey` in a `Codable` struct field** — does the
   type's `Codable` conformance produce reasonable JSON on the
   wire? Tests are currently unit-level; this is the first time
   the type crosses a real HTTP boundary.

## Test plan (`#assertIdempotent`)

Add a new `@Test` in `Tests/LukaVaporTests/LukaVaporTests.swift`:

```swift
@Test
func startLiveActivityIsIdempotent() async throws {
    let key = IdempotencyKey(fromAuditedString: "test-start-key-001")
    let body = StartLiveActivityRequest(
        /* ... test fixture fields ... */
        idempotencyKey: key
    )

    let result = try await #assertIdempotent {
        try await startLiveActivity(
            app: testApp,
            req: mockRequest,
            body: body,
            idempotencyKey: key
        )
    }
    #expect(result == .ok)
}
```

**Critical prediction to test:** the handler hits Redis
(`redis.hset`, `redis.zadd`) which mutates state on every call.
A non-mock second invocation will cause the sorted-set's
`zadd` to add a duplicate (timestamp, username) entry. The
handler returns `.ok` either way. `#assertIdempotent` will
**silently pass** via Option C because both returns are
`HTTPStatus.ok == HTTPStatus.ok`, while the underlying Redis
double-write is invisible to the comparison.

If the prediction holds, this is **the definitive evidence** for
the Option C pathology and a P0 issue for the package's test-time
guarantees.

## Scope commitment

- **One handler, one test.** Do not migrate `end-live-activity`
  (the other POST) or the GET handler. Keep the surface small.
- **No upstream PR.** This is non-contribution work on the
  measurement fork. The adopter isn't informed.
- **Fork hardening banner not required** — this trial runs on
  the `package-integration-trial` branch only; the default
  branch (`trial-luka-vapor` from the linter round) already
  carries the banner.
- **Adopter-side test isolation is a known gap** — the handler
  calls `req.redis.*` which requires a live Redis. The trial
  will attempt to run the test with and without a real Redis
  and record what happens. If no live Redis is available, the
  Option C test falls back to a lighter form (stub the Redis
  calls, verify Option C still silent-passes by construction).

## Pre-committed questions

1. **Structural refactor cost.** How invasive is the inline-
   closure → named-func refactor? Does it feel idiomatic for a
   Vapor codebase, or does it jar against the framework's
   conventional style?
2. **`IdempotencyKey` construction path.** Does `init(fromAuditedString:)`
   end up being the primary path for this adopter (confirming
   the prediction), or does the type's API need a new
   constructor to fit a Codable request-body shape?
3. **Option C pathology on `HTTPStatus.ok`.** Does `#assertIdempotent`
   silently pass when wrapping a non-idempotent handler that
   returns `.ok` regardless? If yes, this is the predicted
   P0 issue.
4. **Compilation & build-time cost.** Did the package add
   meaningful build-time cost? Did the macro expansion produce
   confusing diagnostics at any point?

## Predicted outcome

- **Friction 1 (inline-closure refactor):** will manifest. Needs
  to be documented as a migration cost in the package README.
- **Friction 2 (non-Identifiable body):** `init(fromAuditedString:)`
  will be the only viable path. Confirms the "audit hatch is the
  primary" concern.
- **Friction 3 (JSON wire format):** `IdempotencyKey`'s bare-string
  Codable encoding should work cleanly. Low risk.
- **Option C pathology:** will silently pass. Documents the first
  P0 issue on the package's test-time guarantees — either Option A
  / B needs promotion before v0.1.0, or the README needs a much
  louder callout about Option C's limitations.
- **Build-time delta:** < 30s cold, < 2s incremental. Refutable.
- **Linter parity:** attribute form produces same diagnostic as
  doc-comment form. High confidence; tested in isolation already.

If all five predictions hold, the trial is a **successful
negative result** — it finds real issues that weren't visible
from the three self-authored examples. That's the point of the
trial.
