# luka-vapor — Trial Findings

Measurement for slot-17 first-adopter evidence. See
[`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions.

## Run A — replayable context

Linter: `SwiftProjectLint` @ `29e9069` · Target: fork tip
`d2c9e21` (annotation = `/// @lint.context replayable`). Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**Total: 4 diagnostics, all in `Sources/LukaVapor/routes.swift`.**

| # | Line | Callee | Rule | Verdict | Notes |
|---|---|---|---|---|---|
| 1 | 10 | `post` | `nonIdempotentInRetryContext` | **slot-17 candidate** | `app.post("end-live-activity")` registration site. Bare-name `post` heuristic match. |
| 2 | 25 | `sendEndEvent` | `nonIdempotentInRetryContext` | **correct catch** | `LiveActivityScheduler.sendEndEvent` (APNS push). Body-based inference. Retry = duplicate end-push notification to device. |
| 3 | 54 | `post` | `nonIdempotentInRetryContext` | **slot-17 candidate** | `app.post("start-live-activity")` registration site. Bare-name `post` heuristic match. |
| 4 | 75 | `append` | `nonIdempotentInRetryContext` | **defensible** | `session.tokens.append(tokenEntry)` — in-memory Array.append on a struct that's about to be re-serialized via `hset`. Idempotent in effect when the hget→mutate→hset CAS round-trip is viewed as a whole; worth an adopter-level `/// @lint.effect observational` on `append` or restructure to avoid the flag. |

**Yield.** 4 catches / 3 annotated handlers = **1.33 aggregate**;
4 catches / 2 non-silent handlers = **2.0 excluding silent
(`app.get` line 5, trivial pure-read literal)**.

**Slot-17 evidence.** 2 `(app, post)` fires. `app.get` at line 5
does **not** fire — the prefix lexicon already classifies `get` as
idempotent-by-convention (HTTP GET semantics), so the registration
site for a GET route is silent even under replayable context. This
is a scope asymmetry versus slot 16 (Hummingbird), where
`router.get` *did* fire because Hummingbird's `router` isn't
receiver-recognized and the prefix-match path was bypassed for
`router.`-prefixed calls.

**Conclusion for pre-committed Q2 — replayable-tier view:** `app.get`
is silent under replayable. But see [Run B correction](#run-b-correction-5-verb-scope)
below — the HelloVapor round showed strict-mode fires on `app.get`,
so slot 17 should ship at **5 entries** (matching slot 16), not 4.

### Run B correction (5-verb scope)

Initial Run B analysis below identified 9 `get` callees; 8 are
`EventLoopFuture.get()` and **1 is `app.get` at line 6** (attributed
to body-first-line of the closure opening at line 5). Under
strict_replayable, `app.get` registration sites fire exactly like
`app.post`. The HelloVapor corroboration round (5× `app.get` strict
fires on a richer corpus) confirms this. **Slot 17 ships as 5
entries, not 4.** See [`../hellovapor/trial-findings.md`](../hellovapor/trial-findings.md)
§"Slot-17 2-adopter evidence summary" for combined data.

## Run B — strict_replayable context

Linter: `SwiftProjectLint` @ `29e9069` · Target: fork tip
`f2e5d09` (annotation flipped to `/// @lint.context strict_replayable`).
Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Total: 52 diagnostics** (4 `[Non-Idempotent In Retry Context]`
carried from Run A + 48 `[Unannotated In Strict Replayable Context]`
strict-only). Over the 30-line audit cap — decomposed by cluster
per road-test-plan policy.

### Carried from Run A (4)

Same 4 lines/callees as Run A. No reshuffle between rules.

### Strict-only clusters (48)

| Cluster | Fires | Callees | Verdict | Notes |
|---|---|---|---|---|
| NIO `EventLoopFuture.get()` | 9 | `get` (all) | **1-adopter slice candidate** | Chained on every Redis future: `redis.hget(...).get()`, `redis.hset(...).get()`, `redis.zadd(...).get()`, `redis.zrem(...).get()`, `redis.delete(...).get()`. Semantic-only "await the future" — observational under the replay model. Expected to recur on every pre-async-await Vapor/NIO codebase. |
| Stdlib / Foundation codec | 14 | `String`×4, `decode`×4, `encode`×3, `JSONEncoder`×3, `JSONDecoder`×2, `Data`×2, `prefix`×2 | **stdlib-gap** | Known cross-adopter cluster; `JSONEncoder` / `JSONDecoder` / `String(data:encoding:)` / `Data(...)` are deterministic ctor calls. No stdlib-whitelist slice exists yet; tracked as phase-3 work, not this round. |
| Redis primitives | 7 | `hset`×3, `hget`×2, `zrem`, `zadd`, `delete` | **1-adopter slice candidate** | Redis-verb receiver-method pairs: all 7 are `req.redis.<verb>(...)` on `RedisClient`. Writes (`hset`, `zadd`, `zrem`, `delete`) are genuinely non-idempotent without a key — real-bug-adjacent but in service of the CAS loop, so adopter-level concern. `hget` is observationally pure-read. A framework-whitelist entry for `(RedisClient, hget)` alone might make sense; writes stay flagged by design. Single-adopter evidence; defer. |
| Vapor / project ctors | 5 | `Abort`×3, `LiveActivityTokenEntry`, `LiveActivityPollSession` | **type-ctor-gap** | `Abort` is a Vapor HTTP error constructor; project structs are adopter-owned. Known cross-adopter cluster (same shape as isowords `Database.Error` ctors, SPI-Server `Metric.Label`). PR #20 handles `Type.init(...)` spelling; this is the bare-name spelling path. Phase-3 work. |
| Collection ops | 3 | `removeAll`, `firstIndex`, `first` | **noise** | In-memory collection operations on local variables. `first` and `firstIndex` are pure-reads; `removeAll` is a local-scope mutation. Same class as isowords' `append` flag. |
| Local helpers | 4 | `dataKey`×2, `post`×2 | **mixed** | `LiveActivityPollKeys.dataKey(for:)` ×2 — static pure helper; adopter-annotatable as `@Idempotent`. `post` ×2 are the same Run A slot-17 fires (reported under both rules). |
| Observability | 1 | `emit` | **slice-eligible — observability** | `app.axiom?.emit(...)` — Axiom Logs observability emit. Same Prometheus-Pushgateway-shape as SPI-Server's `AppMetrics.push` (slot-14 era 1-adopter, closed SPI-Server-specific). Second adopter for the observational-emit pattern; now 2-adopter evidence. Still not slice-worthy without a third adopter because each observability library is its own receiver. |
| Handler-body catch | 2 | `sendEndEvent`, `append` | (same as Run A) | Carried. |

### Slot-17 summary

Run B carries the 2 `app.post` slot-17 fires unchanged. Strict mode
adds no additional slot-17-shape fires (because `app.get` still
doesn't fire and the remaining route file has no other
registration sites).

## Comparison to predicted outcome

| Prediction | Actual | Match? |
|---|---|---|
| Run A: 2–3 slot-17 fires | 2 fires (both `app.post`) | ✅ within range |
| Run A: 0–2 handler-body catches | 2 (`sendEndEvent`, `append`) | ✅ upper bound |
| `app.get` symmetry unclear | `app.get` silent — slot-17 scope narrows to 4 verbs | ✅ resolved |
| Run B: 20–40 strict-only | 48 strict-only | ⚠️ exceeded by 8 |
| No new slice-eligible clusters | NIO `EventLoopFuture.get()` surfaces as 9-fire cluster | ⚠️ 1-adopter candidate not predicted |

Under-prediction on Run B total is accounted for by the NIO
`.get()` cluster, which wasn't on the scope doc's anticipated list.
The prediction of "20–40 strict-only" assumed a post-async-await
codebase; luka-vapor uses the older `EventLoopFuture.get()` pattern
throughout its Redis access layer.

## Real-bug catches

1. **`LiveActivityScheduler.sendEndEvent` — line 25** (POST
   `/end-live-activity` handler). Sends an APNS end-event push.
   Retry = duplicate notification visible to the device user.
   Real-bug shape: **external notification delivery without
   idempotency key**. Maps to
   `@ExternallyIdempotent(by: "pushToken + endTimestamp")` or a
   deduplication table keyed by the end-request nonce. **9th
   cross-adopter real-bug shape; maps to the macro surface.**

2. **`start-live-activity` handler CAS race** (lines 67–86,
   structural not individually flagged). The `hget → decode →
   mutate → encode → hset` pattern on a shared Redis hash key is
   racy under concurrent retries: two clients both read the same
   session base, both mutate locally, both write — last-write-wins.
   Flag for adopter consideration — not a slot-17 case, not
   individually caught by the linter (the linter flags
   `hset`/`hget`/`zadd` individually, not the CAS shape), but
   surfaced by the audit. **Real-bug shape: shared-state CAS
   without versioning**, maps to an adopter-level `WATCH/MULTI/EXEC`
   transaction or an `IdempotencyKey` per request.

## Cross-adopter tally update

Real-bug shapes now **9-for-9 across six adopters** (Penny 4 +
isowords 2 + prospero 1 + myfavquotes-api 1 + **luka-vapor 1**
(+ 1 structural note)) — every confirmed catch maps to
`IdempotencyKey` / `@ExternallyIdempotent(by:)` / `@Observational`
macro surface.

## Answers to pre-committed questions

1. **Slot-17 fire shape.** `app.post` fires via bare-name `post`
   lexicon match (the inference reason string explicitly says
   "from the callee name `post`"). Receiver `app` is unresolved,
   so the path is name-heuristic, not receiver-qualified. Slot-17
   whitelist entry should follow slot-16's `idempotentReceiverMethodsByFramework`
   pattern. The receiver-literal `app` matches usage convention in
   the Vapor community.
2. **`app.get` symmetry.** `app.get` is silent under replayable
   (prefix-lexicon classifies `get` as idempotent) but fires under
   strict_replayable (1 fire on this corpus at line 6; 5 fires on
   the HelloVapor corpus). Slot-17 scope is **5 verbs**
   (`get|post|put|patch|delete`), matching slot 16. Whitelist
   entry silences under both tiers.
3. **Handler-body real-bug catches.** Yes — `sendEndEvent` maps
   cleanly to `@ExternallyIdempotent(by:)`. 9-for-9
   cross-adopter shape coverage.
4. **NIO `EventLoopFuture.get()` cluster.** Yes — 9 strict-only
   fires. Logged as 1-adopter candidate. Will likely recur on
   every pre-async-await Vapor/NIO codebase; promote to slice
   when a second adopter fires it.

## Next-step read

Slot 17 has clean first-adopter evidence on **2 `app.post` fires**
(replayable) + **1 `app.get` fire** (strict). 2-adopter corroboration
landed in the same session on
[`sinduke/HelloVapor`](../hellovapor/trial-findings.md): 1× `app.post`
replayable + 5× `app.get` strict. **Slot 17 ships as 5-entry
whitelist** `(app, get|post|put|patch|delete) → Vapor` — same shape
as slot 16, gated on `import Vapor`.
