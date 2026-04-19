# Round 9 Trial Scope

Validation of the new `strict_replayable` context tier against a handler in `swift-aws-lambda-runtime`. Companion to [`claude_phase_2_strict_replayable_plan.md`](../claude_phase_2_strict_replayable_plan.md) — this doc pins the measurement target.

## Research question

> "Does opt-in `strict_replayable` on a single handler produce actionable diagnostics (every fired diagnostic silenceable by a defensible annotation) and a tractable adoption cost?"

Three sub-questions:

1. **Run A diagnostic count** when one handler's context is promoted from `replayable` to `strict_replayable` without any other edits.
2. **Run B campaign cost** — minutes of annotation effort to bring Run A count to 0, and per-diagnostic verdict (actionable vs. irreducible stdlib/framework surface).
3. **Run C steady-state** — is 0 reachable inside the round's budget, or are there irreducible call-graph edges (stdlib / framework / external SDK) strict mode can't silence without a whitelist mechanism?

## Pinned context

- **Linter:** `phase-2-strict-replayable` branch off `main` at `ac8bbc5` (post-round-8-linter-line-update). 2099 tests / 270 suites green baseline.
- **Target:** `apple/swift-aws-lambda-runtime` @ `2.8.0`. Local clone: `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime`. Trial branch `trial-strict-replayable-round-9` forks from `2.8.0`, not pushed.
- **Candidate handler:** `Examples/MultiSourceAPI/Sources/main.swift` — `MultiSourceHandler.handle(_:responseWriter:context:)`. Rationale: richest distinct call graph across the Lambda examples (JSONDecoder/Encoder, logger calls on two severities, response-writer writes, conditional branches on decode attempts). Round-6 `replayable` annotation on this handler produced 0 diagnostics; Run-A measures what strict mode surfaces beyond that baseline.

## Scope commitment

- **Measurement only on the linter side.** Linter code changes land under the plan's Phase 1-3 *before* round 9 begins; this round makes no linter edits.
- **Annotation-only source edits on the target.** Same policy as rounds 2-6 — the only Lambda-side modification is `@lint.context strict_replayable` on the target handler, and progressive `@lint.effect <tier>` or `@Idempotent` / `@Observational` / `@ExternallyIdempotent` annotations on flagged callees during Run B. No logic edits, no refactoring.
- **No pushed branch on the Lambda clone.** Round 2-8 pattern.
- **Round-9 per-diagnostic audit cap: 30 diagnostics.** If Run A exceeds 30, cap the analysis and document the shape of the excess.
- **If Run A = 0**, pivot to a secondary candidate (BackgroundTasks or MultiTenant) and re-run. Document the pivot reason in `trial-findings.md`.

## Explicit Run plan

- **Run A — bare promotion.** Change `/// @lint.context replayable` → `/// @lint.context strict_replayable` on the MultiSourceHandler's `handle` method. Scan. Record diagnostic count + list per-diagnostic `(file, line, callee, reason-if-any)`.
- **Run B — annotation campaign.** For each Run A diagnostic, add the defensible annotation (`@Idempotent`, `@Observational`, `@ExternallyIdempotent(by:)`, or the doc-comment equivalents) to the flagged callee — or, where the callee is stdlib/framework/SDK surface outside the project's edit surface, document as irreducible. Re-scan after each batch of ~5 annotations; log the diagnostic count decrement.
- **Run C — steady state.** After Run B's annotation effort plateaus, final re-scan. Record the steady-state count. Non-zero is fine — decompose into "irreducible" (stdlib/SDK) and "actionable gap" (something the tool should silence but doesn't).

## Expected outcomes

No strong priors; the honest expectation is "Run A surfaces between 3 and 10 diagnostics, most silenceable with `@Observational` on logger/writer methods, some irreducible because they're framework-owned." The round-6 insight — "Lambda handlers are compute-and-return, so external-side-effect scaffolds don't fire" — predicts strict mode will target the *demo code's internal calls* (decoder, encoder, writer) rather than side-effect callees. That's the uninteresting shape; the interesting shape is whatever pattern strict mode reveals that `replayable` couldn't.

## Acceptance

- Run A produces a non-zero count on the first-choice handler (or a documented pivot).
- Run B's annotation campaign produces per-diagnostic verdicts for every diagnostic under the 30-cap.
- Run C's steady-state is either 0 or fully-decomposed-into-named-classes.
- `trial-findings.md` contains a cross-round comparison table (round 6 `replayable` vs round 9 `strict_replayable` on the same handler).
- `trial-retrospective.md` answers the four plan-specified questions.

## Pre-committed questions for the retrospective

1. Was the per-handler adoption effort reasonable (target: ≤90 minutes end-to-end)?
2. What new FP / noise classes did strict mode surface, and are any unbounded?
3. Is `strict_replayable` adoption-ready, or does it need a second slice (e.g., a stdlib/SDK whitelist) before real adopters can use it?
4. What's the next unit of work — Vapor corpus (direction 3), global strict-mode config, or `strict_retry_safe`?
