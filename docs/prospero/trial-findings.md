# Prospero — Trial Findings

## TL;DR

**Real-bug catch on a phase-2 / single-contributor / Hummingbird
target — 7-for-7 macro-surface coverage maintained**, and
**second consecutive plateau round (Completion Criterion #2 now
2/3)**. One real-bug shape surfaced: `ActivityPattern.save(on:)`
in the POST /patterns create handler is a duplicate-insert bug —
the Migration has no unique constraint, so retry creates
duplicates with fresh UUIDs. Maps cleanly to
`@ExternallyIdempotent(by:)`, same shape as isowords'
`insertSharedGame` catch.

**Key usability finding**: the enclosing-function annotation
workaround for Hummingbird's trailing-closure handler shape
**works well**. The linter's body walk traverses trailing closures
inside an annotated function, so `/// @lint.context replayable`
on `addPatternRoutes(to router:, ...)` catches all `.save(on:)` /
`.delete(on:)` / service calls inside the 7 enclosed
`router.get/post { ... }` closures. This is a significant
disconfirmation of the "unlikely on non-Lambda corpus" prediction
in
[`ideas/inline-trailing-closure-annotation-gap.md`](../ideas/inline-trailing-closure-annotation-gap.md)
— trigger #2 met, but severity is LOWER than predicted because
the workaround works.

**New evidence-accumulating candidate**: 14 Run B fires on
Hummingbird Router DSL methods (`router.get` × 11, `router.post`
× 3) — route-registration calls, not HTTP calls. Prime candidate
for a framework whitelist gated on `import Hummingbird`
(`(nil, "get" | "post" | "put" | "patch" | "delete")` on
`Router` / `RouterGroup` receivers). One-adopter evidence;
deferred, awaits second Hummingbird adopter or Vapor-route-DSL
analog.

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (`swift test` green
  at 2286/276).
- **Target:** `samalone/prospero` @
  `a1308b3b9b462a3b5b3bc9a0d7a464f71e767d50` → forked to
  `Joseph-Cursio/prospero-idempotency-trial` @ `trial-prospero`.
  - **Run A tip:** `353753f` (3 `addXRoutes` `@lint.context replayable`).
  - **Run B tip:** `56d676f` (same 3 fns `@lint.context strict_replayable`).
- **Scan corpus:** 29 Swift files under `Sources/Prospero/`.

## Run A — replayable context

**10 diagnostics.** Per-enclosing-function headline:

| addXRoutes function | Fires | Status |
|---|---|---|
| `addPatternRoutes` | 9 | 3× `router.post` (noise — DSL false positive), 2× `pattern.save` (1 real catch + 1 defensible), 1× `pattern.delete` (defensible), 3× `recomputeHues` (defensible) |
| `addForecastRoutes` | 1 | `meteoClient.fetchHourlyForecast` (defensible — idempotent GET) |
| `addCalendarRoutes` | 0 | silent (correct — read-only GET) |

**Function-level coverage: 2/3 (0.67).** Closure-level: 4/9
closures fire (the 5 silent ones are all read-only GETs — correct-
silent).

### Per-diagnostic audit (10 ≤ 30, full audit)

Ground-truthed against `Sources/Prospero/Migrations/` (Fluent
unique constraints — only `User.email` has one;
`ActivityPattern` does not) +
`Services/PatternHueService.swift` (recomputeHues body) +
`Services/OpenMeteoClient.swift` (fetch semantics).

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `PatternRoutes.swift:54` | `router.post` | **noise (shape-specific)** | Hummingbird router DSL — route registration, not HTTP call. Inferred non-idempotent because `post` is in the bare-name lexicon. Candidate for framework whitelist (see slot 16 below). |
| 2 | `PatternRoutes.swift:60` | `pattern.save(on: db)` | **correct catch / real bug** | Inside `POST /patterns` create handler. `ActivityPattern` Migration (`CreateActivityPatterns.swift`) has no `.unique(on:)` constraint — retry of the create handler inserts a second row with a fresh UUID. **Fix: `IdempotencyKey` on the form via hidden input, `@ExternallyIdempotent(by: "idempotencyKey")` on the request type**, or migration-level `.unique(on: "user_id", "name")` at SQL layer. |
| 3 | `PatternRoutes.swift:61` | `hueService.recomputeHues` | **defensible** | `recomputeHues(userID:)` reads all patterns, deterministically assigns hue positions via `HuePlacer.placePoints` (pure math), loops `pattern.save(on:)` on updated-by-PK models. Overwrite-idempotent: same input patterns + same algorithm → same final hue state. Adopter annotation `@lint.effect idempotent` (or `externally_idempotent(by: "userID")`) closes. |
| 4 | `PatternRoutes.swift:80` | `router.post` | **noise (shape-specific)** | Same as #1 (`POST /patterns/:id` route registration). |
| 5 | `PatternRoutes.swift:94` | `pattern.save(on: db)` | **defensible** | Inside `POST /patterns/:id` update handler. Pattern is fetched by ID first (`:81-85`), then `input.apply(to: pattern)` + `save`. Fluent `.save()` on a model with an existing PK is an UPDATE, not INSERT — overwrite-idempotent. |
| 6 | `PatternRoutes.swift:96` | `hueService.recomputeHues` | **defensible** | Same shape as #3. |
| 7 | `PatternRoutes.swift:101` | `router.post` | **noise (shape-specific)** | Same as #1 (`POST /patterns/:id/delete` route registration). |
| 8 | `PatternRoutes.swift:110` | `pattern.delete(on: db)` | **defensible** | Inside delete handler; pattern fetched by ID first. Fluent `.delete()` on a found model is idempotent (re-delete of already-gone row = no-op or trapped error). |
| 9 | `PatternRoutes.swift:111` | `hueService.recomputeHues` | **defensible** | Same shape as #3. |
| 10 | `ForecastRoutes.swift:32` | `meteoClient.fetchHourlyForecast` | **defensible** | External API GET (Open-Meteo). HTTP GET is idempotent; same `(latitude, longitude)` returns same forecast. Adopter annotation closes. |

### Run A tally

- **Correct catches (real bugs with concrete fix shape):** **1** (position 2)
- **Defensible:** **6** (positions 3, 5, 6, 8, 9, 10)
- **Noise (shape-specific — Hummingbird Router DSL):** **3** (positions 1, 4, 7)
- **Missed real bugs:** **0 known** (SQL ground-truth pass confirmed `ActivityPattern` has no unique constraint, so the save-on-create is the only duplicate-insert shape in scope).

**Precision (real-bug catches ÷ fires):** 1/10 = **10%**. 
**Recall:** 1/1 = **100%** (the one known bug was caught). 
**Noise-adjusted precision (excluding shape-specific DSL
noise):** 1/7 = **14%**.

### SQL ground-truth pass applied

Per slot-15 template addition:

- **`User`** (`Migrations/CreateUsers.swift:12`): `.unique(on: "email")`.
- **`ActivityPattern`** (`Migrations/CreateActivityPatterns.swift`):
  **no unique constraint** — natural key candidates are
  `(user_id, name)` but neither alone nor in combination is
  constrained. Retry of POST /patterns inserts duplicates.
  Confirmed real-bug shape #2 above.

Pass took ~5 minutes on this 6-migration codebase. Template
pays off cleanly.

## Run B — strict_replayable context

**62 diagnostics.** Rule distribution: **10
`[Non-Idempotent In Retry Context]`** (Run A positions restated
+ nothing new from strict walk of those 10) + **52
`[Unannotated In Strict Replayable Context]`**. Exceeds 30-
diagnostic audit cap; decomposed by cluster.

### Cluster decomposition

| Cluster | Count | Shape | Verdict |
|---|---|---|---|
| **Hummingbird Router DSL (new)** | 14 | `router.get` (11), `router.post` (3) | **New cluster — one-adopter evidence for slot 16.** Route-registration DSL methods; false positives / unannotated-under-strict. Not seen in prior rounds (Penny/SPI-Server use different handler shapes; isowords uses HttpPipeline not Hummingbird router). |
| **Type ctors / static factories** | 28 | `PageContext` (5), `redirect` (3), `TideClient` (2), `URLEncodedFormDecoder` (2), `PatternMatcher` (2), `PatternFormPage` (2), `OpenMeteoClient` (2), `ForecastAssembler` (2), plus 1-count ctors (`TideStationsService`, `Response`, `PatternListPage`, `PatternHueService`, `PageLayout`, `init`, `ForecastResultsPage`, `CalendarView`, `toModel`) | Cross-adopter recurrence of the type-ctor-gap cluster (same shape as Lambda/isowords/SPI-Server residuals). No new slice. |
| **Stdlib helpers / domain lookups** | 13 | `sort` (4), `mountURL` (3), `decode` (2), `findWindows` (1), `assemble` (1), `apply` (1), `PatternMatcher` (already counted — decomposed correctly) | Stdlib / domain-lookup cluster. No new shape. |
| **Real business calls** | 7 | `recomputeHues` (3), `save` (2), `delete` (1), `fetchHourlyForecast` (1) | Run A positions — defensible + 1 real catch. |

Sum: 14 + 28 + 13 + 7 = **62** ✓

### Trailing-closure workaround effectiveness

Notable: the `addXRoutes` enclosing-function annotation walked
into **all 7 trailing-closure handlers** inside
`PatternRoutes.swift`, producing diagnostics on their internal
calls. **The linter treats closure literals inside an annotated
function's body as part of the same analysis scope.** This makes
the "named-function workaround" viable for Hummingbird Router-
DSL adopters — without this behaviour, the trailing-closure gap
would genuinely block coverage. Updates the
[trailing-closure-annotation-gap idea doc](../ideas/inline-trailing-closure-annotation-gap.md)
accordingly.

## Pre-committed question answers

**Q1 — Does Hummingbird's `040f186` whitelist cover prospero's
surface?** **Not relevant — the 040f186 whitelist was for
Hummingbird's `handle`/`run` shapes on application/service types;
prospero's primary shape is `router.get/post { ... }` closures
within `addXRoutes` helpers. Different surface, no overlap with
the existing whitelist.** The new cluster (14 fires on
`router.get`/`router.post`) argues for a separate Router-DSL
whitelist (slot 16 candidate below).

**Q2 — Does the enclosing-function annotation workaround work?**
**Yes, cleanly.** All internal calls inside trailing closures are
walked. 9 diagnostics from a single annotation on
`addPatternRoutes`; behaves identically to a handler-level
annotation for inference purposes. Caveat: the tier applies
uniformly to *all* closures inside the annotated function, so
this workaround doesn't support per-route tier differentiation
(e.g. a function containing both `replayable` POSTs and
`observational` GET health-checks would need splitting into
separate `addXRoutes` helpers, or a refactor to named handler
functions).

**Q3 — Is there a real-bug shape?** **Yes — 1 catch** on
`ActivityPattern.save` in POST /patterns create handler.
Migration lacks unique constraint; retry creates duplicates.
Maps to `@ExternallyIdempotent(by:)` — **7-for-7 cross-adopter
shape coverage**. The bug's severity is low (UI-visible: user
sees two identical patterns in their list) but the shape is
exactly the isowords `insertSharedGame` pattern — same fix path.

**Q4 — Plateau round?** **Yes.** Advances Completion Criterion
#2 to **2/3 consecutive plateaus**. Reasoning: the new cluster
(slot 16 Hummingbird Router DSL) is evidence-accumulating
(1-adopter), same class as SPI-Server's `AppMetrics.push`
candidate — not a "named adoption-gap slice" in the Criterion #2
sense, just a deferred candidate.

## Comparison to prior rounds

| Metric | Penny (prod #1) | isowords (prod #2) | SPI-Server (prod #3) | **Prospero (prod #4)** |
|---|---|---|---|---|
| Framework | AWS Lambda + DynamoDB | Vapor + PostgreSQL | Vapor + Fluent + PG | **Hummingbird 2 + Fluent + PG/SQLite** |
| Handler shape | `Handler.handle` | `func …Middleware(_ conn:)` | `AsyncCommand.run` | **trailing-closure in `addXRoutes`** |
| Handlers annotated | 5 | 5 | 5 | **3 enclosing fns (9 closure handlers)** |
| Run A fires | 20 | 8 | 7 | **10** |
| Run A real-bug catches | 10 | 2 | 0 | **1** |
| Run A real-bug shapes (new) | 4 | 2 | 0 | **0** (existing duplicate-insert shape) |
| Run A defensible | 6 | 5 | 3 | **6** |
| Run A noise | 1 | 1 | 4 (AppMetrics.push) | **3 (Router DSL post)** |
| Run A handler coverage | 5/5 | 5/5 | 4/5 | **5/9 closures (correct-silent 4)** |
| Run B count | 71 | 162 | 39 | **62** |
| Run B new cluster shapes | 0 | slot 13 (landed) | 0 | **1 — Hummingbird Router DSL (slot 16 candidate, deferred)** |
| New adoption-gap slices (named) | slot 12 (landed) | slot 13 (landed) | 0 — **plateau** | 0 — **plateau** |
| Framework whitelist candidate | 0 | slot 14 (HttpPipeline, deferred) | AppMetrics.push (evidence-accumulating) | slot 16 (Router DSL, evidence-accumulating) |
| IdempotencyKey / @Externally coverage | 4/4 | 2/2 | 0/0 | **1/1** |

**Across-round tally:** 7/7 real-bug shapes (was 6/6) resolvable
via `IdempotencyKey` / `@ExternallyIdempotent(by:)`. 4 production
adopters. **Completion Criterion #2 now at 2/3 consecutive
plateau rounds.** One more zero-named-slice round satisfies the
"adoption-gap stability" ship criterion.

## Links

- **Scope:** [`trial-scope.md`](trial-scope.md)
- **Retrospective:** [`trial-retrospective.md`](trial-retrospective.md)
- **Run A transcript:** [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- **Run B transcript:** [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- **Fork:** [`Joseph-Cursio/prospero-idempotency-trial`](https://github.com/Joseph-Cursio/prospero-idempotency-trial)
- **Trial-branch tips:** `353753f` (Run A), `56d676f` (Run B)
