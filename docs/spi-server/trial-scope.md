# SwiftPackageIndex-Server — Trial Scope

## Research question

> **Does the Penny/isowords yield behaviour generalise to a third
> battle-tested production adopter with a substantively different
> shape (scheduled `AsyncCommand` jobs vs. HTTP middleware), and
> does this round surface a new adoption-gap slice or plateau on
> the existing set?**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (post-PR-#21 merge
  tip; `swift test` green at 2286/276).
- **Target:** `SwiftPackageIndex/SwiftPackageIndex-Server` @
  `74cb5fbb3ead515041bb91f1d133a8f46ce1691a` (main, 2026-04-19) →
  forked to
  [`Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial`](https://github.com/Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial)
  @ `trial-spi-server`.
  - **Run A tip:** `57f11d727` (5 handlers `@lint.context replayable`).
  - **Run B tip:** `c57b424b8` (same 5 handlers `@lint.context strict_replayable`).
- **Scan corpus:** 349 Swift files under `Sources/App/` (+ a small
  handful under `Sources/Run`, `Sources/Authentication`,
  `Sources/S3Store`). Single top-level `Package.swift` — no
  multi-Example decomposition.
- **Toolchain:** swift-tools-version 6.0, macOS 15 minimum.

## Annotation plan

Five `AsyncCommand` scheduled-job entrypoints. All are cron-driven
in production (the SPI build pipeline runs `reconcile`, `ingest`,
`analyze`, `trigger-builds` on schedulers, and `delete-builds` is
an ad-hoc command) — a genuine `replayable` context by shape.

| Handler | File | Tier |
|---|---|---|
| `ReconcileCommand.run` | `Commands/Reconcile.swift:26` | replayable (Run A) / strict_replayable (Run B) |
| `Ingestion.Command.run` | `Commands/Ingestion.swift:85` | replayable / strict_replayable |
| `TriggerBuildsCommand.run` | `Commands/TriggerBuilds.swift:58` | replayable / strict_replayable |
| `Analyze.Command.run` | `Commands/Analyze.swift:31` | replayable / strict_replayable |
| `DeleteBuildsCommand.run` | `Commands/DeleteBuilds.swift:31` | replayable / strict_replayable |

Shape diversity: bulk-upsert reconcile, GitHub-API-ingest,
external build-service dispatch, git+manifest-parse analysis,
pure-DELETE cleanup.

**New axes** vs prior production rounds:
- `AsyncCommand.run(using:signature:)` handler shape — never
  walked by the framework whitelist before (Penny/isowords use
  Vapor `Middleware` or AWS Lambda `Handler` shapes).
- Scheduled-job retry context (cron-driven) — prior rounds were
  webhook-driven (Penny) or mobile-HTTP-driven (isowords).
- Fluent 4 + PostgreSQL (first Fluent-heavy prod adopter; isowords
  is Vapor but uses direct SQLKit for DB access).

## Scope commitment

- **Measurement-only**: no logic edits to the target. Only
  annotation comments + README fork banner.
- **Source-edit ceiling**: ≤ 5 files annotated (README + 4
  Commands — Ingestion is nested so a single edit; 5 handler-
  annotation edits total).
- **Audit cap**: 30 diagnostics. Run A (7) fits for full audit;
  Run B (39) exceeds cap and is decomposed by cluster.

## Pre-committed questions

1. **Does the `AsyncCommand.run(using:signature:)` shape walk
   correctly?** — The framework whitelist has Vapor
   `handle(_:)` and Lambda `handle(_:)` shapes; this is a fresh
   receiver shape. If the linter fails to resolve the receiver or
   walk the body, that's an adoption-gap slice.
2. **Does any real-bug shape surface?** — The catalog/indexer
   domain is DB-heavy with Fluent ORM. Expect ~0-1 real catches;
   Fluent's unique-constraint-via-Migration pattern provides
   DB-level dedup that's invisible to Swift-surface inference
   (SQL ground-truth pass required).
3. **Does a new adoption-gap slice appear?** — Open axis. Likely
   candidates: metrics-push shape (AppMetrics/Prometheus), Fluent
   `.create()`/`.save()` behaviour, new noise cluster from
   `Commands/` shape.
4. **Does this round plateau** (zero new slices) — the first of
   three consecutive plateaus required by the road_test_plan's
   Completion Criterion #2?

## Predicted outcome

Yield shape matches isowords (pervasive DB upserts/unique
indexes → low real-catch rate, diagnostics largely defensible
after SQL ground-truth pass). Run A 5-10 fires, Run B 30-60
dominated by known cross-adopter clusters (stdlib helpers,
Logger/observational, type ctors). New clusters plausible but
not expected beyond low single-digit.
