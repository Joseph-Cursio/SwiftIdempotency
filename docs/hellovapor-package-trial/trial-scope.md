# hellovapor — Package Integration Trial Scope

Second package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
Deliberate counter-case to the
[luka-vapor trial](../luka-vapor-package-trial/trial-scope.md):
luka-vapor's handler returns `HTTPStatus.ok` (trivial return,
stresses Option C pathology). HelloVapor's target returns an
`Acronym` Fluent model — a non-trivial, Identifiable return
type. This trial asks the inverse question: when the return type
reflects state, does the macro surface work as designed?

## Research question

> **On a Vapor handler with a non-trivial Identifiable return
> type (Fluent `Acronym` Model), does the `SwiftIdempotency`
> macro surface catch non-idempotency — the "happy path" where
> Option C's return-equality check has teeth — and does
> `IdempotencyKey(fromEntity:)` become reachable now that the
> adopter's domain type is Identifiable?**

## Pinned context

- **SwiftIdempotency tip:** `34cd52f` (post-luka-vapor-trial
  README updates: Option C pathology section, inline-closure
  migration guide, `SwiftIdempotencyTestSupport` stale-ref fix).
- **SwiftProjectLint tip:** `db4d576` (post-slot-18 merge).
- **Upstream target:** `sinduke/HelloVapor` @ `87fa436` (main,
  2026-04-20, "[Fix] 修复 Docker 真实编译测试路径"). Unchanged
  from the linter-trial pin.
- **Trial fork:** `Joseph-Cursio/HelloVapor-idempotency-trial`
  (already exists from the linter trial; PR #1 to the upstream
  sits separately and is orthogonal to this branch).
- **Trial branch:** `package-integration-trial`, forked from
  upstream `main` tip `87fa436`. Sibling to the existing
  `trial-hellovapor` branch (linter trial); they share no state.

## Migration plan

**Target: `app.post("api", "acronym")` handler** in
`Sources/HelloVapor/routes.swift:31-35`.

Current shape (upstream):

```swift
app.post("api", "acronym") { req async throws -> Acronym in
    let acronym = try req.content.decode(Acronym.self)
    try await acronym.save(on: req.db)
    return acronym
}.description("Create a new acronym.")
```

Target shape (post-migration):

```swift
// In Sources/HelloVapor/Handlers/CreateAcronym.swift (new file):
@ExternallyIdempotent(by: "idempotencyKey")
func createAcronym(
    req: Request,
    acronym: Acronym,
    idempotencyKey: IdempotencyKey
) async throws -> Acronym {
    try await acronym.save(on: req.db)
    return acronym
}

// In Sources/HelloVapor/routes.swift:
app.post("api", "acronym") { req async throws -> Acronym in
    let acronym = try req.content.decode(Acronym.self)
    let keyString = req.headers.first(name: "Idempotency-Key")
        ?? acronym.short  // fallback: use natural business key
    let key = IdempotencyKey(fromAuditedString: keyString)
    return try await createAcronym(
        req: req,
        acronym: acronym,
        idempotencyKey: key
    )
}.description("Create a new acronym.")
```

**Idempotency-key sourcing decision:** an `Idempotency-Key` HTTP
header is the REST-idiomatic placement (Stripe's convention). It
sits outside the decoded `Content` so adding it doesn't force a
wrapper-type change to the `Acronym` decode path. The trial
accepts the natural-business-key fallback (the `short` field) so
clients that don't pass the header still get deterministic
dedup.

## Test plan

Three test shapes to add in `Tests/HelloVaporTests/`:

1. **`#assertIdempotent` on Fluent-Model-returning handler —
   the happy-path counter-case.** A handler that saves then
   returns the saved entity produces different `Acronym` objects
   on each call (different `id` UUID because Fluent generates
   it at save time). Two questions:
   - Does `Acronym` work as an `#assertIdempotent` return? It's
     a `final class` with no explicit `Equatable` conformance —
     we expect this to surface a compile-time requirement that
     Fluent models rarely meet.
   - If a workaround is needed (comparing tuple of value fields,
     or an `Equatable`-conformance extension on Acronym), how
     invasive is it?
2. **`IdempotencyKey(fromEntity:)` on the Acronym model.**
   Fluent's `@ID var id: UUID?` makes Acronym nominally
   Identifiable, but the id is Optional and pre-save is nil. Test
   whether the constructor is reachable pre-save (expected:
   precondition failure or similar) and post-save (expected:
   clean stable key). Surfaces a real ergonomic question for
   create handlers.
3. **`IdempotencyKey` + Idempotency-Key header flow.** Confirm
   that the header-sourced flow works end-to-end through a
   VaporTesting test harness if available, or at minimum through
   a direct function call with a mocked Request.

## Scope commitment

- **One handler, three tests.** No other controllers migrated.
  The `TodoController`, `MockAPIController`, etc. stay on their
  current shape.
- **No upstream PR.** This is measurement work on the fork only.
  PR #1 (Acronym unique constraint) is orthogonal.
- **Fluent database setup:** Fluent SQLite driver is used in
  existing tests (`fluent-sqlite-driver` in Package.swift).
  Tests can use an in-memory SQLite DB; no external services.

## Pre-committed questions

1. **Option C sharpness on Fluent Model returns.** Does `Acronym`
   (non-Equatable `final class`) compile as an `#assertIdempotent`
   return? If not, what's the adopter's workaround shape, and
   is it sharper than the luka-vapor `HTTPStatus.ok` pathology?
2. **`IdempotencyKey(fromEntity:)` reachability on Fluent Models.**
   Does the constructor work on `Acronym` with Optional `id`?
   Pre-save (nil id) vs. post-save (set id) behaviour.
3. **Header-vs-body idempotency-key placement.** Does the
   REST-idiomatic header placement produce a cleaner migration
   than luka-vapor's body-field approach? And does it work with
   Vapor's `Request.headers` API cleanly?
4. **Cross-adopter refactor cost.** luka-vapor cost 67→8 line
   closure + new 75-line handler file. Is HelloVapor's refactor
   comparable in magnitude, or does the Fluent shape make it
   lighter/heavier?

## Predicted outcome

- **Friction 1 (inline-closure refactor):** will manifest again.
  Same shape as luka-vapor, likely lighter because the handler
  body is only 4 lines. Confirms the friction is structural
  (across adopters), not adopter-specific.
- **Friction 2 (`Acronym` not Equatable):** will manifest. The
  test won't compile as-written; the adopter will need to either
  (a) add `Equatable` conformance on Acronym (invasive — affects
  the model's public API), (b) compare tuple of value fields, or
  (c) skip `#assertIdempotent` on this handler and rely on
  SwiftProjectLint's static check. **P0 or P1 finding** depending
  on which workaround is tractable.
- **Friction 3 (`fromEntity:` on Optional id):** Acronym's `id`
  is nil pre-save. `fromEntity(acronym)` before save probably
  produces a bad key (`"Optional(nil)"` or precondition failure).
  Post-save works but is useless for a create handler (you've
  already done the side effect). **Likely P1 finding** — the
  constructor is reachable only in shapes where the key is no
  longer useful.
- **Header-based key flow:** works cleanly. The REST-idiomatic
  pattern is the one most adopters will reach for; confirming
  it works through the package's API is the primary positive
  finding.
- **Build-time delta:** ~0s cold. Predicted from luka-vapor's
  ~0s result; the plugin is amortised once.
- **Linter parity:** holds. High confidence.

If all predictions hold, the trial produces a **stronger
counter-case** to luka-vapor: three new P0/P1 findings around
return-type sharpness and `fromEntity:` reachability on real
adopter domain types. The combined picture (luka-vapor's
trivial-return pathology + HelloVapor's non-Equatable-class
return) is that **Option C works cleanly on structs with
synthesised Equatable and nowhere else** — a tighter statement
than either trial alone produces.
