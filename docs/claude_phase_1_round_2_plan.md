# Trial Round 2: Swift Idempotency Linter vs. a second real codebase

Companion plan to [`claude_phase_1_plan.md`](claude_phase_1_plan.md) (round 1 — `apple/swift-aws-lambda-runtime` 2.8.0). Round 1 shipped Phase 1 *plus* four post-trial follow-ups (OI-3 mutating-method detection, OI-4 cross-file propagation, OI-5 `observational` tier, escaping-closure coverage fix). Round 2 road-tests that post-follow-up Phase 1 against a second, **stylistically different** codebase.

## Research question

"Does Phase 1 — now including the shipped `observational` tier and cross-file resolution — hold up on a codebase that is not serverless event-handling?" Specifically:

1. Does `actorReentrancy` produce a similar Category-B noise rate on an HTTP-server style actor population, or does a different pattern dominate?
2. Does the new `observational` tier correctly absorb the Logger/metrics calls that the critique predicted would otherwise dominate the false-positive profile?
3. Does cross-file resolution (OI-4) behave on a multi-module SPM target where callers and callees genuinely span files?

Round 1 answered "false-positive rate on a well-maintained codebase." Round 2 answers "does that result generalize beyond the target that most flattered it."

## Target selection

### Shortlist considered

| Target | Why interesting | Why not |
|---|---|---|
| **`hummingbird-project/hummingbird` 2.x** | Different domain from Lambda (server, not event). Modern Swift 6 actors throughout. First-class `swift-log` / `swift-metrics` integration — direct stress test for the `observational` tier. Medium size (~150 source files), tractable in a single session. Well-maintained, pinned releases. | None that disqualify. Recommended primary. |
| `swift-server/async-http-client` | Deeper concurrency: explicit retry loops, connection-pool actor, request queue. Sharpest `actorReentrancy` stress test available. | Narrower — exercises one rule hard, the other two lightly. Annotation-gated rules would be near-silent. Fallback, not primary. |
| `vapor/vapor` | Large mature ecosystem. Most likely to surface novel patterns. | Size (>400 source files across sub-packages) risks scope blowout. Defer to round 3 if round 2 validates the approach. |
| `pointfreeco/pointfreeco` | Real application with real business logic; Stripe integration would genuinely benefit from idempotency analysis. | Stripe/payment calls would tempt Phase 2 scope (externally-idempotent tier, `IdempotencyKey`). That's the *opposite* trial — belongs in a Phase 2 road-test, not a Phase 1 generalization test. |
| `apple/swift-nio` | — | Explicitly called out by proposal as the wrong target. Skip. |

### Recommendation: `hummingbird-project/hummingbird`

Three reasons it's the right round 2:

1. **Different domain.** Round 1 was an event-driven serverless runtime. Round 2 on an HTTP server framework tests whether the rule shapes transfer. If they do, "domain-general Phase 1" is defensible. If they don't, that's a finding worth having.
2. **Stresses the `observational` tier.** Hummingbird handlers and middleware log and emit metrics as a matter of course. Any middleware body that calls `logger.info(...)` under a hypothetical `@context replayable` annotation is exactly the false-positive pattern the tier was shipped to absorb. The tier has passed unit fixtures but has not been exercised on a codebase with heavy logging. This trial is the first production-shape test.
3. **Actors look different from Lambda's.** `LambdaRuntimeClient`'s three Category-B findings were all one state-machine-invariant pattern on one stored property. Hummingbird's actors (router storage, middleware chains, connection state) are shaped differently. Whether the Category-B rate stays at ~1/100-files or moves meaningfully tells us whether "one-per-critical-stateful-actor-file" is a generalizable estimate or a Lambda-specific coincidence.

### Pinned target

- **Repo:** `hummingbird-project/hummingbird`
- **Tag:** latest `2.x` stable release at trial start (record the exact tag + SHA in `trial-scope.md` during Phase 0 — both machines pin to the same SHA; do not upgrade mid-trial)
- **Local clone:** `/Users/joecursio/xcode_projects/hummingbird`

### Pinned linter branch

- **Repo:** `SwiftProjectLint`
- **Branch:** **new** branch `idempotency-trial-round-2`, forked from the head of `idempotency-trial` (so round 1's post-follow-up state is the baseline). **Do not** merge back into round 1's branch — separate trials, separate branches.

## Scope commitment (same as round 1, with one addition)

The out-of-scope list from [`phase1/trial-scope.md`](phase1/trial-scope.md) holds unchanged. Specifically, still **out** of scope for round 2:

- Effect inference
- Tiers beyond `idempotent` / `non_idempotent` / `observational` *(round 1 shipped `observational`; the rest of the lattice remains deferred)*
- Contexts beyond `replayable` / `retry_safe`
- Strict mode, scoped idempotency, `@lint.assume`, `@lint.unsafe`, suppression grammar
- `@Idempotent` macro, `IdempotencyTestable`, `IdempotencyKey`, `#assertIdempotent`, protocol-based layer
- Retry pattern detection

**New guardrail specific to round 2:** no rule changes are made on the trial branch. Round 1's retrospective explicitly notes that pulling fixes forward mid-trial conflates "does this rule work?" with "how should this rule evolve?". Round 2 is purely a measurement exercise. Any issue surfaced → recorded as Open Issue in the proposal, not fixed on the branch. The one exception is a **parser bug** producing false annotations (Run A non-zero on un-annotated source) — same carve-out as round 1.

## Phases

Round 1 built the linter. Round 2 does not rebuild it. Phases 1 and 2 from round 1 are skipped; the numbering below is kept parallel to round 1 so cross-references are obvious.

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git checkout idempotency-trial && git pull && swift package clean && swift test`. Baseline must be green (expected: 1844 tests / 251 suites / 0 known issues per round-1 follow-ups).
- Create branch: `git checkout -b idempotency-trial-round-2 && git push -u origin idempotency-trial-round-2`.
- `git pull` in `/Users/joecursio/xcode_projects/swiftIdempotency`.
- Clone `hummingbird-project/hummingbird` at the chosen pinned tag into `/Users/joecursio/xcode_projects/hummingbird`. Record the exact tag + commit SHA.
- Create `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase1-round-2/trial-scope.md` — short doc, mirrors round 1's scope doc but points at Hummingbird and the new branch. Commit immediately. This is the text pointed at when a finding tempts scope expansion.

**Acceptance:** green baseline; pinned clone; new branch pushed; scope note committed.

### Phase 1 — SKIPPED

Linter already built in round 1. No changes on this branch.

### Phase 2 — SKIPPED

Fixtures already green (1844 tests). Re-run the suite once on the new branch to confirm nothing regressed on the clean fork-point, then move on.

### Phase 3 — Positive demonstration on a Hummingbird-shaped handler (≈0.5 day)

Round 1 demonstrated the happy path with a Lambda-shaped handler. Round 3 repeats the exercise with a Hummingbird-shaped handler, because the annotation placement differs meaningfully (middleware vs. closure handler vs. controller method) and the worked example should reflect the target idiom.

- Extend the existing `/Users/joecursio/xcode_projects/swift-lambda-idempotency-demo/` package — **or** create a sibling `/Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo/` if mixing runtimes would pollute the original. Recommend the sibling package: cleaner separation, and round 1's demo stays as the Lambda reference.
- Two handler states, both against a stub `OrderService` type:
  1. **Before:** Hummingbird route handler annotated `/// @lint.context replayable`, calls `orderService.create(...)` where `create` is declared `@lint.effect non_idempotent`. Expect one `nonIdempotentInRetryContext` diagnostic. *Then* add a `logger.info("creating order \(id)")` call in the same handler (with `Logger.info` declared `@lint.effect observational` via a stub) — expect **still exactly one** diagnostic, not two. This is the new assertion: the `observational` tier must not itself trip retry-context rules.
  2. **After:** `create` → `upsert` (`@lint.effect idempotent`). Keep the `logger.info` call. Expect zero diagnostics.
- Capture CLI output verbatim for both runs.

**Acceptance:** before state produces exactly one diagnostic on the non-idempotent call and **none** on the logger call. After state produces zero. Transcripts archived in `docs/phase1-round-2/trial-transcripts/`.

### Phase 4 — False-positive baseline on Hummingbird (≈1 day)

The measurement phase — round 2's core deliverable.

**Run A — full Hummingbird, no annotations.**
```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/hummingbird --categories idempotency
```
Annotation-gated rules expected to produce **zero diagnostics**. Any diagnostic is a parser bug (round 1's Run A was clean; a non-zero here would be a regression on a different corpus — file immediately as a parser issue, still on the out-of-scope carve-out for round 2).

**Run B — structural `actorReentrancy` on Hummingbird.**
```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/hummingbird --categories codeQuality --threshold warning \
  2>&1 | tee docs/phase1-round-2/trial-transcripts/hummingbird-runB.txt
```
Filter to `actorReentrancy`. Each diagnostic is a false-positive candidate — triage into the same three buckets as round 1:

- **A — true positive.** A real `check → await → write` on an actor-owned dedup gate. Unlikely given codebase quality; possible.
- **B — AST match, design-intent mismatch.** The round 1 canonical shape was state-machine invariant assertions. Round 2 will likely surface *different* B-subtypes: connection-pool membership checks, router trie lookups followed by network I/O, middleware ordering guards. For each finding, record the one-sentence reason the AST cannot distinguish intent, and note whether it's the same subtype as round 1 or a new one. New B-subtypes refine OI-1 further.
- **C — rule bug.** File; do not fix on the trial branch.

**Headline metric to record:** false-positives-per-critical-stateful-file. Round 1 = 3 / 1 critical file = 3 per file, or 3 / ~100 runtime files = ~0.03 per file overall. Compute both ratios for round 2 and compare. If either ratio is within 2× of round 1, Phase 1's noise profile is generalizable. If it's 5× higher, the "defensible for adoption" claim needs qualifying.

**Run C — single annotated handler in a Hummingbird example.**
If Hummingbird ships example apps (check `Examples/` or similar), annotate one handler with `/// @lint.context replayable` on a throwaway local branch (`trial-annotation-local` — do not push). Add a call to something the per-file/cross-file symbol table should resolve to a declared `non_idempotent` (e.g., a stub in the same module). Re-run `--categories idempotency`. Expected: one diagnostic if resolution works cross-file, zero if the callee is unreachable. **The key check vs. round 1 is that OI-4's cross-file resolution actually fires on a non-trivial multi-file layout.** Round 1's demo had the callee in the same file; round 2's should not.

**Run D (new — specific to round 2) — `observational` tier under load.**
Find or create a branch of Hummingbird where 3–5 representative middlewares carry `@lint.context replayable`, and the corpus's `Logger.info` / `Metrics.counter` primitives carry `@lint.effect observational`. Run `--categories idempotency` and count diagnostics. Expected: zero from logging/metrics. **This is the decisive test of the OI-5 follow-up.** If the tier correctly absorbs observational calls at realistic volume, OI-5 ships cleanly. If the rule still flags observational calls under any shape (e.g., a log call routed through a custom wrapper function that *itself* wasn't annotated), record the shape — the fix is a cross-file propagation question, not a tier-definition question, and belongs in OI-4 follow-up territory.

### Phase 5 — Write-up (≈0.5 day)

Three artifacts, mirroring round 1's deliverables under a new folder `docs/phase1-round-2/`:

1. **`docs/phase1-round-2/trial-findings.md`** — counts per rule, triaged buckets for `actorReentrancy` with a **delta table vs. round 1** (same pattern / new pattern / absent), representative quoted diagnostics, Phase 3 before/after transcripts verbatim, Run D observational-tier verdict, cross-file resolution confirmation from Run C.

2. **Updates to `docs/idempotency-macros-analysis.md` Open Issues section** — only if round 2 surfaces patterns round 1 did not. If the `observational` tier holds up, update OI-5's status from "shipped, validated on one target" to "validated on two targets." If new `actorReentrancy` B-subtypes appear, they feed OI-1's scope discussion — don't invent new OI-numbers unless the pattern is genuinely distinct.

3. **`docs/phase1-round-2/trial-retrospective.md`** — one page. Did the scope commitment hold a second time? Which findings tempted expansion? Did round 2 change the "Phase 1 defensible for adoption" conclusion, strengthen it, or weaken it? If strengthened → Phase 1 ships. If weakened → name the specific shape that weakens it and what round 3 would need to look like.

**Acceptance:** user can answer "does Phase 1's noise profile transfer to a second codebase?" with a comparison table, not a single-target anecdote.

## Verification end-to-end

From a fresh terminal on either machine:

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout idempotency-trial-round-2 && git pull
swift package clean && swift test                        # 1844+ tests green on the new branch

# Phase 3 before/after (demo package)
cd /Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect exactly one nonIdempotentInRetryContext diagnostic; zero from logger call.
# Flip to after-state:
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect zero diagnostics.

# Phase 4 Run A
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/hummingbird --categories idempotency
# Expect zero.

# Phase 4 Run B
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/hummingbird --categories codeQuality --threshold warning
# Triage per trial-findings.md.
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint` @ `idempotency-trial-round-2` — linter, branched from round 1's post-follow-up state
- `/Users/joecursio/xcode_projects/hummingbird` — target, pinned tag + SHA recorded in scope doc
- `/Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo/` — new demo package for Phase 3
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase1-round-2/` — deliverables folder (scope, findings, retrospective, transcripts)
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/idempotency-macros-analysis.md` — Open Issues amendments, if any

## Fallback target

If Hummingbird turns out not to be on Swift 6 / SwiftSyntax 602 compatible (check at Phase 0 — worth spending 30 min verifying before branch creation), fall back to `swift-server/async-http-client` at its latest tag. The phase structure and scope commitment are identical; only the target differs. Record the pivot in `trial-scope.md` with a one-line reason.

## Total estimated effort

Phase 0: 0.5 day • Phase 3: 0.5 day • Phase 4: 1 day • Phase 5: 0.5 day • **~2.5 days, budget 3.5 with slack.** Substantially lower than round 1 because the linter and fixtures are already built; Phase 4's Run B + Run D triage is the biggest time investment.

## What a clean round 2 unlocks

If round 2 reproduces round 1's noise profile within a factor of 2×, and Run D confirms the `observational` tier absorbs logging at realistic volume, Phase 1 is validated on two stylistically different codebases and ready to propose for adoption without further trials. A round 3 would then be a Phase 2 road-test (effect inference, `externallyIdempotent`, `IdempotencyKey`) against a codebase with real Stripe/SES/third-party calls — `pointfreeco/pointfreeco` or a small internal microservice — a categorically different exercise from this trial.
