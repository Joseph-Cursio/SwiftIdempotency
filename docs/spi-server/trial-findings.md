# SwiftPackageIndex-Server — Trial Findings

## TL;DR

**First "no new slice" round in the production-app series — the
plateau signal the road_test_plan calls for.** 7 Run A diagnostics
across 5 annotated `AsyncCommand` scheduled-job handlers: **0 real-
bug catches, 3 defensible (all Fluent-unique-index or FS-idempotent
guarded), 4 noise (all `AppMetrics.push` — Prometheus Pushgateway
observational).** The `AsyncCommand.run(using:signature:)` shape
walked cleanly without a framework whitelist — the linter's
receiver-agnostic symbol resolution handles it out of the box.

**Across all three production-adopter rounds** (Penny, isowords,
SPI-Server), the real-bug shape tally stays at **6 distinct
shapes, all mapping to `IdempotencyKey` / `@ExternallyIdempotent(by:)`
— now 6-for-6 across three adopters.** This round adds zero new
shapes because it adds zero real catches; the shape-coverage
generalisation holds.

**Evidence accumulating (deferred)**: `AppMetrics.push` fires in
4 of 5 handlers in Run A. Prometheus Pushgateway is observational
by design (re-pushing a metric is safe). If a future adopter uses
a similar metrics-push shape (Penny's Lambda deployments use
Prometheus in production per its Infrastructure/ directory —
verify if re-scanned), this could become a new framework whitelist
slice. Not named yet; one-adopter evidence.

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (`swift test` green
  at 2286/276).
- **Target:** `SwiftPackageIndex/SwiftPackageIndex-Server` @
  `74cb5fbb3ead515041bb91f1d133a8f46ce1691a` → forked to
  `Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial` @
  `trial-spi-server`.
  - **Run A tip:** `57f11d727` (5 handlers `@lint.context replayable`).
  - **Run B tip:** `c57b424b8` (same 5 handlers `@lint.context strict_replayable`).
- **Scan corpus:** 349 Swift files under `Sources/App/`.

## Run A — replayable context

**7 diagnostics.** Per-handler headline:

| Handler | Fires | Status |
|---|---|---|
| `ReconcileCommand.run` | 2 | `reconcile` (defensible via unique-index), `push` (noise) |
| `Ingestion.Command.run` | 1 | `push` (noise) |
| `TriggerBuildsCommand.run` | 1 | `push` (noise) |
| `Analyze.Command.run` | 3 | `analyze` (defensible), `trimCheckouts` (defensible), `push` (noise) |
| `DeleteBuildsCommand.run` | 0 | **silent** — correct; `Build.delete(on:)` is pure-idempotent SQL DELETE |

**Yield: 4/5 handlers fire (0.80).** Silent handler
(`DeleteBuildsCommand`) is correct-silent, not a missed bug.

### Per-diagnostic audit (7 ≤ 30, full audit)

Ground-truthed against `Sources/App/Migrations/` (for Fluent
unique constraints) + `Sources/App/Core/AppMetrics.swift:162`
(for the `push` shape).

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `Reconcile.swift:35` | `reconcile` | **defensible** | Body-walk reaches `reconcileLists` which does `insert.create(on: db)` on `Package` (bulk insert) + `.delete()` loop. Migration `CreatePackage:29` declares `.unique(on: "url")` — retry on the same new-package set → unique-constraint violation trapped by caller's `do/catch` (`Reconcile.swift:34-38`). Observably safe-by-reject. `.delete()` loop is idempotent. Adopter should annotate `@lint.effect idempotent` or `externally_idempotent(by: "url")`. |
| 2 | `Reconcile.swift:43` | `push` | **noise (observational)** | `AppMetrics.push(client:jobName:)` is a Prometheus Pushgateway HTTP POST (see `Core/AppMetrics.swift:159-162` docstring). Pushing the same metrics twice is observationally safe — consumers dedupe by timestamp / retain latest. |
| 3 | `Analyze.swift:43` | `analyze` | **defensible** | 5-hop body-walk into `Analyze.analyze` which eventually calls `updatePackages`, `updateRepository`, `RecentPackage.refresh`, `Search.refresh`, etc. Fluent `.update()` / `.save()` on PK-identified models is overwrite-idempotent (`refresh` functions are materialised-view rebuilds — idempotent by replacement). Transaction-wrapped at `:188-189`. Adopter annotation closes. |
| 4 | `Analyze.swift:51` | `trimCheckouts` | **defensible** | `Analyze.trimCheckouts()` is filesystem cleanup (`fileManager.removeItem(atPath:)` on paths older than `Constants.gitCheckoutMaxAge`). `removeItem` on already-gone path throws, trapped by caller `do/catch`. Observably safe. |
| 5 | `Analyze.swift:57` | `push` | **noise (observational)** | Same shape as #2. |
| 6 | `TriggerBuilds.swift:98` | `push` | **noise (observational)** | Same shape as #2. |
| 7 | `Ingestion.swift:103` | `push` | **noise (observational)** | Same shape as #2. |

### Run A tally

- **Correct catches (real bugs):** **0**
- **Defensible (retry-safe by design; adopter annotation closes):** **3** (positions 1, 3, 4)
- **Noise (observational):** **4** (all `AppMetrics.push`)
- **Missed real bugs:** **0 known**

**Precision (real-bug catches ÷ fires):** 0/7 = **0%**
(lowest across the production-app series). **Recall:** 0/0
actual bugs = N/A — no ground-truth bugs found during the SQL
pass.

### SQL ground-truth pass applied

Applied per the updated `road_test_plan.md` (slot 15). Findings:

- **`Package` model** (`Migrations/001/CreatePackage.swift:29`):
  `.unique(on: "url")` — retry on same-URL set fails fast at DB
  layer, no silent duplicate.
- **`Repository` model** (`Migrations/001/CreateRepository.swift:29`):
  `.unique(on: "package_id")` — one-to-one with Package.
- **`Build` model** (`Migrations/009/CreateBuild.swift:37`):
  `.unique(on: "version_id", "platform", "swift_version")` —
  build-pair uniqueness enforces dedup.
- **`CustomCollection`** (`Migrations/081/CreateCustomCollection.swift`):
  `.unique(on: "name")`, `.unique(on: "url")`, `.unique(on: "key")`.

Every Model touched by an annotated handler has a unique index on
its natural key. The adopter relies on DB-layer rejection (plus
`do/catch` trapping) rather than in-Swift dedup guards, identical
to isowords' pattern but via Fluent rather than raw SQLKit.

## Run B — strict_replayable context

**39 diagnostics.** Rule distribution: **7
`[Non-Idempotent In Retry Context]`** (the Run A positions,
restated under strict framing) + **32
`[Unannotated In Strict Replayable Context]`**. Under the 30-
diagnostic audit cap; decomposed by cluster.

### Cluster decomposition

| Cluster | Count | Shape | Verdict |
|---|---|---|---|
| **Observational logging/metrics** | 16 | `push` (4), `Logger` init (4), `logger.info` (4), `logger.error` (2), `printUsage` (2) | Cross-adopter recurrence of the observational-names cluster. Adopter annotation via `@lint.effect observational` closes. |
| **swift-dependencies lib calls** | 4 | `prepareDependencies` (4) | Setup/configuration call — observational; should annotate once in the `Dependencies` package (or whitelist if this recurs on more `swift-dependencies`-using adopters). |
| **Enum case ctors / stdlib helpers** | 8 | `some` (3), `init` (2), `limit` (2), `BuildPair` (1) | Type-ctor-gap cluster (same shape as isowords/Lambda residuals). |
| **Static metric-reset** | 3 | `resetMetrics` (3) | Idempotent-by-overwrite — resets counters to 0. Adopter annotation closes. |
| **Real business calls** | 8 | `reconcile`, `analyze`, `trimCheckouts` (1 each — same as Run A), `delete` (3 — DeleteBuildsCommand now visible), `triggerInfo` (1), `packageId` (1) | Defensible per Run A audit + DeleteBuildsCommand visible under strict (SQL DELETE is idempotent, would annotate). |

Sum: 16 + 4 + 8 + 3 + 8 = **39** ✓

**No new cluster shapes.** Every cluster is a recurrence of
something seen in prior rounds.

## Pre-committed question answers

**Q1 — Does the `AsyncCommand.run(using:signature:)` shape walk
correctly?** **Yes.** All 5 annotated handlers had their bodies
walked; the linter's receiver-agnostic symbol resolution
(`EffectSymbolTable` keys on `(name, labels)`) handled the fresh
shape without a framework whitelist entry. Notable: handlers
nested in an outer `enum` (Ingestion, Analyze) worked identically
to top-level struct handlers (Reconcile, TriggerBuilds,
DeleteBuilds). **No adoption-gap slice surfaced on the shape
axis.**

**Q2 — Does any real-bug shape surface?** **No.** Zero correct
catches in Run A. The 3 defensible diagnostics all trace to
Fluent unique-constraint-via-Migration dedup (`Package.url`,
`Build.(version_id, platform, swift_version)`) or pure-idempotent
filesystem operations (`trimCheckouts`). The adopter's Fluent
schema enforces retry safety at the DB layer; the linter can't
see Migrations from the call-graph walk, so flagging is correct
but scoring misses the DB-layer guard. **This confirms the
isowords pattern: codebase carefulness (DB-layer unique indexes
or upserts) drives zero real catches. Shape is consistent across
Fluent + raw-SQLKit adopters.**

**Q3 — Does a new adoption-gap slice appear?** **No named slice.**
The one shape candidate is `AppMetrics.push` — 4/7 Run A fires on
a Prometheus Pushgateway shape. But this is **one-adopter
evidence**, identical methodology-wise to slot 14 at its first
surfacing. Parked as "evidence accumulating, not named". If a
future adopter shows the same shape, promote then.

**Q4 — Plateau round?** **Yes — first zero-new-slice round in
the production-app series.** Completion Criterion #2 counts this
as 1/3 consecutive plateaus.

## Comparison to prior rounds

| Metric | Penny (prod #1) | isowords (prod #2, merge tip) | **SPI-Server (prod #3)** |
|---|---|---|---|
| Handlers annotated | 5 | 5 | **5** |
| Run A fires | 20 | 8 | **7** |
| Run A real-bug catches | 10 | 2 | **0** |
| Run A real-bug shapes | 4 | 2 | **0** |
| Run A defensible | 6 | 5 | **3** |
| Run A noise | 1 | 1 | **4** (all `push`) |
| Run A adoption-gap | 3 | 0 | **0** |
| Run A handler coverage | 5/5 | 5/5 | **4/5** (silent handler correct) |
| Run B count | 71 | 162 | **39** |
| Run B new cluster shapes | 0 | 1 (prefix-lexicon, landed as slot 13) | **0** |
| New adoption-gap slices | slot 12 (crash, landed) | slot 13 (prefix-lexicon, landed) | **0 — plateau** |
| Framework whitelist candidate | 0 | slot 14 (HttpPipeline, deferred) | evidence accumulating: metrics-push |
| IdempotencyKey / @Externally coverage | 4/4 | 2/2 | **0/0** (no real catches to map) |

**Across-round tally:** 6/6 real-bug shapes resolvable via
`IdempotencyKey` / `@ExternallyIdempotent(by:)` (unchanged — no
new shapes added this round). 3 production adopters, **1 plateau
round of 3 required** for Completion Criterion #2.

**Yield interpretation across three production rounds**:

| Absolute yield metric | Distribution |
|---|---|
| Run A fires | 20 / 8 / 7 — declining |
| Run A real-bug catches | 10 / 2 / 0 — declining |
| Run A precision (catches/fires) | 50% / 25% / 0% — declining |
| Codebase carefulness | bare inserts / pervasive upsert-SQL / Fluent unique-constraints | varying |

The **precision decline is a codebase-carefulness signal**, not a
linter regression — more carefully designed server codebases
rely on DB-layer dedup that's invisible from the Swift call
site. The linter's diagnostics correctly trace Swift-surface
shape; the gap is always closed by the SQL / Migration ground-
truth pass + adopter annotation.

**Macro-surface coverage generalisation holds** — every real bug
shape, across three adopters, is resolvable via `IdempotencyKey`
/ `@ExternallyIdempotent(by:)`.

## Links

- **Scope:** [`trial-scope.md`](trial-scope.md)
- **Retrospective:** [`trial-retrospective.md`](trial-retrospective.md)
- **Run A transcript:** [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- **Run B transcript:** [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- **Fork:** [`Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial`](https://github.com/Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial)
- **Trial-branch tips:** `57f11d727` (Run A), `c57b424b8` (Run B)
