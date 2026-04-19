# Trial Round 6: Receiver-type + Prefix-matching slices vs. `swift-aws-lambda-runtime`

Sixth measurement round. Companion to [`claude_phase_1_plan.md`](claude_phase_1_plan.md), [`claude_phase_1_round_2_plan.md`](claude_phase_1_round_2_plan.md), [`claude_phase_1_round_3_plan.md`](claude_phase_1_round_3_plan.md), [`claude_phase_2_round_4_plan.md`](claude_phase_2_round_4_plan.md), and [`claude_phase_2_round_5_plan.md`](claude_phase_2_round_5_plan.md). First round to validate the two post-R5 precision slices on a corpus that was **not** tuned against.

## Research question (and the overfitting risk R5's post-fix left open)

Round 5's post-fix verification closed with a strong claim: *4/4 correct catches, 0 noise on pointfreeco Run D*. That claim holds — but pointfreeco is also the exact codebase both precision fixes were designed against. The `users.append(...)` noise motivated stdlib exclusion; the `sendGiftEmail → sendEmail` miss motivated prefix matching. A clean result on the training corpus is necessary but not sufficient.

Round 6 asks the separation question:

> "Do the receiver-type gating and camelCase-gated prefix-matching slices produce the same precision profile on a codebase that was not tuned against?"

Operationalised as four sub-questions:

1. **Inference-without-anchor cleanliness.** Does the post-fix linter stay silent on bare un-annotated `swift-aws-lambda-runtime`? R5 Run E had 0 diagnostics on the prior linter; prefix matching widened the match surface, so the null result must be re-confirmed.
2. **Real-code catch yield under an annotation campaign.** Annotating every Lambda handler's `handle(...)` method `@lint.context replayable` is unambiguous (SQS/SNS/API-Gateway triggers genuinely retry). How many diagnostics fire? What's the per-annotation yield compared to pointfreeco's 4-catches-per-5-annotations baseline?
3. **New false-positive surface from prefix matching.** The R5 pointfreeco corpus did not contain code that would stress the camelCase-gated prefix rule's edge cases (`NSString.appending`, `Publisher.publisher(for:)`, `Combine.send(_:)` variants, etc.). Does a different codebase shape expose misses the R5 unit-test suite didn't anticipate?
4. **Stdlib-exclusion coverage completeness.** The exclusion table covers `Array`/`String`/`Set`/`Dictionary` mutation methods observed on pointfreeco. Does the Lambda codebase use stdlib patterns not on the list (`Array.replaceSubrange`? `Dictionary.merge`?), producing noise the R5 evidence did not surface?

## Target selection

**Primary: `apple/swift-aws-lambda-runtime` at `2.8.0`** — the R5 retrospective's original recommendation and the proposal's originally-named validation target. Already cloned shallowly at `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime`. Every Lambda `handle(...)` method is objectively `@context replayable` by SQS/SNS/API-Gateway delivery semantics, so annotation correctness is unambiguous — no "did I get this right?" ambiguity of the kind pointfreeco's Stripe webhook chain required round 3 to work through.

Reasons to pick this over an alternate target:

- **Zero-ambiguity context annotations.** Every example's `handle(...)` is replayable. No subjective annotation calls.
- **Example surface is already catalogued.** `Examples/` contains 14+ handler examples covering BackgroundTasks, APIGateway (v1 + v2 + authoriser), MultiTenant, MultiSourceAPI, Streaming variants, ManagedInstances, Hummingbird integration, JSONLogging. Wide surface for a single-repo campaign.
- **Continuity from R5 Run E.** The cross-project cleanliness result there was 0 diagnostics on a single handler annotation. Round 6 extends that to the full example set.
- **`JSONLogging` example** specifically exercises `swift-log` — partially addressing the R5 retro's OI-5 "untested observational corner" note. Not full-volume stress, but a real `swift-log` call site.

Not chosen (with reasons):

- **`vapor/vapor`.** Too large to annotate exhaustively in a single round. Worth considering for a future round 7 once round 6 validates the mechanism works at all on a second corpus.
- **An internal microservice.** Not accessible in this session. Still a valid future target once the user is ready to bring one in.
- **`apple/swift-nio`.** Explicitly called out in the proposal as the wrong target (reference-type handlers, below business-logic layer).

### Pinned target

- **Repo:** `swift-server/swift-aws-lambda-runtime`
- **Tag:** `2.8.0` (== SHA `553b5e3`)
- **Local clone:** `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` — shallow clone; re-fetch full history during Phase 0 so branch creation and file-history exploration work.

### Pinned linter baseline

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `main` at `68ad3bc` (post-prefix-matching tip)
- **No new linter branch.** Measurement only.

### Pinned trial branch

- **Branch:** `trial-inference-round-6` on the Lambda clone, forked from `2.8.0`. Not pushed.

## Scope commitment (unchanged from rounds 2-5)

- **Measurement only.** No rule changes on `main`. No whitelist edits. No proposal updates during the round; Phase 7 writeup integrates findings afterwards.
- **Annotation-only source edits.** The only modification to Lambda examples: `/// @lint.context replayable` on each example's `handle(...)` method. One new trial-scaffold file (Run C) containing intentional positive + negative injections. No other edits.
- **Throwaway branch, not pushed.** Same as rounds 2-5.
- **Parser/inference-bug carve-out.** If Run A (zero annotations) produces a diagnostic, that's either a rule firing without an anchor or a new precision failure introduced since R5. Pause and triage on a separate linter branch, not on the trial branch.
- **Per-diagnostic FP audit.** Each Run B diagnostic gets a one-line verdict in `trial-findings.md`: *correct catch* / *defensible* / *noise*. Cap audit at 30 diagnostics.

## Phases

Linter is at `68ad3bc`; Phase 0 prep only needs target-side work.

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git pull origin main && swift package clean && swift test`. Expect green; should be ≥ 2049 tests / 267 suites (post-prefix-matching).
- Re-fetch Lambda clone to full depth: `cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime && git fetch --unshallow origin`.
- Fork trial branch from the pinned tag: `git checkout 2.8.0 && git checkout -b trial-inference-round-6`.
- Write `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-6/trial-scope.md`. Must include: pinned linter SHA, pinned target tag, the four research questions above, the explicit list of Lambda examples that will get `@lint.context replayable`, and the planned Run C injection cases.

**Acceptance:** green linter baseline at `68ad3bc`; Lambda clone at `2.8.0` on `trial-inference-round-6`; scope note committed.

### Phase 6 Run A — bare-repo cleanliness (≈15 min)

Bare `2.8.0`, no annotations:

```
git checkout 2.8.0
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
  --categories idempotency
```

**Expected:** 0 diagnostics. No `@context` anywhere means no retry-context rule can fire; no `@effect` means no caller-constraint rule can fire. Inference alone is silent without anchors.

**Carve-out:** non-zero → critical finding. Either a rule regressed since R5 Run E or prefix matching fires on un-anchored code (which would contradict the implementation). Record, pause, triage.

### Phase 6 Run B — comprehensive handle(...) annotation (≈1 day)

Back to `trial-inference-round-6`. Add `/// @lint.context replayable` above every `handle(...)` method in the `Examples/` directory. Preliminary survey (Phase 0 confirms the exact count): 11+ candidates across BackgroundTasks, APIGateway variants, MultiTenant, MultiSourceAPI, Streaming variants, ManagedInstances, HummingbirdLambda, JSONLogging, HelloWorld, HelloJSON.

```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
  --categories idempotency
```

**Expected shape:** N diagnostics where N is the open measurement. No strong prior — Lambda examples are small and often trivial (pass-through echoes, background-task demos). Real hazards will mostly come from prefix-matched network calls and the `JSONLogging` example's logger interactions (which should silence via observational inference, not fire).

**Per-diagnostic FP audit.** Each classified as:

- *correct catch* — a genuine non-idempotent operation inside a replayable context that a careful reviewer would flag
- *defensible* — syntactic signal plausible but context or semantics make it idempotent by design (teams would annotate `@lint.effect` to document)
- *noise* — fires where a human would say "that's fine" and no reasonable annotation would silence it without distorting the model

**Headline thresholds** (same as R5 Run D's framing):
- Noise fraction ≤ 10%: mechanism cleanly generalises to a second corpus.
- Noise fraction 10-25%: concerning but not blocking; catalogue the specific shapes that drove noise, use as input for a targeted third slice.
- Noise fraction > 25%: R5's precision claim was pointfreeco-overfit. Pause adoption advocacy until the noise class is fixed.

**Per-annotation yield.** Report catches per annotation. Comparison point: pointfreeco Run D post-fix produced 4 catches from 5 annotations (0.8 catches/annotation). A Lambda yield substantially higher or lower is itself informative.

### Phase 6 Run C — prefix + stdlib-exclusion anti-injection (≈0.5 day)

New file `Examples/_TrialInferencePhase2Anti/Sources/main.swift` (or similar location that doesn't conflict with an existing example). Contains intentional positive + negative cases specifically for the two new mechanisms.

Positive cases (each should fire exactly one diagnostic):

1. `@lint.context replayable` → `sendNotification(to:)` — prefix match `send` + `N`
2. `@lint.context replayable` → `createResource(spec:)` — prefix match `create` + `R`
3. `@lint.context replayable` → bare `publishEvent(e)` — prefix match, no receiver
4. `@lint.context replayable` → `queue.enqueueBatch(items)` where `queue: UserQueue` — prefix match on user-typed receiver

Negative cases (each should stay silent):

5. `@lint.context replayable` → `str.appending("x")` where `str: String` — stdlib exclusion on String.appending, also camelCase-gated
6. `@lint.context replayable` → `arr.sending(...)` where `arr: [Int]` — stdlib-collection receiver, even if the name matches prefix-gate-wise (it doesn't — `sending` is lowercase `i`)
7. `@lint.context replayable` → `publisher(for: \.prop)` — `publish` prefix + lowercase `e`, camelCase gate blocks
8. `@lint.context replayable` → `postponed(task)` — `post` prefix + lowercase `p`, camelCase gate blocks
9. `@lint.context replayable` → `Task { publish(event) }` — escaping-closure boundary (exact bare-name match inside Task)

**Expected:** 4 diagnostics from cases 1-4; 0 from cases 5-9. Total contribution to the corpus count: +4.

**Acceptance:** exact match to expectations. Any deviation is a unit-level regression that escaped the existing test suite and needs a new unit fixture.

### Phase 6 Run D — expanded stress (optional, ≈0.5 day)

If Run B's results suggest the mechanism is working cleanly (noise ≤ 10%), widen context annotations beyond `handle(...)` to any internal helper the examples dispatch to. This measures whether the rule fires productively on secondary replayable code, not just top-level handlers.

If Run B reveals noise patterns, skip this and use the time for deeper FP investigation.

**Acceptance is discretionary.** Report either the expanded result or the "skipped in favour of Run B analysis" reason.

### Phase 7 — Writeup (≈0.5 day)

Three artefacts under `docs/phase2-round-6/`:

1. **`trial-findings.md`** — counts per run; the Run B FP audit with per-diagnostic verdicts and noise-fraction summary; the Run C 9-row expected-vs-observed table; per-annotation yield; cross-round comparison (R5 post-fix pointfreeco vs R6 Lambda).
2. **`trial-retrospective.md`** — one page. Three pre-committed questions: (a) did the R5 precision claim hold outside pointfreeco? (b) what new adoption-friction shapes did the Lambda campaign surface that pointfreeco didn't? (c) what's the next unit of work — user-defined type-qualified whitelist, the macro package, or another corpus trial?
3. **Amendments to `docs/idempotency-macros-analysis.md` Open Issues** — only if round 6 produces a new class of pattern. Expected: none, but if noise fraction is > 10%, document the specific shapes.

**Acceptance:** user can answer "is the R5 precision claim pointfreeco-specific or does it generalise?" with evidence from two independent corpora and ~14 real annotations.

## Verification end-to-end

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git pull origin main    # expect 68ad3bc
swift package clean && swift test   # expect ≥ 2049/267

cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime
git fetch --unshallow origin
git checkout 2.8.0

# Run A: bare
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 diagnostics

# Run B: trial branch with all handle() methods annotated
git checkout -b trial-inference-round-6
# ... add @lint.context replayable to every handle() ...
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: N diagnostics, each classified

# Run C: _TrialInferencePhase2Anti added
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: Run-B total + 4 (cases 1-4) = N+4

# Run D (optional): widen context beyond handle()
# Expect: reported discretionarily
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint` @ `main` (SHA `68ad3bc`) — linter, no edits
- `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` @ `trial-inference-round-6` — target, not pushed
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-6/` — new deliverables folder
- `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime/Examples/*/Sources/main.swift` — Run B annotations
- `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime/Examples/_TrialInferencePhase2Anti/Sources/main.swift` — Run C, new file

## Fallback

- If Run B produces a noise rate > 25% driven by a single repeatable shape (e.g., a specific prefix-match false positive class), the round is still informative — the writeup names the shape and it becomes the input for a targeted R7-or-slice fix. Don't treat this as a failure.
- If `swift-aws-lambda-runtime` requires a toolchain version incompatible with the linter's `main`, pivot the target to a different Swift-6.x-compatible real codebase. Record the pivot reason in `trial-scope.md`.
- If Run D's widening reveals unanticipated patterns, report the first 10 and stop rather than blowing the round's time budget.

## Total estimated effort

Phase 0: 0.5 day • Run A: 15 min • Run B: 1 day • Run C: 0.5 day • Run D: 0.5 day (optional) • Phase 7: 0.5 day • **~3 days, budget 4 with slack.** Run B is the heavy lift — annotation + per-diagnostic audit on a ~14-handler surface.

## What a clean round 6 unlocks

If round 6 confirms:
- Inference-without-anchor still silent (Run A),
- Catches per annotation in the same order of magnitude as pointfreeco (Run B),
- 4/0 positive/negative on the Run C anti-injection,
- Noise fraction ≤ 10% on Run B real code,

then the R5 precision claim is validated as corpus-independent, and the next natural unit of work becomes:

1. **`SwiftIdempotency` macro package** (roadmap Phase 5) — now the highest-remaining qualitative improvement. Linter precision is adoption-ready on two corpora; next investment is in runtime verification (`@Idempotent`, `IdempotencyKey`, `#assertIdempotent`).
2. **Vapor / internal-microservice third corpus** — only if evidence demands it. Two-corpus cleanliness is a defensible adoption bar; a third corpus has sharply diminishing novelty.
3. **User-defined type-qualified whitelist** — still deferred. With receiver-type gating and prefix matching shipped, the remaining adoption friction is narrower than it was at R5 and may not justify a dedicated slice.

If round 6 produces > 10% noise, the next unit is a targeted fix against the specific shape that drove it, then a round 7 re-measurement. The R5 retro's rhythm ("build → measure → build → measure") holds.
