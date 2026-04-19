# Round 12 Trial Retrospective

One page. Fourth-corpus validation on Hummingbird. Produced the cleanest yield comparison data the project has — four corpora spanning three distinct handler-shape bands with predictable yields.

## Did the scope hold?

**Yes, tightly.** Five pre-committed annotations. One baseline scan, one post-annotation scan. Per-diagnostic audit. No linter changes, no in-trial fixes needed. Scope matched the round-11 shape exactly, which is the rhythm measurement-rounds have converged on.

## Answers to the four pre-committed questions

### (a) How does Hummingbird's yield compare?

**0.80 — ties with pointfreeco at the top of the observed range.** Four-corpus picture:

- **Mutation-body band (0.80):** pointfreeco webhooks + Hummingbird middleware. Handlers do real per-request work; the rule finds something to flag per annotation.
- **Mixed-demo band (0.33):** Vapor routes. Half trivial (literal returns), half mutations. Yield = ratio of working-handlers to total.
- **Compute-and-return band (0.00):** Lambda demo handlers. No side effects; nothing to flag.

The bands are predictable from handler shape alone. This is the cleanest four-corpus evidence the project has produced.

### (b) Did PR #6 silence `context.logger.*`?

**Yes, on a fresh third-party shape.** Hummingbird uses `context.logger.log(level:...)` (generic `.log` method) rather than `.debug`/`.info`/`.warning`. The chained-logger heuristic extracts `logger` as the immediate-parent segment and classifies observational. Worked first try; no adjustments.

### (c) Heuristic gaps?

**One weak candidate (`construct` prefix).** Not strong enough to ship from round 12's evidence alone — the specific call already fires via upward inference, so a heuristic-name match would be redundant locally. Hold off pending corroboration from another corpus.

**Zero `stop`/`destroy`-shaped gaps in this corpus** — PR #8's whitelist additions don't need to re-surface here because Hummingbird's shutdown/lifecycle surface isn't in the annotated middleware.

### (d) Closure-handler grammar?

**Not needed for Hummingbird itself** — all 5 middleware are `func` declarations. PR #7 still matters for adopter apps (router closures `router.get("/orders") { ... }`) but not for the framework's own code.

## Inference-depth signature across corpora — new observation

A pattern round 12 exposed that round 11 didn't:

- **Hummingbird catches:** all **1-hop** upward inferences. The middleware's immediate callee has a body reaching a non-idempotent leaf.
- **Vapor catches:** all **5-hop** upward inferences. Protocol dispatch chains that go through 5 levels of responders before reaching a leaf.
- **Why the difference:** Hummingbird's middleware calls concrete methods on types it owns (`response.body.withPostWriteClosure`). Vapor's middleware calls protocol-dispatched methods (`AsyncResponder.respond(to:)`) that have many implementations; the inferrer walks through several before hitting a body with a clear non-idempotent signal.

This is the first round to surface an **inference-depth signature** as a corpus-shape variable. Framework design choices (concrete types vs. protocol dispatch) map to different inference profiles. Both are correctly handled by the existing multi-hop machinery.

## What would have changed the outcome

- **Annotating router closures, not just middleware.** Hummingbird has a `HummingbirdRouter` module with router-closure handlers (`router.get("/orders") { req, ctx in ... }`). Round 12 sampled the middleware layer; a router-layer campaign would exercise PR #7 on this corpus and compare yield to the middleware layer.
- **Annotating a Hummingbird-adopter application.** Same note as round-11's retro — framework measurement is informative but adopter-app evidence is qualitatively different. Hummingbird has no bundled demo-app equivalent to Vapor's `Development/routes.swift`; a follow-up could use the `swift-hummingbird-idempotency-demo` locally, though that's a purpose-built fixture not a real app.

## Cost summary

- **Estimated:** 0.5 day (same as round 11).
- **Actual:** ~20 minutes of model time.
- **Biggest time sink:** picking middleware targets. Five candidates became obvious after skimming the Middleware directory.

## Policy notes

- **Round 12 makes per-annotation yield a four-data-point metric.** Enough data now to name the handler-shape bands explicitly; see the findings doc's comparison table.
- **Hummingbird's shallow-inference profile vs. Vapor's deep-inference profile** is worth documenting as a corpus characterisation concept. Adopters picking a framework might notice: shallower dispatch chains mean quicker diagnostic attribution for the linter.
- **Adopter-app evidence remains the qualitative next step.** Four framework corpora now. A real app produces something none of these have: evidence that the rules hold up under genuinely varied real-world call graphs, not curated demo code or internal framework implementations.

## Net output after twelve rounds

- **Rounds 1-6:** linter precision, two corpora.
- **Round 7:** macros integration, 3/4 green.
- **Round 8:** 4th mechanism closed.
- **Round 9:** strict_replayable + 2 bug fixes.
- **PR #6:** chained-logger heuristic.
- **Round 10:** Vapor first-look, 1 annotation.
- **PR #7:** closure-handler grammar.
- **Round 11:** Vapor measured at 6 annotations.
- **PR #8:** `stop`/`destroy` whitelist.
- **Round 12:** Hummingbird fourth-corpus validation.

**Twelve rounds. Four corpora. Three handler-shape bands with predictable yields. 2153/274 linter tests green.** The rule suite has moved from "designed correctly" (rounds 1-6) through "mechanism-integrated" (rounds 7-8) to "strict mode shippable" (round 9) to "cross-corpus generalisable" (rounds 10-12). Each round adds ~20 minutes of evidence and either closes a gap or confirms a hypothesis.

## Recommended path after round 12

Three directions, ordered:

1. **Framework whitelist mechanism** (1-2 days). Still the biggest outstanding slice. Would reduce round-9 Lambda noise from 16 → ~8-10 on library-mediated handlers. Now has strong context: round 12 shows Hummingbird's 1-hop catches don't need a whitelist (the internal surface is already annotatable), but Lambda's external-library callees do. The whitelist is the "library boundary" solution the adoption story needs for the edge corpus.

2. **Router-closure campaign on Hummingbird** (half-day). Exercise PR #7 on Hummingbird's `HummingbirdRouter` module. Would produce router-closure-yield evidence to pair with the middleware-yield this round produced.

3. **Find an adopter application** — still the qualitatively next step.

My pick: **(1) framework whitelist**. Three rounds deferred it; round 12's cross-corpus evidence justifies it now as the adoption-enabling slice, not just a nice-to-have.

If (1) isn't in the budget, (2) is a ~20-minute extension of round 12 and would complete the Hummingbird picture.

## Data committed

- `docs/phase2-round-12/trial-scope.md` — this trial's contract
- `docs/phase2-round-12/trial-findings.md` — per-annotation audit and four-corpus yield table
- `docs/phase2-round-12/trial-retrospective.md` — this document
- `docs/phase2-round-12/trial-transcripts/run-A.txt` — bare Hummingbird baseline
- `docs/phase2-round-12/trial-transcripts/run-B.txt` — 5-annotation scan

No linter changes. Hummingbird annotations remain uncommitted on `trial-annotation-local`; can be discarded or stashed for future rounds.
