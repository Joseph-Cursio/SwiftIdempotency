# isowords — Trial Findings

## TL;DR

**The linter's yield on isowords is an order of magnitude lower than
Penny's — and that's the answer to the research question.** 2 real-
bug catches across 5 annotated handlers (vs Penny's 10). The
difference is not linter-quality: the two bug-shape categories the
linter found (`insertSharedGame` + `startDailyChallenge` → duplicate
row inserts without `ON CONFLICT` guards) both map cleanly onto
`IdempotencyKey` / `@ExternallyIdempotent(by:)`, same as Penny's
shapes.

The difference is **target codebase carefulness**. isowords'
PostgreSQL schema uses `ON CONFLICT DO UPDATE` (upsert) and
`WHERE col IS NULL` (guard) patterns pervasively — `submitLeaderboardScore`,
`insertPushToken`, `updateAppleReceipt`, `completeDailyChallenge`
are all already retry-safe at the SQL layer. The three Run A
diagnostics that looked like bugs on the Swift surface (`createPlatformEndpoint`,
`insertPushToken`, `updateAppleReceipt`) are all **defensible by
design** once the SQL is read. Penny inserts freely; isowords
upserts pervasively.

**One new adoption-gap slice surfaced:** the prefix lexicon
(`create|insert|update|delete` → non-idempotent) is narrower than
the verbs production server apps use. `submit*`, `start*`,
`complete*`, `send*` are all invisible to Run A inference. Strict
mode recovers the miss — `startDailyChallenge` did fire in Run B.
See slot 13 below.

## Pinned context

- **Linter:** `SwiftProjectLint` @ `6200514` (same tip as Penny
  round; `swift test` green at 2272/276).
- **Target:** `pointfreeco/isowords` @
  `c727d3a7c49cf0c98f2fa4f24c562f81e30165f7` → forked to
  `Joseph-Cursio/isowords-idempotency-trial` @ `trial-isowords`.
  - **Run A tip:** `a71c993` (5 handlers `@lint.context replayable`).
  - **Run B tip:** `4e3cc83` (same 5 handlers `@lint.context strict_replayable`).
- **Scan corpus:** 285 Swift files under `Sources/`, 388 total
  including `Tests/`, `App/`, `Bootstrap/`. Single top-level
  `Package.swift` (plus separate nested packages for `App/`,
  `Bootstrap/`, `Assets/` — not scanned this round; all server
  handlers live in the root package).

## Run A — replayable context

**5 diagnostics.** Per-handler headline:

| Handler | Fires | Status |
|---|---|---|
| `submitGameMiddleware` | 1 | Only fire is on `verify` (pure) — noise |
| `submitSharedGameMiddleware` | 1 | `insertSharedGame` — real bug (no ON CONFLICT) |
| `registerPushTokenMiddleware` | 2 | Both defensible (SNS create + DB upsert) |
| `verifyReceiptMiddleware` | 1 | `updateAppleReceipt` — defensible (upsert) |
| `startDailyChallengeMiddleware` | 0 | **silent** — `start*` prefix gap; real bug missed |

**Yield: 4/5 handlers fire (0.80).** Compare Penny 5/5 (1.00).

### Per-diagnostic audit (5 ≤ 30, full audit)

Ground truth verified against `Sources/DatabaseLive/DatabaseLive.swift`
SQL — the actual `ON CONFLICT`/`WHERE` clauses determine whether a
retry is observably safe, independent of the Swift-layer method name.

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `SubmitGameMiddleware.swift:105` | `verify` | **noise** | `verify(moves:playedOn:isValidWord:)` is a pure mathematical move-validator (`Sources/SharedModels/Verify.swift`). Inferrer body-walks 3 hops into it and reaches a mutation, misclassifying the whole function. Same shape as Penny's `unicodesPrefix` finding — pure helper mislabeled via body-walk. |
| 2 | `ShareGameMiddleware.swift:39` | `insertSharedGame` | **correct catch / real bug** | DB SQL: `INSERT INTO "sharedGames" ... RETURNING *` — no `ON CONFLICT` clause. Every retry creates a new row with a fresh auto-generated code. User-visible impact is minor (duplicate rows, but client uses only the returned code), but the call is genuinely non-idempotent. **Fix: `IdempotencyKey(rawValue: completedGame.hash)` — `@ExternallyIdempotent(by: "idempotencyKey")` on `submitSharedGameMiddleware`'s request type.** |
| 3 | `PushTokenMiddleware.swift:47` | `createPlatformEndpoint` | **defensible** | AWS SNS `createPlatformEndpoint` is documented as idempotent: the same `(PlatformApplicationArn, Token)` pair returns the same `EndpointArn`. Adopter should annotate `@lint.effect idempotent`. |
| 4 | `PushTokenMiddleware.swift:55` | `insertPushToken` | **defensible** | DB SQL: `INSERT ... ON CONFLICT ("token") DO UPDATE SET build=..., authorizationStatus=..., updatedAt=NOW()`. Upsert on the token column — retry-safe. Adopter should annotate. |
| 5 | `VerifyReceiptMiddleware.swift:58` | `updateAppleReceipt` | **defensible** | DB SQL: `INSERT ... ON CONFLICT ("playerId") DO UPDATE SET receipt=...`. Overwrite-idempotent by upsert. Adopter should annotate. |

### Run A tally

- **Correct catches (real bugs with concrete fix shape):** **1** (position 2)
- **Defensible (retry-safe by SQL design; adopter should annotate):** 3 (3, 4, 5)
- **Noise (pure-function body-walk):** 1 (position 1)
- **Missed real bugs:** **1** — `startDailyChallenge` at line 117 is an INSERT without `ON CONFLICT` against the `dailyChallengePlays` table. Retry creates duplicate play rows. Invisible to Run A because `start*` isn't in the prefix lexicon.

**Precision (catches ÷ fires):** 1/5 = 20% real-bug-shaped
(compare Penny 10/20 = 50%). **Recall, counting ground truth:**
1 caught / 2 actual bugs = 50% (the `insertSharedGame` and
`startDailyChallenge` bugs were both present; the linter caught
one).

## Run B — strict_replayable context

**162 diagnostics.** Exceeds the 30-diagnostic audit cap;
decomposed by cluster below. Rule distribution: 157
`[Unannotated In Strict Replayable Context]` + 5
`[Non-Idempotent In Retry Context]` (the same 5 Run A positions,
restated under strict framing).

### Strict-only real business calls (recovered via strict walk)

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `DailyChallengeMiddleware.swift:117` | `startDailyChallenge` | **correct catch / real bug** | **Recovered in strict mode.** SQL: `INSERT INTO "dailyChallengePlays" ... RETURNING *` — no `ON CONFLICT`. Retry creates duplicate play rows with fresh IDs. Natural unique key exists (`dailyChallengeId`, `playerId`) — only one play per player per challenge is meaningful. **Fix: `ON CONFLICT ("dailyChallengeId", "playerId") DO NOTHING RETURNING *` in SQL, or `@ExternallyIdempotent(by: "playerId")` on the call.** |
| 2 | `SubmitGameMiddleware.swift:112` | `submitLeaderboardScore` | defensible | SQL: `INSERT ... ON CONFLICT ("puzzle", "playerId") DO UPDATE SET language=...`. Upsert — retry-safe. Words-insert loop also upserts on `(leaderboardScoreId, word)`. |
| 3 | `SubmitGameMiddleware.swift:149` | `completeDailyChallenge` | defensible | SQL: `UPDATE "dailyChallengePlays" SET completedAt=NOW() WHERE ... AND "completedAt" IS NULL`. Guard clause makes retry a no-op. |
| 4-8 | fetch* (5 call sites) | `fetchDailyChallengeById`, `fetchSharedGame`, `fetchDailyChallengeResult`, `fetchLeaderboardSummary`, `fetchTodaysDailyChallenges` | adoption-gap | Pure SELECT reads; adopter should annotate `@lint.effect idempotent`. |

### Decomposition of the 162 strict diagnostics

Sum-checked:

| Cluster | Count | Shape | Verdict |
|---|---|---|---|
| **Stdlib higher-order / Prelude monad helpers** | 59 | `map` (26), `flatMap` (14), `pure` (7), `sequence` (2), `first` (2), `Array` (2), `reduce`, `filter`, `compactMap`, `enumerated`, `Dictionary`, `contains` | Same shape as Penny's stdlib/type-ctor cluster. No new slice. |
| **Either case ctors / Prelude helpers** | 49 | `left` (11), `right` (10), `const` (10), `throwE` (4), `.solo` / `.shared` / `.dailyChallenge` / `.turnBased` / `.player` / `.sharedGame` / `.show` (case ctors), `url`, `baseURL`, `catch`, `EitherIO` | Enum-case construction + `swift-overture` helpers. Adoption-gap, no slice. |
| **HttpPipeline primitives** | 10 | `writeStatus` (10) | Cross-round recurrence — prior pointfreeco www round scored this cluster too. Candidate for a `HttpPipeline` framework whitelist (slot 14 below) if evidence accumulates. |
| **Adopter-type constructors** | 28 | `ApiError` (9), `init` (7), `UnverifiedArchiveData` (3), plus 9 response/error type ctors | Adopter-owned. Adopter annotation closes it. |
| **Pure-function body-walk misclass** | 4 | `verify` (4 sites) | Same `verify` function as Run A; strict walks it at more points. Finding repeats — not a new slice. |
| **Real business calls** | 12 | see above table | 2 real-bug catches (positions 2, 1 above), 3 defensible writes, 5 adoption-gap reads, 1 SNS defensible, 1 adopter read-only |

Sum: 59 + 49 + 10 + 28 + 4 + 12 = **162** ✓

### Real-bug shapes — final list

**Two distinct bug shapes, both map cleanly to `SwiftIdempotency`'s
public API:**

1. **`insertSharedGame` duplicate-row shape** — `ShareGameMiddleware`.
   INSERT without ON CONFLICT on the shared-games table. Retried
   `submitSharedGame` creates duplicate rows with fresh codes.
   Fix: `IdempotencyKey(rawValue: completedGame.contentHash)` or
   client-provided key; `@ExternallyIdempotent(by: "idempotencyKey")`
   on the request type; DB layer deduplicates on the key column.

2. **`startDailyChallenge` duplicate-play-row shape** —
   `DailyChallengeMiddleware`. INSERT without ON CONFLICT on
   `dailyChallengePlays`. The natural unique key
   `(dailyChallengeId, playerId)` exists but isn't enforced.
   Retried `startDailyChallengeMiddleware` creates duplicate play
   rows. Fix: either tighten the SQL (`ON CONFLICT
   ("dailyChallengeId", "playerId") DO NOTHING RETURNING *`) or
   `@ExternallyIdempotent(by: "playerId")` with DB-layer dedup.

Both are **distinct from Penny's four shapes** (coin double-grant,
OAuth error-path Discord noise, sponsor welcome DM, GHHooks
error-path notification). Nevertheless, all six bug shapes across
the two production rounds map onto the same two `SwiftIdempotency`
constructs: `IdempotencyKey` + `@ExternallyIdempotent(by:)`. The
**macro surface's six-for-six generalisation** is the strongest
cross-adopter signal the round produced.

## Newly surfaced actionable slice — slot 13 (open)

**Prefix-lexicon gap for server-app verbs.**

**Shape:** `HeuristicEffectInferrer` currently classifies a callee
as non-idempotent when its name starts with `create|insert|update|delete`
(and a few other known write verbs). These are the CRUD-style
verbs — common in DB-code-gen output. But production server apps
use a **wider** vocabulary for non-idempotent operations:

| Prefix | Example callees (in isowords) | Verdict |
|---|---|---|
| `submit*` | `submitLeaderboardScore`, `submitGameMiddleware` (also Penny-style: `submitPayment`) | INSERT or mutate-on-behalf-of-user |
| `start*` | `startDailyChallenge`, `startSession` | Row-create ("start a play/trial/run") |
| `complete*` | `completeDailyChallenge`, `completeOnboarding`, `completeOrder` | State-transition mutate |
| `send*` | `sendMessage` (Penny), `sendWelcomeEmail` | External-dispatch |
| `register*` | `registerPushToken`, `registerDevice` | Client-side registration that writes |
| `dispatch*` / `schedule*` / `enqueue*` | — (not in isowords but cross-adopter-plausible) | Job-queue writes |

**Evidence**:
- isowords Run A missed `startDailyChallenge` (the real bug) because
  `start*` wasn't lexical. Strict mode recovered it, but
  strict-mode noise floor (162 diagnostics for 5 handlers) makes
  `strict_replayable` a high-friction default for adopters. Every
  adopter that defaults to `replayable` will miss `start*` /
  `submit*` / `complete*` real bugs.
- Penny round had `submitLeaderboardScore`-shaped calls nowhere;
  its vocabulary leaned on `create*`/`insert*`/`update*`/`add*` —
  which happens to overlap the current lexicon. So Penny's
  high-yield outcome partly reflects *prefix-lexicon alignment*
  between the codebase and the heuristic, not just codebase bug
  density.

**Fix direction:**
- Add `submit|start|complete|send|register` to the non-idempotent
  prefix list in `HeuristicEffectInferrer`.
- Gate individual additions on per-adopter evidence — `submit*` has
  two-adopter evidence now (isowords + mentioned in Penny's Q3),
  `start*` has one-adopter evidence (isowords), etc.
- Before shipping: check FP rate on `swift-nio` and TCA — neither
  has strong `submit*`/`start*` surface, so regression risk is
  low, but worth a pre-slice scan.
- Linter test addition: fixture tests for `submit*` / `start*` /
  `complete*` / `send*` / `register*` prefix classification.

**Severity: medium.** It's not a blocker — strict mode already
catches these — but adopters don't default to strict, so the gap
is a quiet correctness hole in the lower-friction default tier.

## Newly surfaced deferred slice — slot 14 (evidence accumulating)

**`HttpPipeline` framework whitelist.**

**Shape:** `writeStatus(.ok)` / `writeStatus(.badRequest)` fires 10
times in isowords Run B, identical shape to the pointfreeco www
round's `writeStatus` residual. The primitive is part of
`pointfreeco/swift-web`'s `HttpPipeline` module (public API:
`writeStatus`, `writeHeader`, `writeBody`, `send`). Writing
response headers is observationally replay-safe — the same status
code / headers / body on retry produces the same response.

**Evidence**: 2 adopters (isowords + pointfreeco www), 1
framework, ~20 combined fires. Same infrastructure shape as the
closed slot 10 Lambda response-writer slice and the 040f186
Hummingbird slice.

**Fix direction** (same pattern as slot 10, 040f186): add entries
to `idempotentReceiverMethodsByFramework` gated on `import
HttpPipeline`. Probable entries: `(nil, "writeStatus")`,
`(nil, "writeHeader")`, `(nil, "writeBody")`, `(nil, "send")`.
Receiver may be `Conn<...>` or free-function via `|>` — verify
shape before picking the gate.

**Status: deferred.** Two-adopter evidence is enough to slice, but
the user's validation direction is production-app rounds (CLAUDE.md
corpus caveat); a third HttpPipeline adopter is unlikely to appear
soon. If a user-owned Point-Free-stack app eventually lands, this
slice pays off immediately.

## Pre-committed question answers

**Q1 — Does yield generalise?** **Yes, with important nuance.**
The linter's precision is consistent (real-bug catches are
real-bug-shaped; noise rate is 1/5 ≈ 20%, comparable to Penny's
1/20 = 5% after adjusting for defensible-by-design catches). But
**absolute yield depends on target codebase carefulness**:

|  | Penny | isowords |
|---|---|---|
| Handlers | 5 | 5 |
| Run A fires | 20 | 5 |
| Run A real-bug catches | 10 | 1 |
| Run A defensible | 6 | 3 |
| Run A noise | 1 | 1 |
| Run A adoption-gap | 3 | 0 |
| Real-bug shapes (distinct) | 4 | 2 |
| Missed real bugs (Run A) | 0 known | 1 (`startDailyChallenge`) |
| Codebase ON CONFLICT / guarded SQL | none observed | pervasive |

Penny writes without upserts; isowords upserts pervasively. The
linter's diagnostics correctly trace what the Swift surface
presents; the gap is that **upsert SQL isn't visible from the
Swift call site** — the adopter-annotation path (`@lint.effect
idempotent` on the DatabaseClient closure properties) is the
recommended remediation, not a linter-side fix.

The round **confirms the Penny yield generalises in terms of what
the linter is doing**, but also shows the headline "10 correct-
catches" was codebase-carefulness-specific. The useful generalisation
metric is **"macro-surface coverage across bug shapes"** — both
rounds produced 100% of bug shapes resolvable via
`IdempotencyKey` / `@ExternallyIdempotent(by:)`. That's the real
cross-adopter signal.

**Q2 — HttpPipeline shape interaction.** No difference observed.
The function-typed `public func *Middleware(_ conn: Conn<...>)`
shape is walked identically to Vapor `func handle(_:)` or Lambda
`func handle(_:)`. Receiver-resolution works on closure properties
(post-PR #19). No new slice from this shape specifically.

**Q3 — Do Penny's four bug-shape categories recur?**
- **Double-increment / duplicate-row writes** — YES (`insertSharedGame`,
  `startDailyChallenge` both fit this shape).
- **Error-path notification duplication** — NO. isowords logs
  errors via `Logger` (structured, observational) rather than
  duplicating user-visible notifications on retry. No error-path
  Discord/email/push-dispatch pattern.
- **External-webhook redelivery** — NO. isowords receives no
  webhooks; it's a mobile-app backend, not an integration hub like
  Penny's GitHub webhook router.
- **Single-use-token replay** — PARTIAL. Apple receipts are
  single-use in principle, but the DB-side upsert on
  `(playerId, receipt)` makes replay safe. No OAuth-code-style
  single-use shape surfaced.

**Score: 1.5 / 4 categories recur cleanly.** Penny's
error-path-notification and webhook-redelivery categories are
likely **Discord-bot-shape-specific**, not universal production
patterns. The double-insert shape IS universal (appears in both
rounds).

**Q4 — Adoption-gap slices.** **One new slice: prefix lexicon
gap** (slot 13 above). Residual is otherwise known cross-adopter
noise. No new cluster shapes beyond what Penny + Lambda +
pointfreeco-www already surfaced.

## Comparison to prior rounds

| Metric | Lambda demos (R9) | Penny (prod #1) | isowords (prod #2) |
|---|---|---|---|
| Handlers annotated | 6 | 5 | 5 |
| Run A catches | 0 | 20 | 5 |
| Run A correct-catches | 0 | 10 | 1 |
| Run A real-bug shapes | 0 | 4 | 1 (+1 missed via prefix gap) |
| Run B count | 16 → 11 post-slot-10 | 71 | 162 |
| New adoption-gap slices | slot 10 | slot 12 (crash) | **slot 13 (prefix-lexicon)** |
| Framework whitelist candidate | slot 10 (landed) | 0 | slot 14 (HttpPipeline) |
| IdempotencyKey / @Externally coverage | 0/0 | 4/4 | **2/2** |

**Every real-bug shape surfaced across three rounds maps cleanly
onto the `IdempotencyKey` + `@ExternallyIdempotent(by:)` surface.
Six for six.**

## Links

- **Scope:** [`trial-scope.md`](trial-scope.md)
- **Retrospective:** [`trial-retrospective.md`](trial-retrospective.md)
- **Run A transcript:** [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- **Run B transcript:** [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- **Fork:** [`Joseph-Cursio/isowords-idempotency-trial`](https://github.com/Joseph-Cursio/isowords-idempotency-trial)
- **Trial-branch tips:** `a71c993` (Run A), `4e3cc83` (Run B)
