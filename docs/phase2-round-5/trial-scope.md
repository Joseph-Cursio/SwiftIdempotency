# Round 5 Trial Scope

## Research question

Does the inference machinery shipped post-round-4 (four commits: `83c828c` + `b4c1a81` + `14a38df` + `cf128da`) deliver useful signal on un-annotated real code without producing enough false positives to teach users to disable the category?

Operationalised as three sub-questions:

1. **Round-3-reproduction:** can inference + a single `@lint.context replayable` annotation on `handlePaymentIntent` reproduce round 3's `handlePaymentIntent → sendGiftEmail` diagnostic that required four annotations?
2. **Noise rate:** what fraction of widened-context diagnostics on pointfreeco are "noise" (fires where a human would disagree and no reasonable annotation would silence them)?
3. **Cross-project stability:** does swift-aws-lambda-runtime stay clean under inference when no anchor annotation exists?

## Pinned artefacts

| Role | Repo / branch | SHA / tag | Local path |
|---|---|---|---|
| Linter baseline | `Joseph-Cursio/SwiftProjectLint` @ `main` | `9cc3bfe` | `/Users/joecursio/xcode_projects/SwiftProjectLint` |
| Primary target | `pointfreeco/pointfreeco` | `06ebaa5276485c5daf351a26144a7d5f26a84a17` | `/Users/joecursio/xcode_projects/pointfreeco` |
| Primary trial branch | `trial-inference-local` (forked from `06ebaa5`) | — | same repo |
| Secondary target | `swift-server/swift-aws-lambda-runtime` | `2.8.0` (= `553b5e3`) | `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` |

Secondary target is a shallow clone at the 2.8.0 release tag (HEAD == tag == `553b5e3`). Per plan: "cross-project sanity check — no trial branch, runs against the pinned tag directly."

## Scope commitment

- **Measurement only.** No rule changes on the linter baseline. No inference-whitelist edits. No proposal updates during the round; Phase 6 write-up integrates findings afterwards.
- **Zero or one annotations on pointfreeco** per Run, per the inference-validity research question. Run A uses zero. Run B uses exactly one (`@lint.context replayable` on `handlePaymentIntent`). Run D widens the context annotation to every webhook entry point — still *context-only*, no effect annotations anywhere.
- **Source modifications to pointfreeco allowed in Run C only.** Adds a single new file `Sources/PointFree/Webhooks/TrialInferenceAnti.swift`. No edits to existing source.
- **No modifications to swift-aws-lambda-runtime.** Run E is zero-annotation cleanliness only.
- **Throwaway branch, not pushed.** `trial-inference-local` is local-only, same policy as rounds 2-4's trial branches.
- **Parser/inference-bug carve-out.** If Run A (zero annotations) produces any diagnostic, that's either a rule firing without an anchor or inference over-firing without a retry context. Pause the round, log the finding, triage on a separate linter branch. Same template as round 4's parser-regression carve-out.
- **FP audit is in scope.** Each Run D diagnostic gets a one-line verdict in `trial-findings.md`: *correct catch* / *defensible* / *noise*. Audit cap 30 diagnostics.

## Enumerated source-level edits this round will make

pointfreeco `trial-inference-local`:

1. **Run B:** add one doc-comment line to `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift` — `/// @lint.context replayable` above `handlePaymentIntent`.
2. **Run C:** create new file `Sources/PointFree/Webhooks/TrialInferenceAnti.swift` (9 cases, listed below).
3. **Run D:** add `/// @lint.context replayable` above every remaining webhook entry point in `Sources/PointFree/Webhooks/`. Per-file list finalised during Phase 0 file survey; appended here as edits are made.

swift-aws-lambda-runtime: **no edits** in the base Run E. Optional light-touch Run E' may add one `/// @lint.context replayable` to a Lambda handler's `handle(...)` method; explicitly flagged in `trial-findings.md` as an optional extension, not a scope creep.

## Run C anti-injection cases

Positive cases (expect one diagnostic each):

1. Bare-name downward, non-idempotent: `@lint.context replayable` function calls un-annotated `publish(...)`. Heuristic-credited.
2. Bare-name downward, idempotent caller constraint: `@lint.effect idempotent` function calls un-annotated `insert(...)`. `idempotencyViolation`, heuristic-credited.
3. Two-signal observational, contamination: `@lint.effect observational` function calls un-annotated `queue.enqueue(...)`. Observational → inferred-non-idempotent.
4. One-hop upward: `@lint.context replayable` caller → un-annotated `foo()` whose body calls a bare-name sink. Upward-inferred, `depth: 1`.
5. Multi-hop upward: three-deep un-annotated chain with a non-idempotent leaf, called from `@lint.context replayable`. Upward-inferred, `depth: 3`.

Negative cases (expect silence):

6. Two-signal observational, clean: `@lint.effect observational` function calls `someOtherLogger.info(...)`. Both observational.
7. Ambiguous bare name `save`: un-annotated `store.save(...)` from a retry context. Deliberately out-of-whitelist.
8. Bare name, wrong receiver for observational: un-annotated `customThing.debug(...)` from a retry context. Fails the two-signal gate.
9. Escaping-closure boundary: non-idempotent call inside `Task { }` within a `@lint.context replayable` function. Escaping-closure policy applies.

Per-case expected outcomes will be tabulated in `trial-findings.md` alongside observed counts and depth values.

## Acceptance summary

- Run A: 0 diagnostics. Non-zero invokes the parser/inference-bug carve-out.
- Run B: 1 inference-credited diagnostic on the `handlePaymentIntent → sendGiftEmail` edge. 0 or >1 is a headline finding either way.
- Run C: exactly 5 new diagnostics (cases 1, 2, 3, 4, 5); 0 from cases 6, 7, 8, 9. Each Run-C positive's provenance prose matches the expected inference mode.
- Run D: some N diagnostics, classified; noise fraction reported. ≤ 10% → adoption-ready. > 25% → next work is whitelist pruning.
- Run E: 0 diagnostics on swift-aws-lambda-runtime base run. Diagnostics here are a critical finding.

## Fallback

- pointfreeco stash preserved under name `round5-preserve-r4-leftovers-<timestamp>` — contains the uncommitted round-4 leftover edits to `GiftEmail.swift` and `PaymentIntentsWebhook.swift`. Kept in case the round aborts and needs to revert cleanly.
- swift-aws-lambda-runtime is a shallow clone at 2.8.0. If the linter needs commit history for any reason (it shouldn't), re-clone with full depth before Run E.
- If Run B's inference chain doesn't reach `sendGiftEmail`'s mailgun call, the finding is itself the Run B result. No plan pivot required within the round — the gap frames the next plan's priorities.

## Timeline

- Phase 0 — Prep: baseline linter test pass green; pointfreeco at detached `06ebaa5`; lambda-runtime pinned at `2.8.0`. Current state.
- Runs A-E: linter invocations + source edits per the plan document.
- Phase 6: `docs/phase2-round-5/{trial-findings.md, trial-retrospective.md}`.
