# Round 12 Trial Findings

Fourth-corpus validation on `hummingbird-project/hummingbird` (tip `a2ed0a0`). Five concrete middleware `handle` implementations annotated `@lint.context replayable`. Single scan, per-diagnostic audit.

## Diagnostic count per run

| Run | State | Diagnostics |
|---|---|---|
| A | bare `a2ed0a0`, zero annotations | 0 |
| B | 5 middleware `@lint.context replayable` annotations | 4 |

## Per-annotation audit

| # | Middleware | Result | Verdict |
|---|---|---|---|
| 1 | `TracingMiddleware.handle` | **fires** on `response.body.withPostWriteClosure` (L134) | **defensible catch.** 1-hop upward inference — `withPostWriteClosure` is a NIO body-stream mutation method; body analysis reaches a non-idempotent leaf directly |
| 2 | `CORSMiddleware.handle` | silent | **silent-by-correctness.** Body is header additions + delegation. Headers-dictionary assignments don't trigger the heuristic (subscript assignment, not method call). Strict-mode would catch nothing new either — CORS is a legitimate retry-safe operation |
| 3 | `MetricsMiddleware.handle` | **fires twice** — `withPostWriteClosure` (L32), `recordNanoseconds` (L41) | **both defensible.** `recordNanoseconds` is a metric-timer write — upward-inferred non_idempotent because the metric backend's body mutates state. `withPostWriteClosure` same shape as TracingMiddleware's |
| 4 | `LogRequestMiddleware.handle` | silent | **silent-by-correctness.** Body is `context.logger.log(...)` plus response delegation. PR #6 chained-logger heuristic correctly classifies `context.logger.log` as observational. Confirmation that the fix generalises to Hummingbird's logger shape |
| 5 | `FileMiddleware.handle` | **fires** on `constructResponse` (L196) | **defensible catch.** `constructResponse`'s body reaches a non-idempotent leaf via upward inference. The `construct` prefix is close to `create` — could add `construct` to the non-idempotent heuristic as a round-12 follow-on if adopter evidence warrants |

**Totals:** 4 fires (TracingMiddleware ×1, MetricsMiddleware ×2, FileMiddleware ×1) + 2 silent (CORSMiddleware, LogRequestMiddleware). **Yield: 4/5 = 0.80 catches per annotation.**

## Cross-corpus yield comparison

Fourth data point:

| Corpus | Annotations | Catches | Yield | Handler shape |
|---|---|---|---|---|
| pointfreeco Run D post-fix | 5 | 4 | **0.80** | webhook handlers with external side effects |
| Lambda round 6 Run B | 9 | 0 | **0.00** | compute-and-return demo handlers |
| Vapor round 11 | 6 | 2 | **0.33** | demo routes, mixed shapes |
| **Hummingbird round 12** | **5** | **4** | **0.80** | **concrete middleware with internal side effects** |

Hummingbird matches pointfreeco's yield exactly at 0.80. Both are the "mutation-shaped body" band. Vapor's 0.33 reflects the narrower "demo route" surface (half literal-returns, half mutations). Lambda's 0.00 reflects the compute-and-return surface.

**The four-corpus picture is clear now**: yield tracks handler-shape composition, not framework. A Hummingbird adopter app with business-logic handlers would produce a similar 0.80+ yield; a Vapor demo-route file produces a lower yield because its handlers are mostly trivial.

## Character of Hummingbird's catches vs Vapor's

Hummingbird's 4 catches are all **1-hop upward inferences** — the middleware's direct callee (`withPostWriteClosure`, `recordNanoseconds`, `constructResponse`) has a body that directly reaches a non-idempotent leaf. No deep chains.

Vapor's 2 catches from round 11 were both **5-hop chains** — the middleware's direct callee (`respond`, `decode`) itself goes 5 levels deep before reaching a non-idempotent leaf.

**Interpretation:** Hummingbird's middleware surface is "shallower" — the side effects happen in methods the middleware calls directly. Vapor's is "deeper" — side effects are behind protocol dispatch chains. Both are valid adoption shapes; both are caught by the same rule.

This is the first round to expose a meaningful **inference-depth signature** difference between sibling frameworks. Worth recording for any future "characterise the corpus before annotating" advice: adopters using shallow-middleware frameworks see direct 1-hop catches; adopters using deep-protocol frameworks see multi-hop catches with the same rule set.

## Heuristic coverage

PR #6 chained-logger heuristic: **held up on third-party shape**. Hummingbird's `context.logger.log(level:...)` (not `.debug`/`.info`/`.warning`, but the generic `.log` method) silenced correctly. This is a fresh log-method shape not exercised by Vapor (which uses `.debug`/`.info`) or by the original Lambda (which uses `.info`/`.error` on `context.logger`).

Potential round-12 heuristic-gap (follow-on candidate): **`construct` prefix**. `FileMiddleware.constructResponse` triggered via body-inference, not heuristic-name. Adding `construct` as a non-idempotent prefix would give one more path to classify (but the upward inferrer already handles the specific call here, so it's marginal).

No `stop`/`destroy`-shaped gaps in this corpus (those shipped in PR #8; round 12 doesn't re-surface them).

## Closure-handler grammar (PR #7)

**Not needed for Hummingbird's annotation targets.** All 5 middleware `handle` methods are `func` declarations. Hummingbird's public API uses protocol-conforming types with concrete method implementations, not closures-as-handlers. A different idiom from Vapor's `app.get("x") { req in ... }`, closer to Lambda's `StreamingLambdaHandler.handle`.

PR #7 still has value for adopter-scale validation — an app built ON Hummingbird would likely have router closures `router.get("/orders") { req, context in ... }`. That surface still needs the closure grammar. But the framework itself doesn't exercise it.

## Answer to the four sub-questions

### (a) How does yield compare?

**0.80 — tied with pointfreeco, in the "mutation-body" band.** Hummingbird middleware with real per-request work produces high yield. Confirms the business-app-shape hypothesis from round 10: if the handler body does work, the rule finds something to flag.

### (b) Does PR #6 silence `context.logger.*`?

**Yes.** LogRequestMiddleware — explicitly chosen to exercise this — stayed silent. `context.logger.log(...)` classifies observational via the chained-logger heuristic, same as Vapor's `request.logger.debug(...)`.

### (c) Heuristic gaps?

**One minor candidate: `construct` prefix.** `constructResponse` was caught via upward inference; a heuristic-name match would be redundant for this specific call but might help on similar shapes in other corpora. Not strong enough evidence to ship the addition from round 12 alone.

### (d) Does PR #7 matter for Hummingbird?

**No — not for the framework itself.** All annotation targets are `func` declarations. Closure-based router handlers are an adopter-app concern, not a framework concern.

## Data committed

Under `docs/phase2-round-12/`:

- `trial-scope.md` — this trial's contract
- `trial-findings.md` — this document
- `trial-retrospective.md` — next-step thinking
- `trial-transcripts/run-A.txt` — bare Hummingbird (0 diagnostics)
- `trial-transcripts/run-B.txt` — 5-annotation scan (4 diagnostics)

Hummingbird clone: `trial-annotation-local` branch, uncommitted annotations. Round-1 trial artefacts remain stashed (`round-1 trial artefacts, saved for reference`) for future reference. Linter untouched.
