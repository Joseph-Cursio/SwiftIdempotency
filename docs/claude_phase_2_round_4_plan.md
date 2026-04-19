# Trial Round 4: Phase 2.1 (externally_idempotent + missingIdempotencyKey) vs. `pointfreeco/pointfreeco`

Fourth measurement round of the idempotency proposal. Companion to [`claude_phase_1_plan.md`](claude_phase_1_plan.md), [`claude_phase_1_round_2_plan.md`](claude_phase_1_round_2_plan.md), and [`claude_phase_1_round_3_plan.md`](claude_phase_1_round_3_plan.md). First round to validate **Phase 2** features on a real codebase — every prior round ran the Phase-1 linter.

## Research question (and why the round-3 retrospective almost got it right)

Round 3's retrospective named three candidate round-4 targets. For `pointfreeco/pointfreeco` it said:

> "Would exercise the externallyIdempotent tier, IdempotencyKey strong type, and #assertIdempotent macro — all of which round 2 left untouched."

The round-3 plan document corrected that framing on the grounds that those features didn't exist in code. **Two of the three now exist:** the `externally_idempotent` lattice tier shipped as `1a204ea`, and the `missingIdempotencyKey` key-routing verifier shipped as `2c1c702`. `IdempotencyKey` strong type and `#assertIdempotent` macro still don't exist — they'd require the `SwiftIdempotency` macro package that remains unbuilt.

So the corrected round-4 research question is:

> "Does Phase 2.1's shipped design hold up on a real codebase — specifically on the exact webhook chain round 3 used to motivate the features?"

Round 4 answers this for three sub-questions:

1. **Parser scaling at Phase 2.1.** Does the new `(by: paramName)` grammar extension stay silent on 918 un-annotated pointfreeco files? Round 3 confirmed Phase-1 parser cleanliness; round 4 validates the grammar extension doesn't regress.
2. **Does round 3's one real-code diagnostic change under Phase 2's lattice?** Round 3's `handlePaymentIntent → sendGiftEmail` edge fired because Phase 1 only had `non_idempotent` as the weakest tier; Phase 2 has a third position (`externally_idempotent`) that the annotation *should* have used. Re-running the round-3 annotation campaign with Phase-2 tier choices tells us whether round 3's diagnostic was a genuine bug-catch or a phase-appropriate artifact.
3. **Does `missingIdempotencyKey` fire correctly on real code when a realistic annotation campaign adds the key-routing parameter to `sendGiftEmail`?** This is the adoption-story test — the closest the trial record comes to "what happens when a team actually adopts this."

## Target selection

Same as round 3 — `pointfreeco/pointfreeco` at the same pinned SHA. Reasons:

- **Continuity.** The round-3 findings document identified `sendGiftEmail` as the canonical `externally_idempotent` target. Round 4 revisits that exact claim with the feature shipped.
- **Delta-analysis value.** Running on the same corpus means diagnostic-count deltas across rounds are meaningful. A new target would conflate "Phase 2 works" with "new target surfaces new patterns."
- **Zero setup cost.** The existing clone at `/Users/joecursio/xcode_projects/pointfreeco` is already pinned and LFS-skipped; the `trial-annotation-local` branch holds round-3's annotations and can fork from there.

### Pinned target

- **Repo:** `pointfreeco/pointfreeco`
- **SHA:** `06ebaa5276485c5daf351a26144a7d5f26a84a17` (unchanged from round 3)
- **Swift-tools-version:** 6.3
- **Local clone:** `/Users/joecursio/xcode_projects/pointfreeco` (LFS-skipped)

### Pinned linter baseline

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `main` at `2c1c702` (post-`missingIdempotencyKey`)
- **No new linter branch.** Round 4 runs against main's tip. Measurement-only; no code changes on the linter side.

### Pinned pointfreeco trial branch

- **Branch:** `trial-annotation-phase2-local` in the pointfreeco clone, forked from `trial-annotation-local` (round 3's leftover branch).
- **Not pushed anywhere.** Throwaway, same policy as rounds 2 and 3.

## The scope question round 4 has to answer upfront

Unlike rounds 1–3, round 4 cannot be done through annotations alone. The `externally_idempotent(by: paramName)` grammar requires the callee to have a parameter that carries the key — and pointfreeco's `sendGiftEmail(for gift: Gift)` currently has no such parameter. Three honest options:

- **(A) Documentary annotation, no source change.** Tag `sendGiftEmail` `@lint.effect externally_idempotent` (no `(by:)`). Rule behaviour: lattice trust granted, `missingIdempotencyKey` has nothing to check. Effect on round 3's diagnostic: it **disappears**, because Phase 2's lattice trusts the keyed tier implicitly.
- **(B) Minimal source modification.** Add an `idempotencyKey: String` parameter to `sendGiftEmail` (ignored in the body — this is trial scaffolding). Tag with `(by: idempotencyKey)`. Route the key at the call site. Tests the verifier.
- **(C) Synthetic injection.** Add a new file `Sources/PointFree/Webhooks/TrialPhase2Anti.swift` with one violation per new rule shape. Doesn't touch real code; validates defensive behaviour on realistic project layout.

Round 4 does **all three** as separate sub-runs (see Phase 4 below). Each answers a different question, and the source-modification concerns apply only to Run C.

## Scope commitment (unchanged from rounds 2–3, with one carve-out)

- **Measurement only.** No rule changes on the linter baseline (main stays at `2c1c702`). No doc changes on the linter side. No proposal updates during the round; a Phase-5 write-up integrates findings afterwards.
- **Source modifications to the target are allowed in Run C only.** The modification is limited to: adding an `idempotencyKey: String` parameter to one function, with the parameter not used in the body. Every such edit is noted in `trial-scope.md`. No refactoring, no implementation changes.
- **Throwaway branch, not pushed.** Same as rounds 2 and 3.
- **Parser-bug carve-out** (same as rounds 2 and 3). If Run A produces a non-zero diagnostic count on un-annotated source, that's a parser regression introduced by the Phase-2.1 grammar extension. Fix on a separate linter branch, not on the trial branch.

## Phases

Linter and fixtures are already built. Phases mirror the round-3 numbering.

### Phase 0 — Prep (≈0.5 day)

- On primary machine: verify `main @ 2c1c702` baseline green (expected: 1890 tests / 256 suites).
- In the pointfreeco clone: `git fetch origin && git checkout trial-annotation-local && git checkout -b trial-annotation-phase2-local`. Round-3's annotations are the starting state; round 4's edits build on them rather than re-do them.
- Write `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-4/trial-scope.md`. Must include: pinned linter SHA, pinned target SHA, the three-option explanation above, and an explicit list of every source-modification edit Run C will make.

**Acceptance:** green linter baseline; new pointfreeco branch forked from round 3's; scope note committed.

### Phase 4 Run A — parser cleanliness at Phase 2.1 (≈15 min)

On unmodified pointfreeco (revert round-3 annotations first; easier to reset to `06ebaa5` than to tease them out):

```
git checkout 06ebaa5  # detached — for the Run A scan only
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco \
  --categories idempotency
```

**Expected:** 0 diagnostics. Same as round 3's Run A but against the new linter. Confirms the `(by:)` grammar extension doesn't misread any pointfreeco doc-comment on 918 files.

**Carve-out:** non-zero → parser regression. Record, pivot to fixing on a separate linter branch, pause round 4.

### Phase 4 Run B — round-3 annotations replayed under Phase 2 (≈0.5 day)

Checkout `trial-annotation-phase2-local`. Three-line edit to `Sources/PointFree/Gifts/GiftEmail.swift`:

```diff
- /// @lint.effect non_idempotent
- /// Sends an email via Mailgun. Replaying on webhook redelivery sends a
- /// duplicate email to the gift recipient — that is the defining
- /// non-idempotent behaviour this tier exists to flag.
+ /// @lint.effect externally_idempotent
+ /// Sends an email via Mailgun. The call itself is non-idempotent today,
+ /// but would be keyed-idempotent if routed through a Mailgun deduplication
+ /// key. The annotation expresses the *intended* tier; the documentary
+ /// form (no `(by:)`) is used because the parameter is not present.
```

Keep the other round-3 annotations (`@lint.context replayable` on the three helpers) unchanged.

Run:
```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco \
  --categories idempotency
```

**Expected:** 0 diagnostics (down from round 3's 1). Phase 2's lattice trusts `externally_idempotent` callees from replayable contexts; the `handlePaymentIntent → sendGiftEmail` edge is no longer a violation in the Phase-2 framing. This is the headline round-4 finding — *round 3's diagnostic was a phase-appropriate artifact, not a bug caught*. Teams that adopt Phase 2 should expect some round-3-era diagnostics to disappear, correctly.

**If Run B produces a non-zero count:** either the lattice rule has a bug, or my analysis above is wrong. Record and triage before Run C.

### Phase 4 Run C — verifier on real code (≈0.5 day)

Minimal source modification: add `idempotencyKey: String` parameter to `sendGiftEmail`. Update the annotation to use `(by: idempotencyKey)`. Update the single call site (`handlePaymentIntent` → `sendGiftEmail(for: gift)`) to pass the key.

**Run C.1 — stable key.** Call site passes `gift.id.uuidString` (pointfreeco's `Gift.id` is a persistent `UUID`-backed DB primary key — stable across retries by DB semantics).

```
swift run … --categories idempotency
```

**Expected:** 0 diagnostics. The verifier sees `gift.id.uuidString` — a member-access chain on a function parameter, opaque to the rule — and stays silent by design. Happy-path confirmation.

**Run C.2 — unstable key.** Flip the call site to pass `UUID().uuidString` (obvious anti-pattern). Re-run.

**Expected:** 1 `missingIdempotencyKey` diagnostic on the `handlePaymentIntent` call site, with the Phase-2.1 suggestion prose mentioning "stable upstream identifier".

**Acceptance:** Run C.1 silent, Run C.2 exactly one diagnostic with correct line number and prose. Matches the rule doc at `SwiftProjectLint/Docs/rules/missing-idempotency-key.md`.

### Phase 4 Run D — anti-pattern injection (≈0.5 day)

New file `Sources/PointFree/Webhooks/TrialPhase2Anti.swift` on the same trial branch. Contains one intentional violation per Phase-2.1 rule shape:

1. `observational → externally_idempotent` edge
2. `externally_idempotent → non_idempotent` edge
3. `missingIdempotencyKey` with `UUID()` at keyed arg
4. `missingIdempotencyKey` with `UUID().uuidString` at keyed arg
5. `missingIdempotencyKey` with `Date.now` at keyed arg
6. `missingIdempotencyKey` with `arc4random()` at keyed arg

Plus two negative cases:

7. `externally_idempotent` without `(by:)` — rule stays silent even with `UUID()` at what would be the key
8. Local let-binding of `UUID()` passed as key — stays silent (documented limitation)

**Expected:** 6 diagnostics from cases 1–6, 0 from cases 7–8. Matches unit fixtures at corpus scale.

### Phase 5 — Write-up (≈0.5 day)

Three artefacts under `docs/phase2-round-4/`:

1. **`trial-findings.md`** — counts per run; the four-round delta table (rounds 1–3 Phase-1 vs round 4 Phase-2); the Run B "disappearing diagnostic" finding with its adoption-education framing; Run C.1/C.2 transcripts; Run D's six-row table of expected vs observed.
2. **`trial-retrospective.md`** — one page. Questions to answer: (a) did Phase 2.1's shipped design hold up on real production code? (b) what's the adoption-education takeaway from Run B? (c) what's the next unit of work — heuristic inference, the SwiftIdempotency macro package, or the round-3-retrospective-named "internal microservice" target round?
3. **Amendments to `docs/idempotency-macros-analysis.md` Open Issues section** — only if round 4 surfaces patterns rounds 1–3 didn't. The existing OI-1/2/3 open items are orthogonal to Phase 2.1 and should stay open. A new OI would only appear if a novel adoption hazard shows up.

**Acceptance:** user can answer "is Phase 2.1 ready for adoption, and what's the honest story for teams migrating from Phase-1 annotations?" with evidence from one continuation corpus and 6+ fixture-mirroring injections.

## Verification end-to-end

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout main
swift package clean && swift test    # 1890 / 256 green

# Run A: fresh checkout of pointfreeco's pinned SHA
cd /Users/joecursio/xcode_projects/pointfreeco
git checkout 06ebaa5
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 diagnostics

# Run B: switch to round-3 annotations + Run-B's one-line edit
git checkout trial-annotation-phase2-local
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 diagnostics (down from round 3's 1)

# Run C.1: sendGiftEmail has idempotencyKey param, call site passes gift.id.uuidString
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 diagnostics

# Run C.2: same setup, call site now passes UUID().uuidString
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 1 missingIdempotencyKey diagnostic

# Run D: TrialPhase2Anti.swift added
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 6 diagnostics from cases 1–6 (plus the Run C.2 carry-over = 7 total)
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint` @ `main` (SHA `2c1c702`) — linter baseline, no edits
- `/Users/joecursio/xcode_projects/pointfreeco` @ `trial-annotation-phase2-local` — target with round-3 annotations + round-4 edits, not pushed
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-4/` — new deliverables folder
- `/Users/joecursio/xcode_projects/pointfreeco/Sources/PointFree/Gifts/GiftEmail.swift` — Run B annotation change, Run C parameter addition
- `/Users/joecursio/xcode_projects/pointfreeco/Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift` — Run C call-site edits
- `/Users/joecursio/xcode_projects/pointfreeco/Sources/PointFree/Webhooks/TrialPhase2Anti.swift` — Run D, new file

## Fallback

None needed. Same target, same linter, no toolchain questions — the round-3 Phase-0 work (`GIT_LFS_SKIP_SMUDGE=1`, Swift 6.3 compatibility) validated these already. If the round-3 trial branch has drifted in unexpected ways, fresh-checkout to `06ebaa5` and re-apply round-3's annotations by hand takes ~15 minutes.

## Total estimated effort

Phase 0: 0.5 day • Run A: 15 min • Run B: 0.5 day • Run C: 0.5 day • Run D: 0.5 day • Phase 5: 0.5 day • **~2.5 days, budget 3 with slack.** Run B and Run C are the two runs most likely to surface surprises (Run B because of the "disappearing diagnostic" framing; Run C because real-code parameter-addition is the least-rehearsed kind of trial edit).

## What a clean round 4 unlocks

If round 4 confirms:
- Phase 2.1 parser clean at 918 files (Run A),
- Round 3's diagnostic disappears under Phase 2 as predicted (Run B),
- Verifier fires exactly on anti-patterns on real code (Run C.2),
- Lattice + generator detection fires on every injected case (Run D),

then Phase 2.1 is validated as ready for adoption on the same basis Phase 1 was: multiple-codebase parser cleanliness + intentional-violation detection with zero false positives. The next natural unit of work becomes:

1. **Heuristic inference** (roadmap Phase 2 proper) — deferred since round 1; round-4's clean result removes the "is Phase 2.1 stable?" precondition the round-1 retrospective set.
2. **`SwiftIdempotency` macro package** (roadmap Phase 5) — brand-new Swift package, new repo, macro-based test generation.
3. **Validation against an internal microservice** — the target the round-3 retrospective named for observational-tier stress testing, still unexercised.

Which comes next is a scope question for after round 4 lands. This plan does not pre-commit to any of them.
