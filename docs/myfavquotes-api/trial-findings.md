# myfavquotes-api — Trial Findings

## Headline

**Plateau round — third consecutive zero-new-slice round.
Completion Criterion #2 (adoption-gap stability) advances to
3/3 → SHIP.** Run A 5/6 (one silent), Run B 13. **One real-bug
shape** (`UsersController.login` token persistence — observably
non-idempotent token generation, maps to `IdempotencyKey` /
`@ExternallyIdempotent(by:)`) — **8th cross-adopter real-bug
shape**, all 8 mapping to the macro surface.

Slot 16 (Hummingbird Router DSL whitelist) **did not gather
2-adopter evidence this round** — myfavquotes-api binds handlers
via method references (`.get(use: self.index)`), not inline
trailing closures, so `RouterGroup.get/post` calls didn't fire as
direct unannotated diagnostics. Slot 16 stays at 1-adopter
(prospero-only).

## Run A — replayable context

**6 handlers annotated, 5 fired, 1 silent. Yield: 5/6 = 0.83
including silent, 5/5 = 1.00 excluding silent.**

| # | File:line | Handler | Diagnostic | Verdict | Notes |
|---|---|---|---|---|---|
| 1 | `UsersController.swift:40` | `create` | `save` non-idempotent | **defensible by design** | `users` migration declares `unique(on: "email")` → DB-level reject on retry |
| 2 | `UsersController.swift:51` | `login` | `create` non-idempotent (persist.create) | **correct catch — real bug shape** | `Token.generate` uses `Int.random(in: 0...999)` × 8 → fresh token per call; persist.create writes a new entry under each random key. Maps to `IdempotencyKey` / `@ExternallyIdempotent(by: idempotencyKey)`. |
| 3 | `QuotesController.swift:58` | `create` | `save` non-idempotent | **defensible by design** | `quotes` migration declares `unique(on: "quote_text")` → DB-level reject on retry |
| 4 | `QuotesController.swift:86` | `update` | `save` non-idempotent | **defensible by design** | UPDATE-after-`Quote.find` on existing row; overwrite-idempotent semantics |
| 5 | `QuotesController.swift:103` | `delete` | `delete` non-idempotent | **defensible by design** | Delete-after-`Quote.find` returns 404 first time, success after; observably idempotent |

**Silent handlers (1):**
- `QuotesController.index` — `Quote.query(on:).all()` resolves to a pure read; no diagnostic.

**Per-handler audit:**
- All 5 fires are appropriate-by-shape. SQL ground-truth pass
  flips 4/5 to defensible (unique constraints + UPDATE/delete
  semantics).
- The login catch is the one *real* bug shape: every retry of
  POST `/api/v1/users/login` writes a new tokens entry under a
  fresh random key, so a flaky network → repeated requests creates
  N stale token entries (each TTL'd to 1h). Stale-token leak is
  observable, not just internal accounting.

## Run B — strict_replayable context

**13 total = 5 carried from Run A + 8 strict-only.**

### Carried from Run A

Same 5 lines, identical verdicts. Strict mode reframes the
`Non-Idempotent In Retry Context` rule as `In Strict Replayable
Context` but the diagnostic class stays `[Non-Idempotent In Retry
Context]`. No new information vs. Run A.

### Strict-only diagnostics (8)

All `[Unannotated In Strict Replayable Context]` — strict mode
demands every callee be provably idempotent / observational /
externally-keyed.

| # | File:line | Caller | Callee | Cluster | Verdict |
|---|---|---|---|---|---|
| 1 | `UsersController.swift:38` | `create` | `hash` (Bcrypt) | **Bcrypt-crypto-gap** (1-adopter) | defensible — Bcrypt.hash is non-deterministic by salt design; observationally safe (output never replayed externally); single fire, evidence-accumulating |
| 2 | `UsersController.swift:42` | `create` | `init` (EditedResponse) | type-ctor-gap | defensible — bare-ctor on response wrapper, no side effects |
| 3 | `UsersController.swift:42` | `create` | `Public` (User.Public) | type-ctor-gap | defensible — bare-ctor on DTO, pure |
| 4 | `UsersController.swift:51` | `login` | `seconds` (Duration) | stdlib-gap | defensible — `Duration.seconds(_:)` is pure value construction |
| 5 | `QuotesController.swift:56` | `create` | `Quote` (Quote init) | type-ctor-gap | defensible — bare-ctor on Fluent model, pure |
| 6 | `QuotesController.swift:56` | `create` | `requireID` (Fluent) | fluent-getter-gap | defensible — `IDProperty.requireID()` returns the stored UUID or throws; pure inspector |
| 7 | `QuotesController.swift:67` | `update` | `find` (Quote.find) | fluent-finder-gap | defensible — `Model.find(id, on:)` is a pure DB read |
| 8 | `QuotesController.swift:95` | `delete` | `find` (Quote.find) | fluent-finder-gap | defensible — same as #7 |

### Decomposition by cluster

| Cluster | Count | Status across rounds |
|---|---|---|
| type-ctor-gap | 3 | known cross-adopter (TCA, Lambda, isowords, prospero) — 1-2 fires per round; not a slice |
| fluent-finder-gap (`find`) | 2 | new shape but fires on a stdlib-style FluentKit static — same family as `find` getters across adopters |
| fluent-getter-gap (`requireID`) | 1 | same family as fluent-finder; trivial getter |
| stdlib-gap (`Duration.seconds`) | 1 | known cross-adopter (Lambda, TCA — `.milliseconds(100)` etc.) — not a slice |
| Bcrypt-crypto-gap (`hash`) | 1 | **new single-fire shape** — first crypto-primitive in any adopter; defensible-by-design but worth logging |

**No new named slice.** Every cluster either matches an existing
defensible-by-design pattern (type-ctor, stdlib, fluent
getter/finder) or is a single fire on a one-off primitive (Bcrypt)
that doesn't reach slice-promotion volume.

### Slot 16 (Hummingbird Router DSL) — no evidence this round

The `addRoutes(to group:)` registration functions in both
controllers were **not annotated** this round (the 6 handler
methods were the annotation surface). The chained
`group.get(use: self.index)` calls live inside `addRoutes`, so
they did not appear in any annotated context's call graph.

The relevant question — "would `RouterGroup.get/post` fire if
`addRoutes` were annotated?" — is answerable but not by this
round's setup. Slot 16 stays at **1-adopter (prospero)**;
promotion remains deferred until a Hummingbird adopter annotates
the enclosing route-registration helper (or an inline trailing
closure).

This is a deliberate scope choice, not an adoption gap: the
six method-handler annotations exercised the primary handler-body
surface, which is where real bugs live. Annotating the registration
helpers would have inflated the diagnostic count without adding
real-bug evidence.

## SQL ground-truth pass

`BearerAuthPersist` is Postgres-via-Fluent with two migrations:

```swift
// CreateQuoteTableMigration.swift
.unique(on: "quote_text")     // → quote create defensible

// CreateUserTableMigration.swift
.unique(on: "email")          // → user create defensible
```

Both `create` handlers (`UsersController.swift:40` and
`QuotesController.swift:58`) flip from "correct catch" to
"defensible by design" under SQL ground-truth. Without this pass,
the round would have mis-scored 3 real-bug catches; with it, the
real-bug count is **1** (`login`).

This is the **third round** validating the SQL ground-truth pass
template addition (after isowords' Run A 3-flip, prospero's
ActivityPattern review). The pass is now a load-bearing part of
DB-heavy adopter audits.

## Comparison to predicted outcome (from scope doc)

| Prediction | Actual | Verdict |
|---|---|---|
| 1 real-bug catch (login token gen) | 1 (login persist.create on random key) | ✅ exact |
| 6-12 Run A fires | 5 | ✅ within range (low end — `index` was the only silent) |
| 30-50 Run B fires | 13 | ❌ **far below** prediction; corpus is smaller than prospero's and the strict-mode "uninferrable callees" tail is correspondingly thinner |
| No new framework slice | confirmed — 0 new slices | ✅ |
| Slot 16 RouterGroup.get/post fires | did not fire (method-reference binding, not annotated through registration helper) | ⚠️ different reason than expected — see Q1 in retrospective |

Run B's 13 is the **lowest strict-mode fire count of any production
adopter to date** (Penny ~30, isowords 162, SPI-Server 39, prospero
62). This is a function of corpus size (17 files) and the linter's
maturity at this tip — most stdlib/type-ctor noise is now
recognized by the inferrer.

## Cross-round tally

| Adopter | Real-bug shapes | Maps to macro surface | New slices |
|---|---|---|---|
| penny-bot | 4 (coin double-grant, OAuth dup, sponsor DM dup, GHHooks dup) | 4/4 → `IdempotencyKey` / `@ExternallyIdempotent` | slot 12 (linter crash) |
| isowords | 2 (insertSharedGame, startDailyChallenge) | 2/2 → `@ExternallyIdempotent(by:)` | slot 13 (prefix lexicon) |
| spi-server | 0 | n/a | 0 (1st plateau) |
| prospero | 1 (ActivityPattern.save) | 1/1 → `@ExternallyIdempotent(by:)` | slot 16 (Hummingbird Router DSL, evidence-only) |
| **myfavquotes-api** | **1** (login token gen) | **1/1 → `IdempotencyKey` / `@ExternallyIdempotent(by:)`** | **0 (3rd plateau — Criterion #2 closes)** |

**Cross-adopter macro-surface coverage: 8/8 real-bug shapes
resolvable via `IdempotencyKey` / `@ExternallyIdempotent(by:)`.**
Five production adopters; **Completion Criterion #2 at 3/3 — SHIP**.

**Cluster status across all rounds (post-myfavquotes):**

- **slot 14 (HttpPipeline whitelist)**: still 2-adopter (isowords + pointfreeco www); ship-eligible standalone, not promoted by this round.
- **slot 16 (Hummingbird Router DSL whitelist)**: still 1-adopter (prospero); not promoted. myfavquotes-api would push to 2-adopter only if a future round annotates `addRoutes(to:)` registration helpers.
- **AppMetrics.push / Prometheus shape** (1-adopter, SPI-Server): unchanged.
- **Bcrypt-crypto-gap** (new this round): 1-adopter (myfavquotes-api), 1 fire. Logged for evidence accumulation; would only matter if a future Hummingbird/Vapor adopter with auth flows fires the same shape.

## Q1–Q4 quick answers (full discussion in retrospective)

**Q1 — Does `RouterGroup.get/post` fire the same slot 16 shape as
prospero's `Router.get/post`?** **Untested this round** — handler-
method annotations don't reach the `addRoutes` registration body.
Slot 16 stays 1-adopter.

**Q2 — Does method-reference handler binding (`use: self.create`)
walk into the function body?** **Yes, perfectly.** All 5 catches
fired on the handler bodies via the doc-comment on the `@Sendable
func` decl. Method-reference binding is *not* an adoption gap —
the doc-comment attaches to the named decl, and the inferrer walks
the method body normally.

**Q3 — Real-bug catch?** **Yes — 1.** `UsersController.login`
persists a random-token-keyed entry per call; on retry, you get N
stale tokens. Maps to `IdempotencyKey`. The two `create` handlers
were correctly flagged but are defensible-by-design once SQL
ground-truth shows the unique constraints.

**Q4 — Plateau round?** **YES — third consecutive zero-new-slice
round.** Completion Criterion #2 (adoption-gap stability) closes
at 3/3.

## Links

- Trial scope: [`trial-scope.md`](trial-scope.md)
- Replayable transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- Strict-replayable transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- Fork: https://github.com/Joseph-Cursio/myfavquotes-api-idempotency-trial
- Linter tip: SwiftProjectLint `2fbb171`
- Run A tip: `8ae0c78`
- Run B tip: `579c1a4`
