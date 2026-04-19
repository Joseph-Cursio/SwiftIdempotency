# Trial Round 5: Phase 2 Heuristic + Upward Inference vs. un-annotated real code

Fifth measurement round. Companion to [`claude_phase_1_plan.md`](claude_phase_1_plan.md), [`claude_phase_1_round_2_plan.md`](claude_phase_1_round_2_plan.md), [`claude_phase_1_round_3_plan.md`](claude_phase_1_round_3_plan.md), and [`claude_phase_2_round_4_plan.md`](claude_phase_2_round_4_plan.md). First round to validate the **inference machinery** — every prior round ran declared-annotation enforcement only.

## Research question

Round 4's retrospective named heuristic inference as the highest-value unshipped piece, arguing it would "convert rounds 2 and 3's 'zero diagnostics on un-annotated source' from 'parser-clean but uninformative' to 'parser-clean AND catches real things.'" Four commits landed on the linter's `main` after round 4:

- `83c828c` — `HeuristicEffectInferrer` (bare-name + two-signal observational)
- `b4c1a81` — `UpwardEffectInferrer` (one-hop body-lub inference)
- `14a38df` — multi-hop API, default off
- `cf128da` — visitors wired to multi-hop; chain-depth surfaced in diagnostic prose

Round 5 answers:

> "Does the inference machinery deliver useful signal on un-annotated real code without producing enough false positives to teach users to disable the category?"

Three sub-questions:

1. **Does inference alone reproduce round 3's diagnostic?** Round 3 hand-annotated four functions (`handlePaymentIntent` context + three effect annotations) to catch one `handlePaymentIntent → sendGiftEmail` edge. Can inference reach the same diagnostic with one annotation (`handlePaymentIntent` context only) or zero annotations?
2. **Is the diagnostic count on un-annotated real code acceptable?** "Acceptable" means every fired diagnostic is either a correct catch or a defensible over-eager match — no confusing cases where a human would say "wait, why did that fire?"
3. **Does inference stay clean on a second corpus?** A bare-name whitelist that catches `sendGiftEmail` in a webhook context must also not noise up a codebase that happens to use `.send` for unrelated operations. `swift-aws-lambda-runtime` is the proposal's original recommended target and has never been exercised — it's the natural cross-project sanity check.

## Target selection

**Primary: `pointfreeco/pointfreeco`** at the same pinned SHA as rounds 3 and 4 (`06ebaa5`). Continuity with the existing annotation campaign is the main value: the same webhook chain is already understood, and deltas against rounds 3/4's diagnostic counts are directly interpretable.

**Secondary: `apple/swift-aws-lambda-runtime`** — single Run E. The proposal's original target. Every SQS/SNS handler is objectively `@context replayable`, so any inference-driven diagnostic on an un-annotated Lambda handler is useful evidence. Crucially, Run E tests "doesn't noise up unrelated code" — which pointfreeco-only cannot.

### Pinned targets

- **pointfreeco:** `06ebaa5276485c5daf351a26144a7d5f26a84a17` (unchanged from rounds 3-4)
- **swift-aws-lambda-runtime:** pin at the latest release tag available when the round starts; record in `trial-scope.md`
- **Local clones:** `/Users/joecursio/xcode_projects/pointfreeco` (LFS-skipped; reuse round-3/4 setup), `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` (fresh clone at Phase 0)

### Pinned linter baseline

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `main` at `9cc3bfe` (current tip; contains heuristic + multi-hop upward inference + `onceContractViolation`)
- **No new linter branch.** Measurement only.

### Pinned trial branches

- **pointfreeco:** `trial-inference-local`, forked from `trial-annotation-phase2-local` (round 4's leftover) then reverted to bare `06ebaa5` before Run A. Not pushed.
- **swift-aws-lambda-runtime:** fresh clone, no trial branch; runs against the pinned tag directly.

## Scope commitment

- **Measurement only.** No rule changes on `main`. No inference-whitelist edits. No proposal updates during the round.
- **Zero or one annotations on the target.** Run B uses *at most one* annotation (`@lint.context replayable` on `handlePaymentIntent`) to measure the annotation-burden delta vs round 3. Other runs use zero annotations.
- **Throwaway branch, not pushed.** Same as rounds 2-4.
- **Parser/inference-bug carve-out.** If Run A produces a diagnostic on completely un-annotated, context-free pointfreeco code, that's either (a) a new rule firing unexpectedly or (b) heuristic inference over-firing without a retry context. Investigate before continuing; the fix lands on a separate linter branch, not on the trial branch.
- **FP audit is part of scope.** Each fired diagnostic gets a one-line verdict in `trial-findings.md`: correct catch / defensible / noise. "Noise" triggers a proposal amendment, not a trial-branch edit.

## Phases

Linter is at `9cc3bfe`; no inference-side edits needed. Phases mirror round 4's numbering.

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git checkout main && swift package clean && swift test`. Record test count; expect > round-4's 1890/256 given the post-R4 additions (inference + once-contract tests).
- Clone/checkout targets: reset pointfreeco to `06ebaa5` on a fresh `trial-inference-local` branch; clone swift-aws-lambda-runtime at the chosen tag.
- Write `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-5/trial-scope.md`. Must include: pinned linter SHA, both pinned target SHAs/tags, the explicit inference-specific research questions, and the "at most one annotation" rule.

**Acceptance:** green linter baseline; both target clones pinned; scope note committed.

### Phase 5 Run A — pointfreeco, zero annotations (≈30 min)

Bare `06ebaa5`, no annotations anywhere.

```
cd /Users/joecursio/xcode_projects/pointfreeco
git checkout 06ebaa5
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI . \
  --categories idempotency
```

**Expected:** 0 `nonIdempotentInRetryContext` diagnostics (no retry context declared anywhere — rule cannot fire without a `@context` annotation). `idempotencyViolation` may fire if inference assigns an effect to an annotated *caller* that has a declared effect — but there are no annotated callers either, so: 0 diagnostics total.

This is the "inference doesn't over-fire on context-free code" baseline. Matches round 4's Run A result in spirit — parser cleanliness, now inference-cleanliness.

**Carve-out:** non-zero → inference firing without a context anchor. Record, triage, pause the round.

### Phase 5 Run B — one context annotation, inference does the rest (≈0.5 day)

Single edit to `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift` on `trial-inference-local`:

```diff
+ /// @lint.context replayable
  func handlePaymentIntent(...) async throws -> ... { ... }
```

No other annotations. In particular: `sendGiftEmail` stays un-annotated. Re-run linter.

**Expected:** exactly one `nonIdempotentInRetryContext` diagnostic on the `handlePaymentIntent → sendGiftEmail` edge, with inference-credited prose: either "whose effect is inferred `non_idempotent` from its body via N-hop chain of un-annotated callees" (upward inference reached a `.send`/mailgun-shaped call inside `sendGiftEmail`'s body) or "whose effect is inferred `non_idempotent` from the callee name `send`" if the bare-name whitelist matches somewhere in the chain.

**Headline finding if it works:** round 3's four-annotation campaign collapses to one annotation. The annotation burden that round 3's retrospective called "the dominant Phase-1 adoption friction" is materially reduced by the shipped inference.

**If Run B produces 0 diagnostics:** either the inferrer didn't reach `sendGiftEmail`'s mailgun call (escaping-closure boundary? non-direct call shape?), or `sendGiftEmail`'s body doesn't actually use a bare-whitelist name. Record the chain the inferrer *did* trace; the gap is evidence for the next inference slice (receiver-type or YAML whitelist).

**If Run B produces >1 diagnostic:** each additional diagnostic gets an FP-audit entry. Likely sources: other replayable-context helpers called from `handlePaymentIntent` that reach a non-idempotent leaf via inference. These are also headline findings — round 3's annotation campaign may have under-reported real hazards.

### Phase 5 Run C — intentional inference-mode injection (≈0.5 day)

New file `Sources/PointFree/Webhooks/TrialInferenceAnti.swift` on the same trial branch. One intentional violation per inference mode:

1. **Bare-name downward, non-idempotent:** `@lint.context replayable` function calls un-annotated `publish(...)`. Expect: 1 diagnostic, prose credits bare-name heuristic.
2. **Bare-name downward, idempotent caller constraint:** `@lint.effect idempotent` function calls un-annotated `insert(...)`. Expect: 1 diagnostic (`idempotencyViolation`, inference-credited).
3. **Two-signal observational:** `@lint.effect observational` function calls `someOtherLogger.info(...)`. Expect: 0 diagnostics (both observational — no violation).
4. **Two-signal observational, contamination:** `@lint.effect observational` function calls `queue.enqueue(...)`. Expect: 1 diagnostic (observational → inferred-non-idempotent).
5. **One-hop upward:** un-annotated helper `foo()` whose body calls `UUID().uuidString`-style sink. Caller `@lint.context replayable` calls `foo()`. Expect: 1 diagnostic, upward-inferred, `depth: 1`.
6. **Multi-hop upward:** three-deep un-annotated chain with a non-idempotent leaf. Caller `@lint.context replayable`. Expect: 1 diagnostic, upward-inferred, `depth: 3`.

Plus three negative cases:

7. **Ambiguous bare name `save`:** un-annotated `store.save(...)` from a retry context. Expect: 0 diagnostics (deliberately out-of-whitelist).
8. **Bare name, wrong receiver type for observational:** un-annotated `customThing.debug(...)` from a retry context. Expect: 0 diagnostics (fails the two-signal gate).
9. **Escaping-closure boundary:** non-idempotent call inside `Task { }` within a `@lint.context replayable` function. Expect: 0 diagnostics (escaping-closure policy).

**Expected totals:** 5 diagnostics from cases 1, 2, 4, 5, 6; 0 from cases 3, 7, 8, 9. Matches unit-fixture behaviour at corpus scale.

### Phase 5 Run D — FP audit on pointfreeco with widened context (≈0.5 day)

Back to the trial branch from Run B. Add `@lint.context replayable` to every entry point in `Sources/PointFree/Webhooks/` (not just `handlePaymentIntent` — all webhook handlers). Still zero effect annotations. Re-run.

**Expected:** some number N of `nonIdempotentInRetryContext` diagnostics. N is unknown ahead of time — that's the measurement. Each fired diagnostic gets a verdict in `trial-findings.md`:

- **correct catch** — the code genuinely loses idempotency on replay (teams should fix)
- **defensible** — the code is non-idempotent by syntactic signal but the context guarantees no retry at this path (teams should add `@lint.effect` to document)
- **noise** — inference fired somewhere a human reader would say "no, that's fine" and no reasonable annotation would silence it without distorting the model

**Scope ceiling:** if N > 30, stop auditing at 30. Twenty to thirty verdicts is enough to estimate a noise rate; past that is diminishing returns for a trial document.

**Headline finding:** the noise fraction. If ≤ 10% are "noise" by the above classification, inference is adoption-ready. If > 25%, the first-slice whitelist needs pruning and the next plan is a whitelist-tuning round rather than new inference surface.

### Phase 5 Run E — swift-aws-lambda-runtime cross-project sanity (≈0.5 day)

Fresh clone at the pinned tag. No trial branch, no annotations.

```
cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI . \
  --categories idempotency
```

**Expected:** 0 diagnostics. Same logic as Run A — no context annotations means no retry-context rule can fire; no effect annotations means no caller-constraint rule can fire. Inference alone is incapable of producing a diagnostic without *some* anchor.

This is the cheap cross-project check that the inference machinery doesn't emit spurious output on an entirely different codebase shape.

**If Run E produces diagnostics:** critical finding. Either a rule is firing without an anchor (bug) or the proposal's claim that "declared annotations are the only source of positional constraints" is wrong. Either way, the round pauses and the linter gets a follow-up branch.

**Light-touch extension (optional, time permitting):** annotate one Lambda handler's `handle(...)` method `@lint.context replayable`. Re-run. Expect: 0 or more diagnostics, each going into the FP audit in the same format as Run D. Cross-project FP evidence is strictly more valuable than more pointfreeco FP evidence, so if Run D's scope ceiling was reached at 30, invest the remaining time here.

### Phase 6 — Write-up (≈0.5 day)

Three artefacts under `docs/phase2-round-5/`:

1. **`trial-findings.md`** — counts per run; delta table vs round 3's 4-annotation-1-diagnostic baseline; Run B's "diagnostic reproduced with one annotation" framing (or the chain-gap finding if it didn't); Run C's 9-row expected-vs-observed table with chain-depth values; Run D's FP audit with per-diagnostic verdicts and a noise-fraction summary; Run E's clean/noisy verdict.
2. **`trial-retrospective.md`** — one page. Three pre-committed questions: (a) did inference deliver on the R4 retro's "catches real things" claim? (b) what's the noise rate, and does it clear the 10%-adoption-ready threshold? (c) what's the next unit of work — YAML whitelist, receiver-type inference, the macro package, or the internal-microservice target?
3. **Amendments to `docs/idempotency-macros-analysis.md`** — only if round 5 surfaces patterns rounds 1-4 didn't. Most likely: the "Still deferred" bullet under Phase 2 gets replaced with evidence-backed prioritization ("YAML before receiver-type because Run D showed X" or vice versa).

**Acceptance:** user can answer "is heuristic + upward inference adoption-ready, and how much annotation burden does it remove on a real webhook chain?" with per-diagnostic verdicts from one continuity corpus, one cross-project corpus, and 9 fixture-mirroring injections.

## Verification end-to-end

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout main    # 9cc3bfe
swift package clean && swift test
# Expect: green, ≥ round-4's 1890/256

# Run A: bare pointfreeco
cd /Users/joecursio/xcode_projects/pointfreeco
git checkout 06ebaa5
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 diagnostics

# Run B: one-annotation context-only
git checkout trial-inference-local   # adds @lint.context replayable
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 1 diagnostic, inference-credited prose

# Run C: TrialInferenceAnti.swift added
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: Run-B total + 5 new diagnostics = 6 total

# Run D: widened context
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: N diagnostics, classify each

# Run E: swift-aws-lambda-runtime, zero annotations
cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI . \
  --categories idempotency
# Expect: 0 diagnostics
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint` @ `main` (SHA `9cc3bfe`) — linter, no edits
- `/Users/joecursio/xcode_projects/pointfreeco` @ `trial-inference-local` — one-annotation + anti-injection trial, not pushed
- `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` @ pinned tag — cross-project fresh clone
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-5/` — new deliverables folder
- `/Users/joecursio/xcode_projects/pointfreeco/Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift` — Run B one-line edit
- `/Users/joecursio/xcode_projects/pointfreeco/Sources/PointFree/Webhooks/TrialInferenceAnti.swift` — Run C, new file

## Fallback

- If Run B's inference chain doesn't reach `sendGiftEmail`'s mailgun call, pivot to "what *did* the inferrer catch, and what annotation would be needed to close the gap?" — that answer is itself the Run B finding, and frames the receiver-type vs YAML whitelist priority question for the next plan.
- If Run D's noise rate exceeds 25%, pivot to whitelist-tuning rather than continuing to new inference surface. The trial record treats this as the honest result, not a blocker.
- If swift-aws-lambda-runtime requires a toolchain version incompatible with the linter's `main`, skip Run E and note the gap — cross-project evidence is valuable but not required for the round to be a net positive.

## Total estimated effort

Phase 0: 0.5 day • Run A: 30 min • Run B: 0.5 day • Run C: 0.5 day • Run D: 0.5 day • Run E: 0.5 day • Phase 6: 0.5 day • **~3 days, budget 4 with slack.** Run B is the most likely to surface surprises (chain-reach assumptions about upward inference on real code are untested). Run D is the largest single measurement effort — budget the audit at 15-20 minutes per diagnostic.

## What a clean round 5 unlocks

If round 5 confirms:
- Inference stays silent without an anchor (Runs A and E),
- Round 3's one-diagnostic finding reproduces with one annotation (Run B),
- All six injected-positive cases fire with correct depth/provenance and all three negatives stay silent (Run C),
- Run D's noise rate is ≤ 10%,

then heuristic + upward inference is validated as adoption-ready on the same basis Phase 1 and Phase 2.1 were: multiple-corpus cleanliness + intentional-violation detection + explicit FP audit. The next natural unit of work becomes:

1. **YAML-configurable whitelist and receiver-type inference** (roadmap Phase 2 second slice) — prioritization informed by Run D's per-diagnostic verdicts.
2. **`SwiftIdempotency` macro package** (roadmap Phase 5) — brand-new Swift package, new repo, macro-based test generation. Round 5's inference evidence strengthens the case: the linter half of the stack is now adoption-ready, so the next investment is in the runtime verification layer the macro package provides.
3. **Validation against an internal microservice with `swift-log` volume** — OI-5's untested corner, still pending.

Which comes next is a scope question for after round 5 lands. This plan does not pre-commit to any of them.
