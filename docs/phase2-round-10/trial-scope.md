# Round 10 Trial Scope

Third-corpus validation. Companion to the round-7 retrospective's direction 3 ("Vapor app or internal microservice once [cross-file suppression] and [logger heuristic] ship"). Both prerequisites shipped in PRs #5 and #6.

## Research question

> "Does the idempotency rule suite — particularly `strict_replayable` — behave differently on a Vapor-shape corpus compared with the library-mediated `swift-aws-lambda-runtime` corpus round 9 measured?"

Round 9's finding was that library-heavy handlers produce a high noise floor under strict mode because every callee is external. The round-7 retrospective predicted a cleaner profile on business-app shapes where most callees are in-project. Round 10 tests that prediction.

Three sub-questions:

1. **Run A** — bare repo, zero annotations. Stay silent (replays the round-6/round-9 result on a fresh corpus).
2. **Run B** — one middleware handler annotated `@lint.context replayable`. Measure per-annotation yield vs. round-6 Lambda's 0.00 and pointfreeco Run D's 0.80-1.80.
3. **Run C** — same handler promoted to `@lint.context strict_replayable`. Measure the count delta vs. Run B. Prediction: 0 additional diagnostics on a well-inferrable corpus, vs. ~10-20 on library-heavy code (round-9 shape).

## Pinned context

- **Linter:** `main` at `a26302b` (post-PR-6 tip with the chained-logger heuristic).
- **Target:** `vapor/vapor` @ tag `4.118.0`. Cloned to `/Users/joecursio/xcode_projects/vapor`.
- **Target handler:** `TestAsyncMiddleware.respond(to:chainingTo:)` in `Sources/Development/routes.swift`. Chosen because: (a) it's a `func` declaration (annotatable under the current grammar — round-6 identified closure-based handlers as unreachable); (b) middleware runs on every HTTP request, making retry a legitimate concern; (c) its body exercises the chained-logger heuristic from PR #6 (`request.logger.debug(...)`) and the new multi-hop upward inference (via `next.respond(...)`).

## Scope commitment

- **Measurement only.** No linter changes this round.
- **Annotation-only source edits.** The only modification to Vapor: one `/// @lint.context <tier>` comment above `TestAsyncMiddleware.respond`. No refactoring, no logic changes.
- **Throwaway branch, not pushed.** `trial-round-10` on the Vapor clone.
- **Per-diagnostic audit cap: 30.** Vapor is large; cap the audit and document the shape of any excess.
- **Cross-corpus comparison is the headline.** The purpose of this round is to answer "is strict_replayable's adoption story business-app-friendly, as predicted?"

## Pre-committed questions for the retrospective

1. Did Vapor produce a lower strict-mode noise floor than Lambda?
2. Did upward inference reach useful conclusions across Vapor's protocol-dispatched middleware chain?
3. What's the next corpus — an actual application repository (somebody's Vapor app), or a broader Vapor annotation campaign?
4. Did the chained-logger heuristic fix from PR #6 hold up on third-party logger-receiver shapes?
