# HelloVapor — Trial Findings

Second-adopter corroboration for slot 17. See
[`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions.

## Run A — replayable context

Linter: `SwiftProjectLint` @ `29e9069` · Target: fork tip
`05e5433` (annotation = `/// @lint.context replayable`). Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**Total: 5 diagnostics, all in `Sources/HelloVapor/routes.swift`.**

| # | Line | Callee | Rule | Verdict | Notes |
|---|---|---|---|---|---|
| 1 | 32 | `post` | `nonIdempotentInRetryContext` | **slot-17 candidate** | `app.post("api", "acronym")` registration site. Same bare-name heuristic as luka-vapor — confirms shape. |
| 2 | 38 | `register` | `nonIdempotentInRetryContext` | **sibling-candidate** | `app.register(collection: TodoController())`. `register` is in slot-13's prefix lexicon. 1-adopter evidence for `(app, register) → Vapor` pair. |
| 3 | 39 | `register` | `nonIdempotentInRetryContext` | **sibling-candidate** | `app.register(collection: MockAPIController())`. |
| 4 | 40 | `register` | `nonIdempotentInRetryContext` | **sibling-candidate** | `app.register(collection: ImageGeneratorController())`. |
| 5 | 41 | `register` | `nonIdempotentInRetryContext` | **sibling-candidate** | `app.register(collection: FakeDataController())`. |

**Yield.** 5 catches / 6 annotated handlers (counting `app.register`
shape as a handler) = 0.83 aggregate; 5 catches / 1 non-silent
handler (the 5× `app.get` are all silent because `get` is
idempotent-by-prefix-lexicon) = conceptually wrong — the yield
metric isn't meaningful when the fires don't cluster on
handler-body work. The bulk of fires are registration-DSL noise,
not handler-body catches.

**Slot-17 evidence.** 1× `app.post` fire, matching luka-vapor's
receiver-agnostic bare-name heuristic. **Confirmed: shape is
corpus-independent.**

**Sibling-pair candidate:** `(app, register) → Vapor` — 1-adopter,
4 fires. Evidence sits below the 2-adopter ship threshold; log for
next-round observation. Note: luka-vapor has zero
`register(collection:)` calls, so this is genuinely 1-adopter at
present.

## Run B — strict_replayable context

Linter: `SwiftProjectLint` @ `29e9069` · Target: fork tip
`4b2bea2` (annotation flipped to `/// @lint.context strict_replayable`).
Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Total: 25 diagnostics** (5 `[Non-Idempotent In Retry Context]`
carried from Run A + 20 `[Unannotated In Strict Replayable
Context]` strict-only). Under 30-line audit cap.

### Carried from Run A (5)

`post` ×1 + `register` ×4. No reshuffle.

### Strict-only clusters (20)

| Cluster | Fires | Callees | Verdict | Notes |
|---|---|---|---|---|
| `(app, get)` registration | 5 | `get` (lines 6, 10, 14, 19, 25) | **slot-17 candidate** | All 5 `app.get` inline-closure registration sites. Silent under replayable (prefix-lexicon classifies `get` as idempotent) but fire under strict because no explicit annotation exists. **Confirms the luka-vapor strict-mode asymmetry.** |
| Vapor `.description()` chain | 5 | `description` (lines 10, 14, 18, 25, 32) | **new 1-adopter candidate — observational** | `.description("...")` chained on `RouteBuilder` — Vapor's OpenAPI-metadata helper. Purely observational (attaches a string to the route for docs). 1-adopter evidence for `(Route, description) → Vapor` pair. Defer to 2-adopter evidence. |
| Controller ctors | 4 | `TodoController`, `MockAPIController`, `ImageGeneratorController`, `FakeDataController` | **type-ctor-gap** | Same cross-adopter cluster as luka-vapor / spi-server / isowords. Phase-3 work. |
| `parameters.get` | 1 | `get` (line 18) | **1-adopter candidate** | `req.parameters.get("name")` on line 18. Same shape as prospero's 5-fire `(parameters\|queryParameters, get)` cluster from slot 16's trial. **Second adopter for this sibling pair** — prospero (Hummingbird) + hellovapor (Vapor) — but gated on different imports, so the shape generalises across frameworks but not as a single whitelist entry. Log for cross-framework observation. |
| Stdlib codec | 2 | `decode` ×2 | **stdlib-gap** | `req.content.decode(Acronym.self)` / `decode(InfoData.self)`. Cross-adopter. |
| Fluent write | 1 | `save` (line 33) | **correct catch** | `acronym.save(on: req.db)` inside `app.post("api", "acronym")` handler. **Real-bug candidate — see SQL pass below.** |
| Vapor primitives | 2 | `render`, `Abort` | **type-ctor-gap / observational** | `req.view.render("index", ...)` — Leaf template render, observational. `Abort(.badRequest, ...)` — Vapor HTTP error ctor, type-ctor-gap. |

### SQL ground-truth pass (Fluent)

`CreateAcronym` migration at `Sources/HelloVapor/Migrations/CreateAcronym.swift`
declares three fields (`short`, `long`, `created_at`) with no
`.unique(on:)` constraint. **No DB-level dedup.** Therefore:

- **`acronym.save(on: req.db)` at `routes.swift:33` — correct
  catch, real bug.** Retry = duplicate row with identical
  `short`/`long` content. Maps to `@ExternallyIdempotent(by:
  "<caller-supplied-idempotency-key>")` or an adopter-level
  `Acronym.query(on:).filter(\.$short == body.short).first()`
  guard before `save`.

## Cross-adopter tally update (post-HelloVapor)

**Real-bug shapes: 10-for-10 across 6 production-app adopters.**

| Adopter | Shape | Macro surface |
|---|---|---|
| Penny | coin double-grant | `IdempotencyKey` |
| Penny | OAuth error-path duplication | `@ExternallyIdempotent(by:)` |
| Penny | sponsor DM duplication | `@ExternallyIdempotent(by:)` |
| Penny | GHHooks error-path | `@ExternallyIdempotent(by:)` |
| isowords | `insertSharedGame` dup-insert | `@ExternallyIdempotent(by:)` |
| isowords | `startDailyChallenge` dup-insert | `@ExternallyIdempotent(by:)` |
| prospero | `ActivityPattern.save` on create | `@ExternallyIdempotent(by:)` |
| myfavquotes-api | `UsersController.login` token persist | `IdempotencyKey` |
| luka-vapor | `sendEndEvent` APNS duplicate push | `@ExternallyIdempotent(by:)` |
| **hellovapor** | **Acronym create without unique constraint** | **`@ExternallyIdempotent(by:)`** |

## Comparison to predicted outcome

| Prediction | Actual | Match? |
|---|---|---|
| Run A: 1 `app.post` + 4 `register` = 5 | 1 + 4 = 5 | ✅ exact |
| Run B: 5 × `app.get` strict-only | 5 | ✅ exact |
| Run B: 20-30 strict-only total | 20 | ✅ lower bound |
| `Acronym.save` without unique constraint | confirmed correct catch | ✅ |

All four predictions hit. Cleanest-match findings doc this round.

## Answers to pre-committed questions

1. **`app.post` reproduction.** Yes — single `app.post("api",
   "acronym")` fires under replayable via identical bare-name
   heuristic. Shape confirmed corpus-independent.
2. **`app.get` strict-mode asymmetry.** Yes — all 5 `app.get`
   registrations fire under strict_replayable but silent under
   replayable. Confirms luka-vapor's asymmetry generalises. Slot
   17 scope is **5 verbs** (`get|post|put|patch|delete`) matching
   slot 16.
3. **Acronym save.** Real-bug shape: no unique constraint on
   `short` in `CreateAcronym` migration. 10-for-10 macro-surface
   coverage.
4. **`(app, register)` sibling-pair evidence.** 4 fires, 1-adopter
   (hellovapor only). Deferred; does not ship with slot 17.

## Slot-17 2-adopter evidence summary

Combined evidence across luka-vapor + hellovapor:

| Adopter | Replayable fires | Strict-only extra | Total slot-17-shape |
|---|---|---|---|
| luka-vapor | 2× `app.post` | 1× `app.get` | 3 |
| hellovapor | 1× `app.post` | 5× `app.get` | 6 |
| **Combined** | **3** | **6** | **9** |

Shape consistency across adopters: identical. Bare-name heuristic
fires on `post|put|patch|delete` under replayable; every verb
fires under strict without an explicit annotation. A 5-entry
receiver-method pair `(app, get|post|put|patch|delete) → Vapor`
silences all 9 fires cleanly across both tiers. **Slot 17 is
ship-eligible.**
