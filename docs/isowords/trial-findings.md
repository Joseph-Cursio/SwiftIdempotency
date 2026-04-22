# isowords — Trial Findings

## TL;DR

**Merge-tip remeasurement (2026-04-21).** Slot 13 landed as
SwiftProjectLint PR #21 (merge commit `2fbb171`); the prefix-lexicon
gap that left `startDailyChallenge` silent in Run A is closed. At
merge tip, **5/5 handlers fire in Run A** (matching Penny's
handler-coverage yield), the previously-missed `startDailyChallenge`
bug is caught on the default `replayable` tier, and the numbers
below reflect this remeasurement against tip `2fbb171`.

**The linter's yield on isowords is an order of magnitude lower than
Penny's — and that's the answer to the research question.** 2 real-
bug catches in Run A across 5 annotated handlers (vs Penny's 10).
The two bug-shape categories the linter found (`insertSharedGame` +
`startDailyChallenge` → duplicate row inserts without `ON CONFLICT`
guards) both map cleanly onto `IdempotencyKey` /
`@ExternallyIdempotent(by:)`, same as Penny's shapes.

The difference is **target codebase carefulness**. isowords'
PostgreSQL schema uses `ON CONFLICT DO UPDATE` (upsert) and
`WHERE col IS NULL` (guard) patterns pervasively —
`submitLeaderboardScore`, `insertPushToken`, `updateAppleReceipt`,
`completeDailyChallenge` are all already retry-safe at the SQL
layer. Five of the eight Run A diagnostics are **defensible by
design** once the SQL is read. Penny inserts freely; isowords
upserts pervasively.

**Adoption-gap slice — now shipped.** The prefix lexicon
(`create|insert|update|delete` → non-idempotent) was narrower than
the verbs production server apps use. `submit*`, `start*`,
`complete*`, `register*` were invisible to Run A inference; strict
mode was the only safety net. Slot 13 added these to
`HeuristicEffectInferrer.nonIdempotentNames` — see slot 13 below for
the measured delta.

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (PR #21 merge tip,
  2026-04-21; `swift test` green at 2286/276). Prior measurement
  was taken against tip `6200514` (pre-slot-13).
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

**8 diagnostics.** Per-handler headline:

| Handler | Fires | Status |
|---|---|---|
| `submitGameMiddleware` | 3 | `verify` (noise), `submitLeaderboardScore` (defensible, upsert), `completeDailyChallenge` (defensible, guarded) |
| `submitSharedGameMiddleware` | 1 | `insertSharedGame` — real bug (no ON CONFLICT) |
| `registerPushTokenMiddleware` | 2 | Both defensible (SNS create + DB upsert) |
| `verifyReceiptMiddleware` | 1 | `updateAppleReceipt` — defensible (upsert) |
| `startDailyChallengeMiddleware` | 1 | `startDailyChallenge` — real bug (no ON CONFLICT); recovered at merge tip |

**Yield: 5/5 handlers fire (1.00).** Matches Penny's 5/5.

### Per-diagnostic audit (8 ≤ 30, full audit)

Ground truth verified against `Sources/DatabaseLive/DatabaseLive.swift`
SQL — the actual `ON CONFLICT`/`WHERE` clauses determine whether a
retry is observably safe, independent of the Swift-layer method name.

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `SubmitGameMiddleware.swift:105` | `verify` | **noise** | `verify(moves:playedOn:isValidWord:)` is a pure mathematical move-validator (`Sources/SharedModels/Verify.swift`). Inferrer body-walks 3 hops into it and reaches a mutation, misclassifying the whole function. Same shape as Penny's `unicodesPrefix` finding — pure helper mislabeled via body-walk. |
| 2 | `SubmitGameMiddleware.swift:112` | `submitLeaderboardScore` | **defensible** | DB SQL: `INSERT ... ON CONFLICT ("puzzle", "playerId") DO UPDATE SET language=...`. Upsert — retry-safe. Words-insert loop also upserts on `(leaderboardScoreId, word)`. Newly surfaced at merge tip (slot 13 prefix addition: `submit*`). |
| 3 | `SubmitGameMiddleware.swift:149` | `completeDailyChallenge` | **defensible** | DB SQL: `UPDATE "dailyChallengePlays" SET completedAt=NOW() WHERE ... AND "completedAt" IS NULL`. Guard clause makes retry a no-op. Newly surfaced at merge tip (slot 13 prefix addition: `complete*`). |
| 4 | `ShareGameMiddleware.swift:39` | `insertSharedGame` | **correct catch / real bug** | DB SQL: `INSERT INTO "sharedGames" ... RETURNING *` — no `ON CONFLICT` clause. Every retry creates a new row with a fresh auto-generated code. User-visible impact is minor (duplicate rows, but client uses only the returned code), but the call is genuinely non-idempotent. **Fix: `IdempotencyKey(rawValue: completedGame.hash)` — `@ExternallyIdempotent(by: "idempotencyKey")` on `submitSharedGameMiddleware`'s request type.** |
| 5 | `PushTokenMiddleware.swift:47` | `createPlatformEndpoint` | **defensible** | AWS SNS `createPlatformEndpoint` is documented as idempotent: the same `(PlatformApplicationArn, Token)` pair returns the same `EndpointArn`. Adopter should annotate `@lint.effect idempotent`. |
| 6 | `PushTokenMiddleware.swift:55` | `insertPushToken` | **defensible** | DB SQL: `INSERT ... ON CONFLICT ("token") DO UPDATE SET build=..., authorizationStatus=..., updatedAt=NOW()`. Upsert on the token column — retry-safe. Adopter should annotate. |
| 7 | `VerifyReceiptMiddleware.swift:58` | `updateAppleReceipt` | **defensible** | DB SQL: `INSERT ... ON CONFLICT ("playerId") DO UPDATE SET receipt=...`. Overwrite-idempotent by upsert. Adopter should annotate. |
| 8 | `DailyChallengeMiddleware.swift:117` | `startDailyChallenge` | **correct catch / real bug** | DB SQL: `INSERT INTO "dailyChallengePlays" ... RETURNING *` — no `ON CONFLICT`. Retry creates duplicate play rows with fresh IDs. Natural unique key exists (`dailyChallengeId`, `playerId`) — only one play per player per challenge is meaningful. **Fix: `ON CONFLICT ("dailyChallengeId", "playerId") DO NOTHING RETURNING *` in SQL, or `@ExternallyIdempotent(by: "playerId")` on the call.** Newly surfaced at merge tip (slot 13 prefix addition: `start*`) — closes the Run A miss from the pre-slot-13 measurement. |

### Run A tally

- **Correct catches (real bugs with concrete fix shape):** **2** (positions 4, 8)
- **Defensible (retry-safe by SQL design; adopter should annotate):** **5** (2, 3, 5, 6, 7)
- **Noise (pure-function body-walk):** 1 (position 1)
- **Missed real bugs:** **0** — both known `insertSharedGame` and `startDailyChallenge` bugs are now caught in Run A at merge tip.

**Precision (catches ÷ fires):** 2/8 = 25% real-bug-shaped
(compare Penny 10/20 = 50%). **Recall, counting ground truth:**
2 caught / 2 actual bugs = **100%** at merge tip (the pre-slot-13
measurement was 50%; the slot 13 prefix-lexicon addition recovers
the second bug).

## Run B — strict_replayable context

**162 diagnostics at merge tip** (unchanged from pre-slot-13). Rule
distribution shifts from 157 `[Unannotated]` + 5 `[Non-Idempotent]`
(pre-slot-13) to **154 `[Unannotated]` + 8 `[Non-Idempotent]`** at
merge tip — the three prefix-lexicon additions
(`startDailyChallenge`, `submitLeaderboardScore`,
`completeDailyChallenge`) reclassify from unannotated to
non-idempotent under strict framing, but the total count and
per-cluster decomposition are invariant. Exceeds the 30-diagnostic
audit cap; decomposed by cluster below.

### Real business calls (cross-tier at merge tip)

All entries below fire in both tiers at merge tip. Pre-slot-13, the
three write-shape entries were strict-only; slot 13's prefix-lexicon
expansion pulled them into Run A.

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `DailyChallengeMiddleware.swift:117` | `startDailyChallenge` | **correct catch / real bug** | SQL: `INSERT INTO "dailyChallengePlays" ... RETURNING *` — no `ON CONFLICT`. Retry creates duplicate play rows with fresh IDs. Natural unique key exists (`dailyChallengeId`, `playerId`) — only one play per player per challenge is meaningful. **Fix: `ON CONFLICT ("dailyChallengeId", "playerId") DO NOTHING RETURNING *` in SQL, or `@ExternallyIdempotent(by: "playerId")` on the call.** Run-A-visible at merge tip via slot 13 `start*` prefix addition. |
| 2 | `SubmitGameMiddleware.swift:112` | `submitLeaderboardScore` | defensible | SQL: `INSERT ... ON CONFLICT ("puzzle", "playerId") DO UPDATE SET language=...`. Upsert — retry-safe. Words-insert loop also upserts on `(leaderboardScoreId, word)`. Run-A-visible at merge tip via slot 13 `submit*` prefix addition. |
| 3 | `SubmitGameMiddleware.swift:149` | `completeDailyChallenge` | defensible | SQL: `UPDATE "dailyChallengePlays" SET completedAt=NOW() WHERE ... AND "completedAt" IS NULL`. Guard clause makes retry a no-op. Run-A-visible at merge tip via slot 13 `complete*` prefix addition. |
| 4-8 | fetch* (5 call sites) | `fetchDailyChallengeById`, `fetchSharedGame`, `fetchDailyChallengeResult`, `fetchLeaderboardSummary`, `fetchTodaysDailyChallenges` | adoption-gap | Pure SELECT reads; adopter should annotate `@lint.effect idempotent`. Strict-only. |

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

## Surfaced and landed — slot 13 (merged, PR #21)

**Prefix-lexicon gap for server-app verbs.**

**Landed** as SwiftProjectLint **PR #21 → merge commit `2fbb171`**
(2026-04-21). `submit`, `start`, `complete`, `register` added to
`HeuristicEffectInferrer.nonIdempotentNames` (`send` was already
present). Bare-name + camelCase-gated prefix-match, identical
treatment to the existing `create|insert|update|delete` entries.
Linter test suite: 2272 → 2286 (+14 tests).

**Measured delta on isowords Run A at merge tip** (this remeasurement):

| Metric | Pre-slot-13 (`6200514`) | Merge tip (`2fbb171`) | Δ |
|---|---|---|---|
| Run A diagnostics | 5 | **8** | +3 |
| Handlers firing | 4/5 | **5/5** | +1 |
| Correct catches (real bugs) | 1 | **2** | +1 (`startDailyChallenge` recovered) |
| Defensible | 3 | **5** | +2 (`submitLeaderboardScore`, `completeDailyChallenge`) |
| Noise | 1 | 1 | unchanged |
| Missed real bugs | 1 | **0** | −1 |
| Recall | 50% | **100%** | +50pp |

**Run B delta:** total 162 unchanged; rule distribution shifts from
157/5 (`[Unannotated]`/`[Non-Idempotent]`) to **154/8** as the three
prefix-lexicon additions reclassify. No regression — all 162
diagnostics stable across tips, just under different rule IDs.

**Original slice rationale** (for historical reference) — `start*`
wasn't in the prefix lexicon, so Run A inference missed
`startDailyChallenge` despite the `INSERT` without `ON CONFLICT`
ground truth. Strict mode recovered it, but `strict_replayable`'s
noise floor (162 for 5 handlers) makes strict a high-friction
default. Every adopter defaulting to `replayable` would have missed
`start*` / `submit*` / `complete*` real bugs. Slot 13 closes that
hole.

**Cross-round:** Penny's vocabulary leaned on
`create*`/`insert*`/`update*`/`add*` (overlapping the pre-slot-13
lexicon), which is part of why Penny's Run A yield was so high
relative to isowords'. Post-slot-13, lexicon alignment is no longer
a confound; absolute yield differences trace to codebase
carefulness.

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
At merge tip, the linter's precision is consistent (real-bug
catches are real-bug-shaped; noise rate is 1/8 = 12.5%, comparable
to Penny's 1/20 = 5% after adjusting for defensible-by-design
catches). Handler coverage matches Penny at 5/5. But **absolute
yield (fires and real-bug count) still depends on target codebase
carefulness**:

|  | Penny | isowords (merge tip `2fbb171`) |
|---|---|---|
| Handlers | 5 | 5 |
| Run A fires | 20 | 8 |
| Run A real-bug catches | 10 | 2 |
| Run A defensible | 6 | 5 |
| Run A noise | 1 | 1 |
| Run A adoption-gap | 3 | 0 |
| Run A handler coverage | 5/5 | **5/5** |
| Real-bug shapes (distinct) | 4 | 2 |
| Missed real bugs (Run A) | 0 known | **0** (prior: 1; recovered via slot 13) |
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

**Q4 — Adoption-gap slices.** **One new slice surfaced and landed
in-round: prefix-lexicon gap** (slot 13 above — PR #21, merge
`2fbb171`). Residual is otherwise known cross-adopter noise. No
new cluster shapes beyond what Penny + Lambda + pointfreeco-www
already surfaced.

## Comparison to prior rounds

| Metric | Lambda demos (R9) | Penny (prod #1) | isowords (prod #2, merge tip) |
|---|---|---|---|
| Handlers annotated | 6 | 5 | 5 |
| Run A catches | 0 | 20 | **8** |
| Run A correct-catches | 0 | 10 | **2** |
| Run A real-bug shapes | 0 | 4 | 2 |
| Run A handler coverage | 0/6 | 5/5 | **5/5** |
| Run B count | 16 → 11 post-slot-10 | 71 | 162 |
| New adoption-gap slices | slot 10 (landed) | slot 12 (landed) | **slot 13 (landed)** |
| Framework whitelist candidate | slot 10 (landed) | 0 | slot 14 (HttpPipeline, deferred) |
| IdempotencyKey / @Externally coverage | 0/0 | 4/4 | **2/2** |

**Every real-bug shape surfaced across three rounds maps cleanly
onto the `IdempotencyKey` + `@ExternallyIdempotent(by:)` surface.
Six for six.**

## Comparison to slot 14 tip (`698081e`) — HttpPipeline whitelist

Re-scanned at SwiftProjectLint slot 14 merge commit `698081e`
(adds `writeStatus` and `respond` to `idempotentMethodsByFramework`
gated on `import HttpPipeline`).

| Metric | At `2fbb171` (slot 13 tip) | At `698081e` (slot 14 tip) | Delta |
|---|---|---|---|
| Run B total | 162 | **152** | **−10** |
| `writeStatus` diagnostics | 10 | 0 | −10 |
| `respond` diagnostics | 0 | 0 | 0 |
| Other clusters | 152 | 152 | unchanged |

The −10 delta exactly matches the prior `writeStatus`-cluster
count. No transitive multiplier on the isowords corpus — the
isowords middlewares fire `writeStatus` directly in the annotated
strict_replayable handler bodies, without intervening helpers
whose inference would benefit from the silence. Contrast:
pointfreeco's `stripeHookFailure` / `validateStripeSignature` /
`fetchGift` helpers each had `writeStatus`/`respond` in their
bodies, so slot 14 unblocked an extra 6 transitive silences
there (see `pointfreeco/trial-findings.md`).

Run A unchanged at 8 diagnostics — `writeStatus` and `respond`
fire only in strict mode (replayable mode doesn't require every
callee to be classified).

## Links

- **Scope:** [`trial-scope.md`](trial-scope.md)
- **Retrospective:** [`trial-retrospective.md`](trial-retrospective.md)
- **Run A transcript:** [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- **Run B transcript:** [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- **Fork:** [`Joseph-Cursio/isowords-idempotency-trial`](https://github.com/Joseph-Cursio/isowords-idempotency-trial)
- **Trial-branch tips:** `a71c993` (Run A), `4e3cc83` (Run B)
