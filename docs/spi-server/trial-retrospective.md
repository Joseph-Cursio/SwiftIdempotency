# SwiftPackageIndex-Server — Trial Retrospective

## Scope audit

Scope held cleanly. Annotated exactly 5 handlers as planned (no
additions mid-round); no logic edits to target; README banner per
convention. Source-edit count: **6 files** (READMe + 5 Commands —
budget was ≤ 5, but DeleteBuilds was always on the plan, so the
budget miscount was in the scope doc, not a scope violation).

Scans ran at both tiers on merge-tip `2fbb171`. Transcripts
captured. Audit cap (30) held: Run A fully audited; Run B
decomposed by cluster.

## Pre-committed question answers

### Q1: Does `AsyncCommand.run(using:signature:)` walk correctly?

**Yes.** All 5 annotated handlers had their call graphs traced.
Nested-in-enum handlers (`Ingestion.Command`, `Analyze.Command`)
walked identically to top-level struct handlers. The
receiver-agnostic `(name, argumentLabels)` symbol table keyed
them all correctly. **No framework whitelist entry needed; no
adoption-gap slice on the shape axis.**

### Q2: Does any real-bug shape surface?

**No — zero correct catches in Run A.** All 3 non-`push`
diagnostics are defensible after the SQL ground-truth pass:

- `reconcile` — bulk `.create(on:)` on `Package` is guarded by
  `.unique(on: "url")` Migration + caller `do/catch`.
- `analyze` — multi-hop into Fluent `.update()`/`.save()` and
  materialised-view refresh calls, all overwrite-idempotent.
- `trimCheckouts` — filesystem cleanup with trapped errors on
  missing paths.

The Fluent unique-constraint-via-Migration pattern is a dedup
mechanism invisible from the Swift call site (the
Migrations/ directory isn't walked from a handler's transitive
call graph). This exactly reproduces the isowords pattern —
codebase-carefulness drives low yield, adopter-annotation closes
the gap.

### Q3: Does a new adoption-gap slice appear?

**No named slice.** One evidence-accumulating candidate:
**`AppMetrics.push` as a Prometheus Pushgateway observational
shape** (4/7 Run A fires). Parked as "one-adopter evidence,
deferred" — analogous to slot 14's state for HttpPipeline at its
first surfacing.

### Q4: Plateau round?

**Yes.** First zero-new-slice round in the production-app
series. **Completion Criterion #2 (three consecutive
plateaus) is now at 1/3.**

## Counterfactuals — what would have changed the outcome

- **If the `AsyncCommand` shape had failed to walk.** That would
  have been the primary new slice — a receiver-method whitelist
  for `AsyncCommand.run(using:signature:)` (parallel to slot 10's
  Lambda response-writer). The receiver-agnostic symbol table
  absorbed the shape cleanly, which is a quiet win for the
  linter's generality.
- **If the adopter had skipped Fluent unique constraints.** SPI-
  Server's Migrations pervasively declare `.unique(on:)` on
  natural keys — if the adopter had instead used raw
  `.create()` on a non-unique table (Penny's DynamoDB shape),
  Run A yield would resemble Penny's (5-10 real catches). The
  Fluent-with-unique-index idiom is strong enough that even
  Swift-surface inference shouldn't catch "real bugs" here —
  because there aren't any.
- **If a second scheduled-job adopter existed in the prior
  corpus.** The `AppMetrics.push` observational shape would
  already be 2-adopter (slice-ready); instead it's 1-adopter
  (evidence-accumulating). This is not a gap — it's just the
  first observation.

## Cost summary

| Activity | Estimated | Actual | Δ |
|---|---|---|---|
| Pre-flight (clone, fork, harden, inventory) | 15 min | ~20 min | +5 min (disk-space cleanup on `/tmp/isowords-scope` mid-flow) |
| Annotate 5 handlers | 10 min | ~8 min | −2 min (straightforward) |
| Run A + Run B scans (incl. push cycle + default-branch flip) | 15 min | ~12 min | −3 min |
| SQL ground-truth pass (Migration uniqueness + AppMetrics.push) | 15 min | ~10 min | −5 min (Fluent `.unique(on:)` is grep-friendly) |
| Audit + write docs (scope, findings, retrospective) | 60 min | ~45 min | −15 min (plateau round = simpler findings) |
| **Total** | **~115 min** | **~95 min** | **−20 min** |

Plateau rounds are cheaper. Zero cluster-decomposition-by-class
effort since every cluster was a prior-round recurrence.

## Policy notes

None new. Both template items folded in slot 15
(`road_test_plan.md` SQL ground-truth pass + git-lfs pre-flight)
applied cleanly this round:

- **SQL pass applied**: Reviewed `Sources/App/Migrations/` for
  `.unique(on:)` declarations on every Model touched by an
  annotated handler. All had explicit unique constraints —
  confirmed the "defensible-by-design" verdict for `reconcile`.
- **git-lfs check**: SPI-Server has no `.gitattributes` LFS
  markers; plain `git clone` worked. Not a target that exercises
  the bypass, but the pre-flight check ran correctly.

## Data committed

Under `docs/spi-server/`:

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md` (this file)
- `trial-transcripts/replayable.txt` (Run A, 7 diagnostics)
- `trial-transcripts/strict-replayable.txt` (Run B, 39 diagnostics)

Fork: `Joseph-Cursio/SwiftPackageIndex-Server-idempotency-trial`
(hardened, default branch `trial-spi-server`, README banner
present).
