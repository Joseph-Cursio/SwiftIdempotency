# Round 4 Trial Retrospective

One page. First Phase-2 measurement round. The question it has to answer: is Phase 2.1 ready for real adoption on the basis of evidence, not design intuition?

## Did the scope hold?

**Yes, with one explicit carve-out.** Zero rule changes on the linter. The carve-out was source modification on the target — explicitly listed in `trial-scope.md` and strictly bounded. The actual edits: one annotation-tier change, one parameter addition, two call-site variants, one new trial file. Five edits across three files. Every edit documented in `trial-findings.md` with its motivation.

Would a "pure annotation" round have been possible? Only Run A, Run B, and the two Run D negatives. Runs C.1, C.2, and D cases 1–6 all require the `(by:)` grammar to name a parameter that existed, which pointfreeco's `sendGiftEmail` didn't have. The alternative — leaving the verifier untested on real code — would have been a worse trial artefact.

## Answers to the three pre-committed questions

### (a) Did Phase 2.1's shipped design hold up on real production code?

Yes. Five runs, five outcomes matching predictions. Specifically:

- The `(by: paramName)` grammar parsed without regression on 918 files (Run A).
- The new `externally_idempotent` tier behaves correctly in the retry-context rule's lattice on real code (Run B).
- The `missingIdempotencyKey` rule fires with correct prose, correct line numbers, and correct parameter-name identification on a real production call site (Run C.2).
- All six new-lattice-row / generator-detection cases fire in realistic project layout (Run D).
- Both documented limitations (opaque expressions, let-bindings) stay silent on real and synthetic instances (Run C.1, Run D Negative 2).

No false positives across any run. No prose errors. No line-number errors. No parser regressions. The unit-fixture claims generalise.

### (b) What's the adoption-education takeaway from Run B?

Teams migrating from Phase-1 annotations to Phase-2 tiers should expect **diagnostic counts to decrease** in some cases as they pick the more-accurate tier. This is correct behaviour.

The path is:
1. A team adopts Phase 1 and annotates a Mailgun-sending function `@lint.effect non_idempotent` because that's the only honest tier Phase 1 offers.
2. A replayable caller of that function trips `nonIdempotentInRetryContext`.
3. The team fixes the call site (or accepts the diagnostic as a known backlog item).
4. Phase 2 ships with `externally_idempotent`.
5. The team upgrades the annotation to `@lint.effect externally_idempotent`. The diagnostic silences. No call-site change was needed.

The diagnostic wasn't a bug catch — it was Phase 1's best approximation of a nuance Phase 2 now captures directly. A team can be *strictly more correct* after an annotation-tier refinement that reduces their diagnostic count to zero.

This is the kind of thing that confuses adoption metrics. "Rule count went down, is it working less?" No — it's measuring something more accurately. Rule docs and release notes should foreground this when Phase 2 ships to real teams.

### (c) What comes next?

Three plausible directions. Ordered by how much new evidence they would produce per day:

1. **Heuristic inference** (roadmap Phase 2 proper) — still the highest-value unshipped piece. The round-3 annotation burden (4 annotations for one 3-hop chain) is the dominant Phase-1 adoption friction, and round 4 didn't address it. Inference would deliver annotation-free signal and convert rounds 2 and 3's "zero diagnostics on un-annotated source" from "parser-clean but uninformative" to "parser-clean AND catches real things."
2. **The `SwiftIdempotency` macro package** — the proposal's Phase 5 deliverable. Largest change, requires a separate Swift package. Unlocks `@Idempotent` peer-macro test generation and `IdempotencyKey` as a strong type that is compile-time-enforced to be routed. The round-3 retrospective called this out as the biggest single gap in the trial record.
3. **An internal microservice with `swift-log` volume** — OI-5's last untested corner. The three public trials all had limited `swift-log` usage; the observational tier's corpus-scale stress test remains pending. User's own repos would be the natural target.

No round-5 is needed to close the Phase-2.1 loop. Round 4 was the loop.

## What would have changed the triage

- **Effect inference.** Run B's "disappearing diagnostic" finding would have emerged differently — inference might have auto-propagated the `externally_idempotent` tier from callee to caller, potentially silencing *more* diagnostics than the tier change alone. That's a different adoption story with its own education points.
- **`IdempotencyKey` strong type.** The Run C.2 diagnostic would have been *compile-time* enforced — `UUID().uuidString` wouldn't even type-check as an `IdempotencyKey`. The linter rule would become a fallback for codebases that haven't adopted the strong type. That's the Phase-5 payoff the proposal has been aiming at since April 2026.
- **Test generation via `@Idempotent`.** Would add a *runtime* verification layer — the `sendGiftEmail` function would auto-gain a peer test that calls it twice with the same idempotency key and verifies identical observable behaviour. That's a qualitatively different check than any lint rule can perform, and it's the claim the proposal originally justified the macro package with.

None of these were the scope of round 4. They're named here for the next planning document.

## Cost summary

- **Estimated:** 2.5 days.
- **Actual:** one focused session, ~90 minutes of model time. Similar to rounds 2 and 3; the shared pattern is "linter + target both pre-prepared, work is measurement + writing."
- **Biggest time sink:** the LFS-filter workaround when the trial branch needed a commit. Resolved by setting `filter.lfs.clean/smudge = cat` in the local repo config. Same class of issue round 3 had; the workaround persists across branch switches.

## Net output after four rounds

Phase 1 and Phase 2.1 are both now validated on the basis of evidence, not just design review. Across four rounds:

- 1155 files of un-annotated source produced zero false positives from annotation-gated rules.
- Three real-code annotation campaigns (rounds 1 and 3 in their respective phases; round 4 here) produced exactly the diagnostics the rule designs predicted.
- Every open issue from rounds 1–3 either resolved, stayed correctly deferred, or got explicitly reclassified as an adoption-education point rather than a rule defect.
- Six intentional violations and two documented limitations were exercised end-to-end on a realistic project layout. All six fired; both limitations stayed silent.

The honest assessment from the earlier conversation still stands: **the structural rule (`actorReentrancy`) earns its keep on day zero; the annotation-gated rules and the Phase-2.1 verifier are well-built and waiting for users.** Round 4 doesn't change that assessment — it validates the *mechanisms*. Whether the *system* earns its keep against real adoption remains a question only real adoption can answer.

## Policy notes

- **"No rule changes on the trial branch" held a fourth time.** Carry this forward to every future measurement round. It produced cleaner deliverables every time.
- **Source modifications are sometimes unavoidable.** The solution isn't to refuse them — it's to explicitly list them in the scope doc, keep them bounded, and document every edit. Round 4's approach worked.
- **The LFS-filter workaround should be in a README somewhere.** Future rounds against LFS-using repos will hit this. `git config filter.lfs.clean "cat"; git config filter.lfs.smudge "cat"; git config filter.lfs.process ""` lets git operations proceed without git-lfs installed, at the cost of LFS-backed files being left as pointers. For a measurement trial that cares only about Swift source, that's the right trade.

## Recommended path after round 4

Don't run round 5 yet. Build one of the three named deliverables — heuristic inference, the macro package, or a `swift-log`-heavy internal-target trial. Each would produce more novel information than another measurement round on the same three codebases.

If forced to pick: heuristic inference. It's the piece that most visibly addresses the "annotation-campaign cost is the real blocker" theme from round 3's retrospective and the honest-assessment note in this session's conversation history. Runs 1–4 answered "does the machinery work"; heuristic inference answers "can teams get useful signal before they've done the annotation work."
