# Round 13 Trial Retrospective

One page. **First adopter-application validation** in the project's history. Three high-value findings from a 30-minute scan. Worth more than the four prior framework-corpus measurements combined for adoption-cost evidence.

## Did the scope hold?

**Yes — and the scope was modest enough that the value-per-minute beat any prior round.** Six annotations across three Hummingbird example apps. Two scans (replayable, strict_replayable). Three concrete findings, each with a named follow-on.

## Answers to the four pre-committed questions

### (a) Replayable yield on adopter handlers?

**0.00.** First time a corpus produced this with annotated handlers that genuinely contain non-idempotent calls. Cause: the Fluent ORM verb gap (`save`/`update`/`delete`). Adopters using the most common Swift web ORM see no catches without a 3-line heuristic extension.

### (b) Strict surface?

**34 catches across 6 handlers** — 5.7 catches per annotation. Most strict-mode-rich corpus measured. Decomposes into three actionable classes (Fluent ORM, `.init(...)` form, Hummingbird/JWT primitives), each with a clear fix path.

### (c) Gaps named?

Three:
1. **Fluent verbs missing from `nonIdempotentNames`** (`save`/`update`/`delete`). Single highest-priority follow-on. Same shape as PR #8 (`stop`/`destroy`).
2. **`.init(...)` constructor form** missing from PR #9's idempotent-type whitelist (only bare-identifier `JSONDecoder()` matches; `HTTPError(.notFound)` doesn't).
3. **Hummingbird primitives** (`HTTPError`, `JWTPayloadData`, `request.decode`) — broader follow-on for a Hummingbird-specific framework whitelist.

### (d) Mock-service body-masking?

**Yes — surfaced cleanly in `jobs`.** `FakeEmailService.sendEmail` body is purely `logger.info` calls; upward inference correctly classifies it observational; the heuristic-name path's "send → non_idempotent" guess is overridden. Local reasoning is correct, but adopters should know dev-environment fakes can mask intent the prod service would surface.

## What this round changes

The four-corpus summary table the proposal carried (rounds 6-12) said "yield tracks handler-shape composition" — true for framework code. Round 13 adds: **"yield on adopter code tracks heuristic-coverage of the adopter's framework choice."** A Vapor adopter and a Hummingbird adopter using Fluent face the same `0.00` yield until Fluent verbs ship in the heuristic.

This is the first round whose findings are **adoption-blocking**, not just adoption-friction. Without the Fluent verbs in the heuristic, the rule suite produces no catches on the canonical "POST creates duplicate row" bug it was designed for. That's a real shipping blocker for any adopter using Fluent.

## What would have changed the outcome

- **Pre-skim of the `swift_idempotency_targets.md` document.** ChatGPT's curated list explicitly named ORM-hidden-mutation as a likely-issues category (line 102 of the targets doc). A pre-round read would have predicted the Fluent gap before measurement; round 13 confirmed the prediction.
- **A broader annotation campaign on a single example.** 6 annotations across 3 packages spread the evidence thin. A 15-handler campaign on `todos-postgres-tutorial` alone would produce more concentrated cost-per-handler evidence.
- **Including `swift-hummingbird-idempotency-demo` for cross-fixture comparison.** That repo's `OrderService` declares `@lint.effect non_idempotent` on `create`, which the linter explicitly catches. Comparing "annotated demo" vs "real-shape adopter app" would directly measure the heuristic's coverage gap.

## Cost summary

- **Estimated:** 0.5 day.
- **Actual:** ~30 minutes of model time.
- **Biggest time sink:** debugging the `jobs` zero-catch result. The "FakeEmailService body inferred observational" finding emerged from following the upward-inference precedence chain, which took ~10 minutes of careful tracing. Worth it — the finding is one of the round's three headline outputs.

## Policy notes

- **Adopter-app rounds produce qualitatively different findings from framework rounds.** Framework rounds confirm "the rule fires correctly when intent is clear." Adopter rounds find "the rule misses entire classes of real adopter code." Both are valuable; round 13 is the first to deliver the latter.
- **`swift_idempotency_targets.md` is a useful guide.** Tier 1 (Hummingbird examples) was the right starting point — small enough to scan in 30 minutes, varied enough to surface multiple gap classes. Worth using the document's Tier-2 (Vapor + Fluent + jwt-kit) and Tier-3 (Awesome Vapor) tiers as a roadmap for follow-up rounds.
- **Mock/fake-service masking is worth a documentation note.** The finding isn't actionable as code, but adopters using mocks in dev environments deserve to know the linter's behavior. A short note in the proposal's "limitations" section.

## Net output after thirteen rounds

- **Rounds 1-12:** linter mechanism validation across four framework-shape corpora.
- **PRs #6-9:** four cheap heuristic / grammar / whitelist slices, each closing a named gap.
- **Round 13:** **first adopter-app evidence.** Three findings, two of which directly gate adopter-Fluent yield.

## Recommended path after round 13

Two named follow-ons fall out cleanly:

1. **Fluent verb whitelist** (~30 minutes). Add `save`/`update`/`delete` to `nonIdempotentNames`. Same shape as PR #8. Would lift round-13 replayable yield from 0.00 to ~0.67 (5/6 expected catches: list = silent-by-correctness, others fire). Trivial slice.

2. **`.init(...)` constructor recognition** (~1-2 hours). Extend the type-constructor whitelist (PR #9) to also match `Type.init(...)` member-access form. Would silence ~10/34 of round-13's strict diagnostics. Modest extension.

3. (Lower priority) **Hummingbird-specific framework whitelist.** Larger slice; benefits adopters of one framework; defer until adopter base is established.

My pick: **(1) immediately**, then re-measure round 13 to confirm the lift. If the re-measurement shows the predicted yield jump, that's strong adopter-evidence the rule suite is now ready for Fluent users. (2) follows naturally as the "now strict mode is usable on adopter Fluent code" slice.

## Data committed

- `docs/phase2-round-13/trial-scope.md` — this trial's contract
- `docs/phase2-round-13/trial-findings.md` — per-handler audit and five-corpus comparison
- `docs/phase2-round-13/trial-retrospective.md` — this document
- `docs/phase2-round-13/trial-transcripts/run-{A,B,C}.txt` — counts per-package per-mode

Hummingbird-examples annotations remain in-place; revert with `git checkout` per file. No linter changes this round (measurement only).
