# Round 4 Trial Scope Commitment

Fourth measurement round. First to validate **Phase 2** features on a real codebase — every prior round exercised only Phase 1. Companion to [`../phase1/trial-scope.md`](../phase1/trial-scope.md), [`../phase1-round-2/trial-scope.md`](../phase1-round-2/trial-scope.md), and [`../phase1-round-3/trial-scope.md`](../phase1-round-3/trial-scope.md).

## Pinned linter baseline

- **Repo:** `Joseph-Cursio/SwiftProjectLint`
- **Branch:** `main`
- **SHA:** `2c1c702` (post-`missingIdempotencyKey`)
- **No new linter branch.** Round 4 runs against main's tip. Measurement-only; zero code changes on the linter side.
- **Baseline:** 1890 tests across 256 suites, verified green at Phase 0.

## Pinned target

- **Repo:** `pointfreeco/pointfreeco`
- **SHA:** `06ebaa5276485c5daf351a26144a7d5f26a84a17` (unchanged from round 3)
- **Swift-tools-version:** 6.3
- **Local clone:** `/Users/joecursio/xcode_projects/pointfreeco` (LFS-skipped)

## Pinned trial branch

- **Branch:** `trial-annotation-phase2-local`
- **Forked from:** `trial-annotation-local` (round 3's leftover branch; carries the round-3 annotations on `PaymentIntentsWebhook.swift` and `GiftEmail.swift`)
- **Not pushed.** Throwaway, same policy as rounds 2 and 3.

## Research questions

Three sub-questions, one per Phase-2.1 claim:

1. **Parser scaling.** Does the new `(by: paramName)` grammar stay silent on 918 un-annotated pointfreeco files? Confirms the Phase-2.1 grammar extension doesn't regress the Phase-1 parser cleanliness result from round 3.
2. **Round-3 diagnostic under Phase 2.** Round 3's `handlePaymentIntent → sendGiftEmail` edge fired because Phase 1 had only `non_idempotent` as the weakest tier to annotate `sendGiftEmail` with. Phase 2 has a third position (`externally_idempotent`) that the annotation *should* have used. Re-running the annotation campaign with Phase-2 tier choices tells us whether round 3's diagnostic was a real bug-catch or a phase-appropriate artifact.
3. **Verifier on real code.** Does `missingIdempotencyKey` fire correctly on real production Swift when a realistic annotation campaign adds the key-routing parameter to `sendGiftEmail`? This is the closest the trial record comes to a production adoption story.

## Source modifications: explicit list

Unlike rounds 2 and 3, this round cannot be done with annotations alone. `sendGiftEmail(for gift: Gift)` has no parameter capable of carrying an idempotency key, so the `(by: paramName)` grammar has nothing to name. The scope commitment for round 4 allows three specific source edits to the target, on the throwaway branch only:

1. **`Sources/PointFree/Gifts/GiftEmail.swift`** — change the effect annotation from `@lint.effect non_idempotent` (round 3's Phase-1 choice) to `@lint.effect externally_idempotent` (Run B) or `@lint.effect externally_idempotent(by: idempotencyKey)` (Runs C.1 / C.2). Later runs additionally add an `idempotencyKey: String` parameter to the function signature. The parameter is not consumed in the body — this is trial scaffolding, not a real Mailgun integration.
2. **`Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift`** — update the single call site `sendGiftEmail(for: gift)` to pass the key: `sendGiftEmail(idempotencyKey: ..., for: gift)`. Two variants (C.1 stable, C.2 unstable).
3. **`Sources/PointFree/Webhooks/TrialPhase2Anti.swift`** — new file (Run D) with six intentional violations and two documented-limitation negatives. No modification to existing pointfreeco code.

Every source edit is documented in the corresponding run's section of `trial-findings.md` with the full diff. Nothing is pushed upstream.

## Round-4-specific guardrails

Same policies as rounds 2 and 3:

- **Measurement only.** No rule changes on `main`. No proposal changes during the round; a Phase-5 write-up integrates findings afterwards.
- **Throwaway branch, not pushed.** Trial branch stays in the local clone.
- **Parser-bug carve-out.** If Run A produces non-zero diagnostics on unmodified pointfreeco, that's a parser regression introduced by the Phase-2.1 grammar extension. Fix lands on a separate linter branch; round 4 pauses.

New guardrail: **source modifications are bounded by the explicit list above.** No refactoring, no implementation changes, no edits beyond adding annotations, the single `idempotencyKey` parameter, the two call-site updates, and the Run-D synthetic file. If a run wants a fifth edit, it stops and triages.

## Research questions rounds 1–3 cannot answer

- **Does Phase 2's lattice correctly absorb round-3's diagnostic?** This is structurally invisible until the `externally_idempotent` tier exists.
- **Does the `(by:)` grammar work on real production Swift?** All prior grammar tests were synthetic fixtures.
- **Does `missingIdempotencyKey` produce the right diagnostic prose on a real callee with realistic argument expressions?** The rule doc shows the expected form; this is the corpus-scale confirmation.

## Deliverables

1. [`trial-findings.md`](trial-findings.md) — counts per run, four-round delta table, the "disappearing diagnostic" finding with its adoption-education framing, Run C and Run D transcripts.
2. [`trial-retrospective.md`](trial-retrospective.md) — one page. Answers: (a) did Phase 2.1's shipped design hold up on real production code? (b) what's the adoption-education takeaway from Run B? (c) what comes next?
3. Amendments to [`../idempotency-macros-analysis.md`](../idempotency-macros-analysis.md) Open Issues — only if round 4 surfaces patterns rounds 1–3 didn't. Existing OI-1/2/3 are orthogonal to Phase 2.1 and should stay open.

## Cost budget

~2.5 days. Run B and Run C are the two runs most likely to surface surprises: Run B because of the "disappearing diagnostic" framing is novel, and Run C because real-code parameter-addition is the least-rehearsed kind of trial edit.

## Known gaps this round will not address

- **Heuristic inference** (roadmap Phase 2 proper) — deferred since round 1. Round 4 does not touch it.
- **`SwiftIdempotency` macro package** — brand-new Swift package outside the linter. Round 4 does not touch it.
- **Observational-tier stress at `swift-log` volume** — OI-5's residual gap. The round-4 corpus is pointfreeco, which does not have dense `swift-log` usage. Unchanged.
