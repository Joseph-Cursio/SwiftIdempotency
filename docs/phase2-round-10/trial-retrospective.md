# Round 10 Trial Retrospective

One page. First third-corpus validation. Vapor produced a **cleaner strict-mode profile than round 9's Lambda corpus**, exactly as the round-9 retrospective predicted — and surfaced a 5-hop upward inference as a side benefit.

## Did the scope hold?

**Yes.** The scope was measurement only; no rule changes. One annotation in one file. Three runs. Under 30 minutes of model time. No in-trial fixes needed because PR #5 (cross-file suppression) and PR #6 (chained-logger heuristic) had already landed, and both held up cleanly under this corpus.

## Answers to the four pre-committed questions

### (a) Did Vapor produce a lower strict-mode noise floor than Lambda?

**Yes, decisively.** Strict mode on Vapor: 1 diagnostic, identical to replayable (0 incremental). Strict mode on Lambda's MultiSourceAPI: 19 diagnostics. Ratio 19:0 in strict-mode additional diagnostics.

The structural reason is clear now: Vapor's `next.respond(...)` delegation is upward-inferable across 5 hops because the responder chain is in-project Swift code with visible bodies. Lambda's `JSONDecoder`, `ByteBuffer`, `responseWriter.write` are external library symbols the inferrer can't follow. **The rule suite's precision is a function of call-graph inferrability**, not of the corpus's retry-safety posture.

### (b) Did upward inference reach useful conclusions across Vapor's protocol-dispatched middleware chain?

**Yes, across 5 hops — the deepest chain observed in any trial round.** Previous rounds exercised inference chains up to 3 hops in purpose-built fixtures (round 5 `MultiHopUpwardInferenceTests`). Real-world Vapor middleware is deeper, and the fixed-point iteration converged correctly.

This is also the first round where inference propagated across **protocol dispatch** — `AsyncResponder.respond(to:)` has multiple implementations, and the inferrer picked up at least one body-inferable path to a non-idempotent leaf. That's a stronger guarantee than "the inferrer handles nested `func` calls" — it handles protocol conformers that share a method name.

### (c) What's the next corpus?

**An application repository.** Vapor is still a framework. A user's Vapor app — the kind with `AuthController`, `OrderController`, `PaymentController` — would have business-shape handlers that exercise the rule suite at its target use case. The existing `swift-hummingbird-idempotency-demo` in the user's `xcode_projects` folder is a 2-file purpose-built fixture, not a real corpus.

**Finding an adopter-scale application repository is now the rate-limiting step** for further mechanism validation. Three framework-shape corpora (pointfreeco, Lambda, Vapor) are enough evidence to say the rules work as designed; the open question is cost-to-adopt at scale, which only a real application can measure.

### (d) Did the chained-logger heuristic fix from PR #6 hold up?

**Yes.** `request.logger.debug(...)` in Vapor's middleware stayed silent in both Run B and Run C. The fix generalises across third-party logger receivers (Vapor's `request.logger` is a `Logger` from swift-log — same shape as pointfreeco's and Lambda's receiver patterns but accessed through a different property path). Zero regressions, zero adjustments needed.

## What would have changed the outcome

- **Picking a deeper annotation campaign.** One annotation produced one diagnostic. A multi-middleware campaign would measure per-annotation yield at scale and might surface a second FP class. The trial's single-annotation scope was deliberately narrow (fast-to-complete), but a 10-annotation broader campaign is a natural follow-up inside the same corpus.
- **Targeting a closure-based handler.** Round 6 flagged closure handlers as ungrammatical for the current `@lint.context` parser. Vapor's `routes.swift` is >50% closures. Round 10 sidestepped this by picking `TestAsyncMiddleware.respond` (a `func`). A round 10.5 would either extend the grammar (bigger slice) or pivot to a different framework whose adopter-facing surface is more `func`-heavy.

## Cost summary

- **Estimated (implicit):** 1-2 days for a third-corpus validation.
- **Actual:** ~25 minutes of model time. Clone + one annotation + three scans + writeup. The round rode on PRs #5 and #6 being already shipped.
- **Biggest time sink:** picking the target handler. Vapor's `routes.swift` is mostly closure-based (unannotatable under the current grammar); finding `TestAsyncMiddleware.respond` as the viable `func` target took ~5 minutes of reading.

## Policy notes

- **Trial rhythm at this point is measurement-focused, not build-focused.** Rounds 1-6 measured linter precision on existing mechanisms; round 7 measured macros-package integration; round 8 closed the one gap round 7 surfaced; round 9 measured strict mode and surfaced two pre-existing bugs; this round measured third-corpus generalisability. No rule changes, no macros changes. The measurement-only rhythm is the right shape at this maturity.
- **Cross-corpus comparison tables are the headline artefact.** Individual corpus findings are informative; the comparison across corpora is what answers the "does this generalise?" question. Round 10 makes the table three-corpus-wide for `replayable`, two-corpus-wide for `strict_replayable`.
- **Protocol-dispatch inference is an under-celebrated mechanism.** The round-5/R6 multi-hop tests focused on direct-function chains. Vapor exercised protocol-dispatched chains for the first time in a real corpus. Worth naming as a separate capability in the proposal (currently bundled under "upward inference").

## Net output after ten rounds

- **Rounds 1-6:** linter rule precision validated across two corpora (pointfreeco, Lambda), four code styles, 3909 file-scans.
- **Round 7:** macros-package validation — 3/4 green, 1 deferred.
- **Round 8:** deferred mechanism closed via `@IdempotencyTests` extension-role redesign.
- **Round 9:** `strict_replayable` tier + two pre-existing bug fixes (cross-file suppression, `registerAll` guard).
- **PR #6 slice:** chained-logger heuristic extension.
- **Round 10:** third-corpus (Vapor) validation. `strict_replayable` confirmed business-app-adoption-ready.

The rule suite + macros package now have three-corpus evidence and 2136/274 test coverage. The remaining open items from the proposal are feature additions (dedup_guarded, transactional_idempotent, framework whitelist), not blockers.

## Recommended path after round 10

Three directions, roughly ordered:

1. **Find a real adopter application and measure end-to-end cost.** This is now the rate-limiting step for further mechanism validation. Anything from a small Vapor demo app to a production Hummingbird microservice would count. Scope depends on access.
2. **Closure-handler grammar extension.** Round 6 flagged this; round 10 re-surfaced it (Vapor's routes are >50% closures). ~1-2 day slice to teach the parser to read `@lint.context` from closure-literal leading trivia. Unblocks most Vapor/Hummingbird adopter code.
3. **Framework whitelist mechanism** (deferred from earlier). Would turn round 9's Lambda noise floor from 16 to ~8-10 without per-line suppression. Lower priority now that strict_replayable's adoption story on business-app corpora is validated as low-cost.

My pick: **find an adopter, or (2) if no adopter available**. A real application's evidence is qualitatively different from three framework-shape corpora; it's the evidence that turns the project from "correctly-designed rules" into "rules with an adopter-validated cost profile." (2) is the next-best if access is the blocker.

## Data committed

- `docs/phase2-round-10/trial-scope.md` — this trial's contract
- `docs/phase2-round-10/trial-findings.md` — per-run counts and cross-corpus comparison
- `docs/phase2-round-10/trial-retrospective.md` — this document
- `docs/phase2-round-10/trial-transcripts/run-A.txt` — bare scan (0 diagnostics)
- `docs/phase2-round-10/trial-transcripts/run-C.txt` — strict_replayable scan (1 diagnostic)

Vapor clone branch `trial-round-10`, not pushed. No linter changes, no macros-package changes. Round 10 is a pure measurement round.
