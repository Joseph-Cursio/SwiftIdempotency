# myfavquotes-api — Trial Retrospective

## Did the scope hold?

**Yes, with one tactical scope-narrowing call surfaced mid-round.**

- Source-edit ceiling: ≤ 4 files. **Actual: 3** (README banner +
  QuotesController + UsersController). Migration files weren't
  touched — SQL ground-truth was a read-only audit.
- Audit cap: 30 diagnostics. **Actual: 13 Run B (full audit
  comfortable).**
- Measurement-only: held. Only annotation comments + README banner
  changes pushed.

**Mid-round narrowing**: scope doc proposed possibly annotating the
`addRoutes(to:)` registration helpers to test slot 16 evidence.
Rejected during execution — annotating registration helpers
inflates fire counts on `RouterGroup.get/post` chain calls
(non-real-bug noise) without surfacing real-bug shapes that the
6 `@Sendable func` annotations don't already cover. The handler-
body annotations were the right scope; slot 16 evidence is a
separate question, deferred.

## Q1 — Does `RouterGroup.get/post` fire the same slot 16 shape as prospero's `Router.get/post`?

**Untested this round.** The slot 16 evidence shape requires
annotating the *enclosing* registration helper (e.g. prospero's
`addPatternRoutes`). myfavquotes-api's `addRoutes(to group:)`
helpers were not annotated — only the 6 handler methods themselves
were. Result: zero `RouterGroup.get/post` calls appeared in any
annotated context's call graph.

Slot 16 stays at **1-adopter (prospero)**. Promotion to 2-adopter
would require either:

- A future Hummingbird adopter that exhibits inline trailing closure
  handlers (matching prospero's primary handler shape), OR
- A retro-pass on this fork annotating `addRoutes(to:)` in addition
  to the 6 handlers, to compare shapes head-to-head.

This was a deliberate scope choice. The handler-body shape is
where real-bug evidence lives. Inflating Run B with slot 16 noise
to push 1→2 adopters on a deferred slice would have muddied the
plateau call.

## Q2 — Does method-reference handler binding (`use: self.create`) walk into the function body?

**Yes — perfectly clean.** All 5 of Run A's diagnostics fired on
handler-body call sites via the `/// @lint.context replayable`
doc-comments attached to the `@Sendable func index/create/update/
delete/login` declarations. The chain:

```swift
group.get(":id", use: self.show)        // <- registration call site
                                         // (NOT the diagnostic surface)
@Sendable func show(...) async throws { // <- annotated; body walked here
    try await Quote.find(...)            // <- diagnostic fires here
}
```

The doc-comment binds to the named decl. The inferrer walks the
method body. Method-reference binding doesn't break this. **Not
an adoption gap.** This is materially different from prospero's
inline trailing closure shape (where the closure body needs the
enclosing function annotation to be reachable). The two patterns
exercise different paths through the visitor.

Adoption note worth documenting in the road_test_plan: when the
adopter uses **method-reference binding** (Hummingbird's `use:` API
shape), prefer annotating the handler methods. When the adopter
uses **inline trailing closure handlers** (prospero shape, also
Vapor's `app.get { req in ... }`), prefer annotating the enclosing
registration function. Both produce useful diagnostics; the choice
is a pattern-match, not a correctness one.

## Q3 — Real-bug catch?

**Yes — 1.** `UsersController.login` (`Sources/App/Controllers/
UsersController.swift:46-52`):

```swift
@Sendable func login(_ request: Request, context: UserContext) async throws -> Token {
    let user = context.user
    let token = try Token.generate(for: user)              // <- random per call
    try await persist.create(key: "\(token.tokenValue)",   // <- new key per retry
                             value: token,
                             expires: .seconds(3600))
    return token
}
```

`Token.generate` (per `Sources/App/Models/Token.swift:27-31`):

```swift
static func generate(for user: User) throws -> Token {
    let random = (1...8).map( {_ in Int.random(in: 0...999)} )
    let tokenString = String(describing: random).toBase64()
    return try Token(tokenValue: tokenString, userID: user.requireID())
}
```

Eight calls to `Int.random` per invocation → fresh `tokenValue`
per call → fresh persist-driver key per retry. A flaky network
that retries `/login` 3× leaves 3 stale token entries in the
persist store, each with a 1-hour TTL. The client receives a
different bearer token on each retry; the *latest* response wins
client-side, but the *earlier* tokens remain valid for an hour
against the server.

This is a textbook `IdempotencyKey` case:

```swift
// Suggested fix shape (NOT implemented this round — measurement-only):
@Sendable func login(_ request: Request,
                     context: UserContext,
                     idempotencyKey: IdempotencyKey) async throws -> Token {
    if let existing = try await persist.get(key: idempotencyKey.rawValue) {
        return existing  // return same token on retry
    }
    let token = try Token.generate(for: context.user)
    try await persist.create(key: "\(token.tokenValue)",
                             value: token,
                             expires: .seconds(3600))
    try await persist.set(key: idempotencyKey.rawValue,
                          value: token,
                          expires: .seconds(3600))
    return token
}
```

**8th cross-adopter real-bug shape mapping cleanly to the
`IdempotencyKey` / `@ExternallyIdempotent(by:)` macro surface** —
8/8 across all production adopters.

## Q4 — Plateau round?

**YES.** Run B Bcrypt-crypto-gap (1 fire) and fluent-finder-gap
(2 fires of `find`) and fluent-getter-gap (1 fire of `requireID`)
are all single-fire shapes that don't reach slice volume. Each
fits the existing "stdlib/framework-gap defensible-by-design"
bucket — the same bucket that holds `Duration.seconds`,
`Type.init(...)`, etc. across prior rounds. No new *named*
adoption-gap slice is scored.

**Completion Criterion #2 (adoption-gap stability — three
consecutive plateaus) advances 2/3 → 3/3.** Adoption-gap stability
SHIP CRITERION CLOSED.

Status of the three completion criteria from `road_test_plan.md`:

1. **Framework coverage**: Vapor (todos-fluent + SPI-Server +
   pointfreeco), Hummingbird (prospero + myfavquotes-api),
   SwiftNIO (swift-nio), Point-Free (pointfreeco + TCA). ✅
   **Met** since prospero round.
2. **Adoption-gap stability**: 3/3 consecutive plateaus
   (spi-server + prospero + myfavquotes-api). ✅ **Met this round.**
3. **Macro-form evidence**: idempotency-tests-sample +
   assert-idempotent-sample + webhook-handler-sample exercise
   `@IdempotencyTests` / `#assertIdempotent` / `IdempotencyKey`
   end-to-end; root tests cover `@Idempotent` /
   `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent`.
   ✅ **Met.**

**All three road-test completion criteria are now met.**

## What would have changed the outcome

- **If the corpus included inline trailing closure handlers:**
  slot 16 would have fired and accumulated 2-adopter evidence,
  promoting that slice to ship-eligible. Adam Fowler's
  hummingbird-examples typically uses method-reference binding;
  the inline-closure shape is more common in tutorial code (which
  prospero leans into). myfavquotes-api leans toward the
  hummingbird-examples convention.
- **If `Quote.unique(on: "quote_text")` were absent:** the
  `quote.save(on:)` diagnostic would have flipped to a real-bug
  catch. The unique constraint is a single line in
  `CreateQuoteTableMigration.swift` — a reminder that DB-schema
  defaults can flip the entire correctness story for an adopter.
  This is exactly the value of the SQL ground-truth pass.
- **If `Token.generate` used a deterministic-by-user-and-day token
  shape (e.g. HMAC of `userID + dayOfYear`):** the login catch
  would have been a false positive. The fact that it uses 8×
  `Int.random` makes it a true catch — the linter inferred
  correctly because the call graph never reaches the random
  source, just the persist.create on the resulting non-deterministic
  key.

## Cost summary

| Phase | Estimate | Actual |
|---|---|---|
| Scout target (parkAPI gone, switched to myfavquotes-api) | 5 min | ~10 min (search + verify) |
| Pre-flight (linter green check, fork provision, harden, banner) | 10 min | ~8 min |
| Scope doc | 15 min | ~12 min |
| Annotate 6 handlers + commit + push | 5 min | ~5 min |
| Run A scan + audit | 10 min | ~5 min (small corpus) |
| Run B scan + audit + SQL ground-truth | 15 min | ~10 min |
| Findings + retrospective | 30 min | ~20 min |
| **Total** | **~90 min** | **~70 min** |

**~25% under-budget.** Multi-package corpora setup (the recipe
addition from prior rounds) is now well-trodden — picking
`BearerAuthPersist` as the only annotated subpackage and scanning
just that subpackage avoided the multi-package shell-recipe
overhead.

## Policy notes (for road_test_plan.md)

**Two adoption-pattern observations worth folding into the template:**

### 1. Handler-binding shape determines annotation target

Adopters bind handlers to routes in two structurally distinct shapes:

- **Method-reference (`use:`)** — Hummingbird `RouterGroup.get(":id", use: self.show)`, Vapor `routes.get(":id", use: show)`. Annotate the *handler method* with `/// @lint.context …` on its `func` decl. The doc-comment attaches directly; the inferrer walks the method body. (myfavquotes-api shape.)
- **Inline trailing closure** — `router.get("/path") { req, ctx in … }`, common in tutorial code and prospero's prod app. The closure body has no named decl to attach to. Annotate the *enclosing registration function* (`func addXRoutes(to:)`); the inferrer walks the closures within. (prospero shape.)

Both produce useful diagnostics. Pick the matching shape. This is
already implicit in prior round retrospectives but worth surfacing
in the template proper.

### 2. `unique(on:)` constraint check is the SQL-ground-truth shortcut for Fluent adopters

For Postgres+Fluent adopters, the SQL ground-truth pass can short-
circuit on Fluent migrations: a `.unique(on: "<col>")` declaration
is the Swift-surface equivalent of a Postgres `UNIQUE` constraint,
which means INSERT-on-retry hits a DB-level reject. Both
myfavquotes-api migrations declare unique constraints — both
`create` handler diagnostics flip to defensible-by-design without
needing to read SQL.

Add to `road_test_plan.md` "SQL ground-truth pass" subsection
under DB-heavy adopters:

> For Fluent adopters specifically, check the migration `.unique(on:)`
> calls before reading SQL — Fluent compiles `.unique(on:)` to a
> Postgres `UNIQUE` constraint. If a `create` handler's model
> migration has `.unique(on: <natural-key>)`, the create-on-retry
> hits a DB-level dedup just like a raw `ON CONFLICT (...)
> DO NOTHING`. This shortcut covers most Fluent CRUD audits.

### 3. (Already in plan from isowords/prospero rounds — confirmed again)

Both prior policy items — SQL ground-truth pass mandatory for
DB-heavy adopters, git-lfs bypass clone — held this round
(myfavquotes-api uses neither LFS nor anything-other-than-SQL
for ground truth, so the existing recipe was sufficient).

## Data committed

- `docs/myfavquotes-api/trial-scope.md` — scope, pinned context,
  annotation plan, predictions
- `docs/myfavquotes-api/trial-findings.md` — Run A 5/6, Run B 13,
  cluster decomposition, cross-round tally, Q1-Q4 short answers
- `docs/myfavquotes-api/trial-retrospective.md` — this file
- `docs/myfavquotes-api/trial-transcripts/replayable.txt` — Run A
  raw output (5 issues)
- `docs/myfavquotes-api/trial-transcripts/strict-replayable.txt`
  — Run B raw output (13 issues)

Fork artifacts (under `Joseph-Cursio/myfavquotes-api-idempotency-trial`):

- `trial-myfavquotes` branch (default), tip `579c1a4`
  (Run B annotation state)
- Run A intermediate tip: `8ae0c78`
- Banner commit: `380a603`
