# Unidoc — Trial Findings

Eighteenth adopter road-test. **First MongoDB-backed adopter.**
Designed specifically to confirm the slot 23 (switch-dispatch
deep-chain inference) hypothesis as 2-adopter slice-ready. See
[`trial-scope.md`](trial-scope.md) for predictions.

## Run A — replayable

`swift run CLI /tmp/unidoc-scan/Sources/UnidocServer --categories
idempotency --threshold info`, linter `eb35175`, target `500663c`
(trial branch `trial-unidoc` @ `4c6195b2`). Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**5 fires across 4 of 6 annotated handlers.**

### Per-diagnostic table

| # | Location | Callee | Verdict | Notes |
|---|----------|--------|---------|-------|
| A1 | `WebhookOperation.swift:81` | `create` | **FALSE POSITIVE — enum case pattern.** | Fires on `case .create(let event):` — the linter mistakes the enum case label for a `create()` function call. Same shape would fire on any `switch` with a `.create`/`.update`/`.send`/etc. arm. **New 1-adopter slice candidate** (separate from slot 23). |
| A2 | `WebhookOperation.swift:107` | `update` (`db.users.update`) | **defensible by data layer.** | `Unidoc.DB.Users.update(user:)` uses `Mongo.FindAndModify<Mongo.Upserting<…>>` — a by-key upsert. Replay produces same final user state. The Run A fire is correct (linter identifies write); audit flips to defensible. |
| A3 | `WebhookOperation.swift:148` | `updateWebhook` (`db.packages.updateWebhook`) | **defensible by data layer.** | `Unidoc.DB.Packages.updateWebhook(configurationURL:repo:)` is a by-key update. Replay produces same final package state. Same shape as A2. |
| A4 | `WebhookOperation.swift:190` | `insert` (`db.repoFeed.insert`) | **CORRECT CATCH (low-impact real bug)** | `Unidoc.DB.RepoFeed.insert(activity:)` writes to the `RepoFeed` Mongo collection, which is **capped (1 MB / 16 docs)** with no indexes (`static var indexes: [Mongo.CollectionIndex] { [] }`). Replay produces a duplicate activity entry in the feed; impact is bounded by the capped collection (the dupe ages out as new activity arrives) but a feed reader would see the same package-version-discovered twice. |
| A5 | `AuthOperation.swift:57` | `perform` (`UserIndexOperation.perform`) | **CORRECT CATCH (real bug)** | OAuth flow body. Calls `client.exchange(code:)` first (GitHub OAuth code is single-use; second exchange returns 4xx — the handler catches it as `AuthenticationError`), then calls `operation.perform(on: server)` which downstream-creates a user record. **Replay shape:** first exchange succeeds → user record created → returns to caller; second exchange (LB retry) fails with auth-error → `.unauthorized("Authentication failed")` returned to caller, but the user record from the first call is already there. UI reports "Authentication failed" while session was actually granted. Subtle real-bug shape. |

### Per-handler verdict

| Handler | Run A | Verdict |
|---------|-------|---------|
| `WebhookOperation.load(with:)` | fires (A1) | **SLOT 23 SILENT MISS — masked by enum-case-pattern false positive.** Deep-chain through switch into `handle(installation:...)` / `handle(create:...)` does NOT propagate. The `load` fire is incidental — A1 fires on the `case .create(let event):` enum pattern, not on the `handle(...)` call inside the case body. With a switch whose case names didn't match non-idempotent prefixes (as in tinyfaces' `case .checkoutSessionCompleted:`), `load` would be silent. |
| `WebhookOperation.handle(installation:...)` | fires (A2) | **CORRECT CATCH on `db.users.update`** — defensible after Mongo audit. |
| `WebhookOperation.handle(create:...)` | fires (A3, A4) | **TWO catches** — `updateWebhook` (defensible) + `insert` (correct catch on capped-collection dup). |
| `AuthOperation.load(with:)` | fires (A5) | **CORRECT CATCH** on downstream OAuth + user-create chain. |
| `PackageAliasOperation.load(from:db:as:)` | silent | **Correct silence by accident.** `db.packageAliases.upsert(...)` uses Mongo `upsert`, semantically idempotent. The linter doesn't fire because `upsert` isn't on the bare-name non-idempotent list — happens to be the right answer for the wrong reason. |
| `LoginOperation.load(with:)` | silent | **Correctness signal.** Pure render with no DB or external API calls; expected and confirmed. |

### Yield

- **5 catches / 6 handlers = 0.83** including silent.
- **5 catches / 4 non-silent handlers = 1.25** excluding silent.

### Real-bug shape inventory (after data-layer audit)

1. **`RepoFeed.insert(activity:)` duplicate-on-retry** (A4). Mongo
   capped collection with no indexes; replay produces a duplicate
   activity entry that ages out via the cap. Low-impact but a
   real bug. **Filing candidate.**
2. **OAuth code exchange + user-create race** (A5). The OAuth
   code is single-use at GitHub's API level; first exchange
   succeeds, second returns auth error. The handler reports
   `.unauthorized("Authentication failed")` to the caller while
   the user record from the first invocation exists in the DB.
   UI inconsistency: "auth failed" message but session is
   actually granted. **Filing candidate** (subtle, but real).

## Run B — strict_replayable

Trial branch `trial-unidoc` @ `7559a761`. Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**39 fires (Run A's 5 + 34 strict-only).** Above the 30 cap;
decomposed by class.

### Carried from Run A

All 5 Run A `[Non-Idempotent In Retry Context]` fires reproduce
identically.

### Strict-only (34 fires)

| Cluster | Count | Examples | Verdict shape |
|---------|-------|----------|---------------|
| **C1. HTTP response constructors** | ~10 | `.ok(...)`, `.notFound(...)`, `.created(...)`, `.unauthorized(...)`, `.redirect(...)`, `.seeOther(...)` | **Framework whitelist gap.** `HTTP.ServerResponse.*` constructors. Should be globally idempotent (response value-types). Slice candidate: extend `idempotentTypesByFramework` for HTTP response builders. |
| **C2. Enum case patterns falsely identified as calls** | ~6 | `.installation(...)`, `.create(...)`, `.ignore(...)`, `.web(_, ...)`, `.version(...)`, `.auth(...)`, `.github(...)` | **False positive — same shape as A1.** Linter walks `case .Foo(let bar):` patterns as if they were `Foo(bar)` function calls. Cross-cutting bug independent of slot 23. |
| **C3. `init` calls** | 6 | 6× `init` | **Constructor noise.** Type initializers (`Unidoc.User(...)`, `Unidoc.PackageRepo(...)`, etc.) treated as standalone unannotated calls under strict. |
| **C4. Mongo writes (carried from Run A repeated under strict)** | ~5 | `update`, `insert`, `modify`, `delete`, `updateWebhook` | Same as Run A — un-annotated under strict; semantics already audited above. |
| **C5. Adopter helpers called from annotated entries** | ~4 | `handle` (×2), `perform`, `index` (×2) | **Annotation-form gap.** Sibling methods that need explicit `@lint.effect` to satisfy strict mode. Same shape across rounds. |
| **C6. Other primitives** | ~3 | `db.session()`, `page.resource(...)`, `client.exchange(code:)` | Mixed: Mongo session retrieval is read-only; `resource` is a getter; `exchange` is the OAuth single-use call (legitimate non-idempotent). |

**No new adoption-gap slices** in Run B that weren't surfaced in
Run A. The C1 + C2 + C3 clusters are pre-existing FP shapes
(framework whitelist, enum-pattern walking, constructor recognition);
C4 + C5 + C6 are routine strict-mode noise.

## Predicted vs actual

| Prediction (from scope §"Pre-committed questions") | Actual |
|----------------------------------------------------|--------|
| Q1 — Switch-dispatch deep-chain (`load(with:)` silent) | **MIXED.** `load` does fire — but on a separate enum-case-pattern false positive (A1), NOT via deep-chain through to the `handle(...)` calls. The slot 23 silent miss IS confirmed (the correct-cause path is silent); the round just produced an incidental fire from a separate bug. |
| Q2 — Sub-handler direct annotation (`handle(...)` fires when annotated directly) | **YES.** Both `handle(installation:)` (A2) and `handle(create:)` (A3, A4) fire. Confirms the inner methods ARE inferred non-idempotent — the gap is purely upward propagation through the switch. |
| Q3 — Mongo upsert defensibility (`PackageAliasOperation` fires, audit flips to defensible) | **MIXED.** Linter is silent (didn't fire at all because `upsert` isn't on the bare-name list). The semantically-correct answer is "defensible" but the linter reaches it by not noticing the call, not by audit. Tests whether the prefix-match heuristic generalises to Mongo: **mostly yes** — `update`, `insert`, `delete` all fire on Mongo as they do on Postgres/Fluent, just without the framework-gate. |
| Q4 — Pure-render correctness signal (`LoginOperation.load` silent) | **YES.** Confirmed silent. |

## Comparison to prior rounds

- **vs tinyfaces (round 17):** Both rounds confirm slot 23. The
  silent-miss shape is identical (deep chain through switch
  doesn't propagate to the enclosing function). tinyfaces was a
  cleaner test (the switch case names — `.checkoutSessionCompleted`,
  `.invoice`, `.subscription` — didn't accidentally match
  non-idempotent prefixes); unidoc's `case .create(let event):`
  fires the enum-pattern false positive that masks the slot 23
  silence, but the underlying shape is the same.
- **vs matool (round 16):** Different shape — matool was a
  controller layered through usecase → repository, no switch
  dispatch. unidoc's webhook is the layer-skipping shape.
- **First Mongo-backed adopter.** The data-layer audit pattern
  (find migrations, check unique constraints) maps cleanly to
  Mongo's collection indexes (`static var indexes: [Mongo.CollectionIndex]`).
  Capped-collection semantics (`RepoFeed`) are a Mongo-specific
  data-layer audit consideration not present on Postgres/Fluent.

## Linter slice candidates (named, ordered by evidence weight)

### Slot 23 — switch-dispatch deep-chain inference (now 2-adopter)

**Promote from 1-adopter speculative to 2-adopter slice-ready.**

Both tinyfaces (round 17) and unidoc (round 18) exhibit the same
shape: a method-bound dispatcher whose body is `switch
self.event { case .X: handle(...) case .Y: handle(...) }`, where
the `handle(...)` sub-handlers contain non-idempotent calls.
Without the slot, the dispatcher's `@lint.context replayable`
annotation produces zero diagnostic from the deep-chain path —
only incidental hits from other shapes (tinyfaces: zero; unidoc:
enum-case-pattern FP).

**Fix direction:** `EffectSymbolTable.runInferencePass` to walk
`SwitchExprSyntax` case bodies as direct callees of the enclosing
function, not as nested expressions. `.runInferencePass` already
walks `BraceStmt` / `CodeBlockItemSyntax` bodies; adding
`SwitchCase` traversal is the surgical fix.

**Proposed slice scope:** small — visit-method extension on the
existing inference walker. Tests: 2 fixtures from
`tinyfaces/trial-transcripts/replayable.txt` + this round's
transcript can serve as regression goldens.

### Enum-case-pattern false positive (new 1-adopter slice candidate)

`case .create(let event):` fires the linter's name-prefix
heuristic (`create` matches the non-idempotent verb list). The
linter is walking the enum case's `EnumCasePatternSyntax` —
specifically the `.identifier` part — as if it were a function
call.

**Fix direction:** the call-walker should distinguish
`MemberAccessExprSyntax` calls (`Foo.create(...)`) from
`EnumCasePatternSyntax` patterns (`case .create(...)`). The
former is a call; the latter is a binding.

**Trigger condition:** 2-adopter exhibition before slice work.
This round is 1-adopter; tinyfaces' switch case names happened
to not match prefixes. A future webhook-shape round with
`.create` / `.update` / `.delete` enum cases will trigger.

### HTTP `ServerResponse.*` framework whitelist (1-adopter)

10 fires under strict on `HTTP.ServerResponse.{ok, notFound,
created, redirect, seeOther, unauthorized}`. These are pure
response-value constructors. **Slice direction:** add
`HTTP.ServerResponse` to `idempotentTypesByFramework` (or a
parallel mechanism for member-access-style constructors).
Single-adopter; defer.

## Real-bug filing queue

Two filing candidates:

1. **unidoc — `RepoFeed.insert(activity:)` duplicate-on-retry.**
   Capped Mongo collection (1 MB / 16 docs); replay produces a
   duplicate feed entry that ages out via the cap. Low-impact but
   real. Per filing policy in
   [`ideas/pointfreeco-triage-issue.md`](../ideas/pointfreeco-triage-issue.md).
2. **unidoc — OAuth code-exchange / user-create UI inconsistency.**
   Replay → first exchange succeeds + creates user → second
   exchange returns 4xx → handler reports `unauthorized` to the
   caller while the user already exists. Subtle but real.
