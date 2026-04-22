# hummingbird-examples / open-telemetry — Trial Retrospective

## Pre-committed question verdicts

### Q1 — Slot 16 fire count

**Prediction:** 3 slot 16 fires (`router.get` × 2, `router.post` × 1)
in Run A.
**Actual:** 1 slot 16 fire in Run A (`router.post` only).

**Verdict:** Prediction was wrong on *mode*, not on *shape*. The
`router.get` calls never fire in replayable mode by design —
`get` is a bare-name idempotent HTTP verb and the
`nonIdempotentInRetryContext` rule correctly does not inspect
it. Both `router.get` calls surface in Run B as
`unannotatedInStrictReplayableContext` (strict mode forces all
unannotated callees to raise). This matches prospero's behaviour
exactly: prospero's 3× `router.post` Run A fires + 11× `router.get`
Run B fires are the same two-path pattern, in the same ratio
(all `post`s caught in Run A, all `get`s caught only in Run B).

**Total slot 16 fires across both runs: 3** (1 in Run A + 2 in
Run B). Prospero totalled 14 (3 + 11). Same paths, same rule
shapes, smaller sample. Clean 2-adopter corroboration.

### Q2 — Handler-body catches in Run A

**Prediction:** No handler-body catches (pure reads + traced sleep).
**Actual:** Zero handler-body catches.

**Verdict:** Confirmed. The handler closures contained no
non-idempotent bare-name verbs, no ORM verbs, and no
`@NonIdempotent`-attributed helpers. Correct silence — no rule
should have fired, and none did.

### Q3 — Strict-mode cluster shape

**Prediction:** Strict-only fires cluster cleanly into
existing-whitelist-slice buckets; no new named slice expected.

**Actual:** 11 strict-only fires, decomposing as:
- **2** Slot 16 continuation (`router.get` × 2) — known slice
- **4** `.init(...)` type-constructor gap — known gap (from
  todos-fluent findings)
- **5** across four candidate clusters (`addMiddleware`,
  `context.parameters.require` receiver-chain, `withSpan`,
  `Task.sleep`/`seconds`) — **each new at 1-adopter evidence**

**Verdict:** Partially refuted. The prediction assumed no new
clusters; this corpus surfaced four new below-threshold candidates.
None is ship-eligible (all are 1-adopter), but the prediction
that the corpus would be a "clean signal with no surprises" did
not hold — OTel + Swift Distributed Tracing + Swift Concurrency
stdlib primitives all surfaced cleanly, consistent with the
corpus being the first Observability-focused adopter tried.

This is a positive surprise for the framework: small
observability-shaped corpus surfaced primitives that weren't
visible in DB-or-auth-shaped prior trials (Fluent/Prospero/
myfavquotes-api/SPI-Server/Penny). Each candidate is
recorded in `trial-findings.md` for next-round cross-corroboration.

### Q4 — Distinct adopter for slot 16?

**Prediction:** Ambiguous. Monorepo-adopter argument goes both
ways.

**Actual verdict:** **Distinct adopter for slot 16.** Three
orthogonal reasons:
1. Different binding style (inline trailing closures) vs.
   todos-fluent (which uses `TodoController` method references,
   produced zero slot 16 fires, and whose annotated context was
   `TodoController` methods, not `buildRouter`).
2. Different annotation target (`buildRouter` vs. controller
   methods).
3. Different stack (OTel-instrumented vs. Fluent-backed).

The slot 16 evidence from this round is structurally disjoint
from the slot 16 evidence prospero contributed. Counting it as
a separate adopter is defensible. The conservative reading
(monorepo = one adopter, need a non-hummingbird-examples target
like a Vapor DSL analog) still holds slot 16 at 1-adopter, but
given the test corpus situation (no obvious Vapor adopter in the
trial pool, Vapor uses different router DSL shape anyway),
the monorepo-distinct-adopter reading is the practical one to
proceed with.

**Recommendation:** promote slot 16 to 2-adopter ship-eligible;
note in the slice commit message that corroboration comes from
the same monorepo (hummingbird-examples) via a distinct
subdirectory, stack, and binding style, not from a separate
upstream repo.

## What this round added to the slot 16 picture

1. **`router.post` in Run A** — 1 fire, exact match for prospero's
   3× Run A shape.
2. **`router.get` in Run B** — 2 fires, exact match for prospero's
   11× Run B shape.
3. **Registration site detection** — `buildRouter` as an enclosing-
   function annotation target works identically to prospero's
   `addXRoutes`, confirming the pattern is not `Router`-subtype-
   specific (prospero used `RouterGroup`; this used `Router`).

## New candidate slices surfaced (1-adopter, tracked only)

Four below-threshold clusters from Run B:

| Candidate | Shape | Cross-adopter need |
|---|---|---|
| Hummingbird Router registration primitives (`addMiddleware`) | Module-level registration helper inside `@lint.context`-annotated fn | Second adopter with `addMiddleware` usage pattern |
| `context.parameters.require` receiver-chain | Chained member-access receiver not matched by slot-14 bare-receiver whitelist | Second adopter with `context.parameters.*` chain |
| Swift Distributed Tracing (`withSpan`) | Observational primitive | Second adopter importing `Tracing` |
| Swift Concurrency (`Task.sleep`, `Duration.seconds`) | stdlib async/Foundation primitives | Second adopter with `Task.sleep(for:)` in annotated context |

Each is named for observation only. None is a linter-PR
candidate yet.

## Scope-commitment audit

- **Measurement-only:** ✅ no linter changes this round.
- **Source-edit ceiling (≤2 files):** ✅ 1 file edited — one
  doc-comment line on `buildRouter` (added for Run A, flipped
  for Run B).
- **Audit cap (30 diagnostics):** ✅ well under — 13 total in Run
  B, 2 in Run A.
- **Single sub-package:** ✅ `open-telemetry/` only; no other
  hummingbird-examples subdirs touched.

## Outcome

- **Slot 16 → 2-adopter ship-eligibility.** Linter team may now
  draft the Hummingbird Router DSL whitelist PR against
  SwiftProjectLint.
- **Criterion #2 remains 3/3 closed** (same-slice extension, not
  a new named slice).
- **4 new below-threshold candidates recorded** for next-round
  observation. None blocks anything; all are parked in
  `trial-findings.md`.

## Push outcome

User authorized push. Trial branch `trial-open-telemetry`
pushed to [`Joseph-Cursio/hummingbird-examples-idempotency-trial`](https://github.com/Joseph-Cursio/hummingbird-examples-idempotency-trial)
with three commits off upstream `0d0f9bd`:

| Commit | Message |
|---|---|
| `9b5a662` | validation-sandbox banner on README |
| `9a7edb8` | Run A tip (`buildRouter` @ `@lint.context replayable`) |
| `674935a` | Run B tip (same function flipped to `strict_replayable`) |

The upcoming linter PR that ships the slot 16 Hummingbird Router
DSL whitelist may cite `9a7edb8` (prosp-style `router.post` Run A
evidence, replayable mode) and `674935a` (prosp-style `router.get`
Run B evidence, strict mode) as the second-adopter corroboration
tips.
