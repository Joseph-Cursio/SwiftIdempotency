# Round 12 Trial Scope

Fourth-corpus validation. Hummingbird is the Vapor-family alternative framework — similar HTTP server/middleware shape, different implementation team and code conventions. Round 12 measures whether the yield profile from rounds 10-11 holds on a sibling framework.

## Research question

> "Does `@lint.context replayable` on Hummingbird middleware produce a yield in the same band as Vapor (round 11: 0.33) and pointfreeco (round 5: 0.80) — or does it reveal a corpus-shape difference?"

## Pinned context

- **Linter:** `main` at `df176a1` (post-PR-8 tip with `stop`/`destroy` whitelist).
- **Target:** `/Users/joecursio/xcode_projects/hummingbird` (existing clone, branch `trial-annotation-local`, tip `a2ed0a0`).
- **Annotation targets (5):** concrete middleware `handle(_:context:next:)` implementations that span different observable-effect shapes:
  1. `TracingMiddleware.handle` — distributed tracing spans
  2. `CORSMiddleware.handle` — HTTP header manipulation
  3. `MetricsMiddleware.handle` — metric counters + timers
  4. `LogRequestMiddleware.handle` — logger-heavy body (exercises PR #6)
  5. `FileMiddleware.handle` — file I/O + response construction

All `@lint.context replayable`. No other source edits.

## Scope commitment

- **Measurement only.** No linter changes this round.
- **Fixed annotation set; single scan.** Unlike a "campaign" round, the five targets are pre-committed for per-shape yield comparison.
- **Per-diagnostic audit with defensible/noise/correct-catch verdicts** matching the round-11 shape.

## Pre-committed questions for the retrospective

1. How does Hummingbird's yield compare to Vapor (0.33) and pointfreeco (0.80)?
2. Does the round-6 chained-logger heuristic (PR #6) silence Hummingbird's `context.logger.*` calls as expected?
3. Are there any heuristic-coverage gaps that round 12's surface reveals — similar to round 11's `stop`/`destroy`?
4. Does the closure-handler grammar extension (PR #7) matter for Hummingbird, or does it use `func` declarations exclusively?
