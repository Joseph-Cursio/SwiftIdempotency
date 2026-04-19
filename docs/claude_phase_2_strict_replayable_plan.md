# Implementation Plan: `strict_replayable` Context Tier

Next slice after the round-8 macros-package redesign closed Finding 4. Implements the "flag unless proven idempotent" opt-in mode that has been queued since round 7. Linter-side work with a small proposal-side documentation follow-on. Companion to [`claude_phase_5_peer_macro_redesign_plan.md`](claude_phase_5_peer_macro_redesign_plan.md) and the [round-8 retrospective](phase5-round-8/trial-retrospective.md) that ordered this as direction 2.

## Why this is the right next work

Round 6 produced a clean precision profile for `@lint.context replayable`: the rule catches declared/inferred `non_idempotent` callees and stays silent on unannotated/unknown callees. That silence is a precision win — it means "don't alarm on code you haven't classified yet." It's also the ceiling on the rule's catch rate: code that slips through un-annotated is assumed safe until someone proves otherwise.

`strict_replayable` flips that default for declarations that opt in. Every callee in a strict_replayable body must be *provably* idempotent/observational (declared or upward-inferred from a clean sub-graph). Unannotated callees become errors. The adoption story is: "annotate a few critical handlers `strict_replayable` for maximum protection, leave the rest `replayable` for low-noise coverage."

The round-8 redesign matters specifically because it made this slice tractable:

- Before round 8, `@Idempotent` was a marker-only attribute whose value was linter-readable only. Annotating a function took the same amount of work as writing `/// @lint.effect idempotent`.
- After round 8, `@Idempotent` still works as a marker, and `@IdempotencyTests` at the `@Suite` type gives the annotator a free test that double-invokes the function — if they were going to write that test anyway, `@Idempotent` pays for itself.

That tilts the cost of annotating for strict-mode adoption from "pure tax" to "incidental benefit," which is the adoption inflection the round-7 retrospective predicted.

## Scope of this plan

**In scope:**

- New `ContextEffect.strictReplayable` case in `EffectAnnotationParser.ContextEffect`, with parsing for `/// @lint.context strict_replayable`.
- New rule `unannotatedInStrictReplayableContext`, with its own visitor (`UnannotatedInStrictReplayableContextVisitor`) and rule identifier. Lives alongside `nonIdempotentInRetryContext`; precision on `replayable` callers is unchanged.
- Lattice semantics: a callee in a `strict_replayable` body passes silently only if its effect is declared or upward-inferred as `idempotent`, `observational`, or `externallyIdempotent` (any key-parameter). Everything else — `non_idempotent` (fires via the existing rule), heuristic-inferred, or completely unknown — is an error from the new rule.
- Unit tests covering the rule's behaviour on each effect tier, escaping closures, cross-file resolution, `.unsafe` suppression (the existing escape hatch).
- Round-9 validation against `swift-aws-lambda-runtime` — flip one handler's `@context replayable` → `strict_replayable` and measure the resulting diagnostic count against the round-6 baseline. The annotation campaign (adding `@Idempotent`/`@Observational` to silence the non-error callees) is the measurement target.
- Proposal-side documentation in `docs/idempotency-macros-analysis.md`: the `@context replayable` section gets a subsection for `strict_replayable` with the "opt-in strictness" framing.

**Out of scope with reasons:**

- **Global strict-mode flag** (`.swift-idempotency.yml`'s `default_context_mode: strict_replayable`). Might make sense for greenfield repos, but as a first slice the per-declaration opt-in lets adopters scope strictness to specific handlers without codebase-wide commitment. Global opt-in is a separate slice if/when real adopters ask for it.
- **`strict_retry_safe`**. `retry_safe` and `replayable` have always shared implementation (the retro-docs call out the distinction as "documentary"). Pre-adopter, adding both strict variants doubles the surface without adding signal. Ship `strict_replayable` first; if adopters ask for `strict_retry_safe` we clone the implementation.
- **New diagnostic suggestion paths.** The existing "annotate with `/// @lint.effect <tier>`" suggestion from `nonIdempotentInRetryContext` is the right shape for this rule too — the new rule just points at a different set of acceptable tiers. No need for a new suggestion template.
- **Cross-corpus validation on a second codebase.** Round 9 validates on the `swift-aws-lambda-runtime` corpus. A second corpus (Vapor, internal microservice) is the round-7 retrospective's direction 3 and stays there; unblocking it from "waits on macros" to "waits on real adopter" is a side effect of this slice, not a deliverable.
- **Escape-hatch refinement.** The existing `// swift-idempotency:disable-next-line <rule>` and `/// @lint.unsafe reason: "..."` mechanisms already work with per-rule suppression. No new suppression grammar needed; tests verify both suppress the new rule.

## Design

### Parser extension

`EffectAnnotationParser.swift`:

```swift
public enum ContextEffect: Sendable, Equatable {
    case replayable
    case retrySafe
    case once
    case strictReplayable      // new
}

// extractContext switch adds:
case "strict_replayable":
    return .strictReplayable
```

Two lines in `ContextEffect`, two lines in the switch. The enum's existing `Sendable, Equatable` conformances carry through.

**Lattice ordering.** `strictReplayable` and `replayable` share identical callee-effect constraints for the *positive* case (`non_idempotent` fires the existing rule). They differ only on the *absence* of evidence — `replayable` is silent, `strictReplayable` fires the new rule. Nothing in the existing lattice table changes; the new rule reads the existing lattice but applies a stricter acceptance predicate.

### New rule: `unannotatedInStrictReplayableContext`

Rule identifier: `unannotatedInStrictReplayableContext` (added to `RuleIdentifier.swift`).

**Firing condition.** Inside a function declared `@lint.context strict_replayable`, a callee fires the rule iff **none** of these hold:

- The callee is declared `@lint.effect idempotent`, `observational`, or `externally_idempotent` (any key parameter — absence of `by:` still grants lattice trust per the round-7 design).
- The callee has upward-inferred effect `idempotent` or `observational` via `symbolTable.upwardInference(for:)`.
- The callee is already flagged by `nonIdempotentInRetryContext` (avoid double-firing on the same call).

Callees that *are* flagged by `nonIdempotentInRetryContext` — declared/upward-inferred `non_idempotent`, or heuristically inferred `non_idempotent` — continue to produce that rule's diagnostic. The new rule only fires when existing coverage misses: callees whose effect can't be determined at all.

**Diagnostic shape.**

> Unannotated call in strict_replayable context: 'handleOrderCreated' is declared `@lint.context strict_replayable` but calls 'writeAuditLog', whose effect is not declared and cannot be inferred from its body. Annotate 'writeAuditLog' with `/// @lint.effect <tier>` or `@Idempotent`/`@Observational`/`@ExternallyIdempotent(by:)` to unblock.

**Suggestion path.**

> Add `/// @lint.effect idempotent` if re-invocation produces no additional observable effects; `observational` for logging/metrics/tracing primitives; `externally_idempotent(by: <param>)` for calls that rely on a caller-supplied deduplication key.

### Visitor

New visitor `UnannotatedInStrictReplayableContextVisitor` in `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/Visitors/`. Shape mirrors `NonIdempotentInRetryContextVisitor`:

- `BasePatternVisitor, CrossFilePatternVisitorProtocol`
- Walks each function declaration in the file; `parseContext(declaration:)` identifies strict-replayable bodies; `analyzeBody` recursively inspects all `FunctionCallExprSyntax` calls within.
- Reuses the existing `AnalysisSite`, `isEscapingClosure`, `directCalleeName`, and `escapingCalleeNames` helpers. The round-5/6 escaping-closure policy applies identically — calls inside `Task { }`, `detached { }`, etc. are analysed as their own sub-context, not as part of the enclosing strict-replayable body.
- `analyzeCall` dispatches:
  - If the callee has a declared `non_idempotent` effect or heuristic `non_idempotent` inference, return — `nonIdempotentInRetryContext` handles it.
  - If the callee has declared or upward-inferred `idempotent`/`observational`/`externally_idempotent`, return — passes.
  - Otherwise, fire the new rule's diagnostic.

Estimated size: ~220 lines, roughly matching `NonIdempotentInRetryContextVisitor`'s current 254-line footprint. Most of the complexity is the escaping-closure policy duplication, which is why round 6's lesson about "extract a shared retry-context-body walker" becomes attractive here. **Do not extract during this slice** — two similar visitors is better than a premature abstraction, especially when the visitors might diverge (e.g., strict-mode might grow its own lattice rules over time). Extraction is a separate refactor once three rules share the shape.

### Registration

Pattern registrar update in `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/PatternRegistrars/`:

- Either extend `NonIdempotentInRetryContext.swift` to register both rules (they share analysis traversal but produce independent diagnostics), or add a new `UnannotatedInStrictReplayableContext.swift` registrar. The choice depends on whether the existing file's registrar is generic over the rule — I lean toward a new file for symmetry with how `idempotencyViolation` and `nonIdempotentInRetryContext` already live in separate registrars.

### Macros-package interaction

No macros-package edits required. `@Idempotent`, `@Observational`, `@ExternallyIdempotent(by:)` attributes already read by `EffectAnnotationParser.effectFromAttributes` satisfy the rule's "callee declares an idempotent effect" condition. The round-8 `@IdempotencyTests` attribute is already in the recognised-but-silent set (committed in SwiftProjectLint@ac8bbc5) and is irrelevant to this rule.

## Phases

Five-ish days. Core linter work lands in 2-3 days; validation round takes the rest.

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git pull origin main && swift package clean && swift test`. Expect green; baseline is the ac8bbc5-plus-everything test count (was 2099/270 after the round-8 linter line-update).
- Create a feature branch `phase-2-strict-replayable` off `main`. Not pushed.
- Re-fetch `swift-aws-lambda-runtime` full depth if still shallow: `cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime && git fetch --unshallow origin`.
- Skim round 6's per-diagnostic FP audit (`docs/phase2-round-6/trial-findings.md`) to catalogue the handlers annotated in that round and which example files they live in. Identifies the candidate for promotion to strict_replayable in Phase 4.
- Write `docs/phase2-round-9/trial-scope.md` with the pinned target, the candidate handler, the three research questions (below), and the acceptance thresholds.

**Acceptance:** linter baseline green; feature branch created; scope doc committed.

### Phase 1 — Parser + effect recognition (≈0.5 day)

- Add `strictReplayable` to `ContextEffect`. Update the enum's doc comment to explain the opt-in strictness framing.
- Extend `extractContext`'s switch to recognise `strict_replayable`.
- Unit tests in `Tests/CoreTests/Idempotency/` (new file `StrictReplayableContextParsingTests.swift` or extend the existing context-parsing tests — whichever is cleaner). Coverage: parses successfully; doesn't collide with `replayable` when both aliases-ish appear in trivia; unknown tokens still fall through to `nil`.

**Acceptance:** parser recognises the new context; existing context tests still green; `swift test` adds ~5 parsing tests.

### Phase 2 — Visitor + diagnostic (≈1 day)

- New visitor file (see Design). Mirrors `NonIdempotentInRetryContextVisitor`'s structure; reuses shared helpers.
- New rule identifier `unannotatedInStrictReplayableContext` in `RuleIdentifier.swift`, added to the idempotency-category switch alongside existing cases.
- New pattern registrar; integration with `CrossFileAnalysisEngine`.
- Compile + smoke-test inside the linter's own test corpus.

**Acceptance:** visitor builds clean; no regressions on the existing 2099-test baseline; smoke-tested on the `swift-aws-lambda-runtime` clone (zero diagnostics expected since no handler is annotated `strict_replayable` yet).

### Phase 3 — Unit tests (≈1 day)

Fixture-based tests in `Tests/CoreTests/Idempotency/UnannotatedInStrictReplayableContextVisitorTests.swift`. Each case is a small source string fed to `CrossFileAnalysisEngine` and asserted against diagnostic counts + messages.

Positive cases (rule fires):
- `strict_replayable` caller + completely unannotated callee
- `strict_replayable` caller + callee with only a heuristic non-idempotent inference (should still fire the *existing* rule, not the new one — verifies the new rule defers)
- `strict_replayable` caller + chain of unannotated callees (upward inference yields no positive classification)
- `strict_replayable` caller + `@Idempotent`-annotated callee nested inside an escaping closure (rule fires on the enclosing strict context's direct callee, not through the closure boundary)

Negative cases (rule stays silent):
- `replayable` caller + unannotated callee (the round-6 precision profile)
- `strict_replayable` caller + `@Idempotent` / `@Observational` / `@ExternallyIdempotent(by:)` callees
- `strict_replayable` caller + upward-inferred `idempotent` callee (transitively proven from sub-graph)
- `strict_replayable` caller + `// swift-idempotency:disable-next-line unannotatedInStrictReplayableContext`
- `strict_replayable` caller + `/// @lint.unsafe reason: "..."` on the callee

Cross-file cases (rule uses the symbol table correctly):
- Caller in `A.swift`, callee declared in `B.swift` with `@lint.effect idempotent` → silent
- Caller in `A.swift`, callee declared in `B.swift` without annotation → fires

Target: ~25-30 test cases, each ≤20 lines. Follows the existing `NonIdempotentInRetryContextVisitorTests` style (164 lines, ~15 cases).

**Acceptance:** new test file green; new rule's test coverage matches the existing rule's shape; no regressions elsewhere.

### Phase 4 — Round-9 validation on `swift-aws-lambda-runtime` (≈1 day)

New target branch `trial-strict-replayable-round-9` on the Lambda clone, forked from `2.8.0`. Promote one handler's context from `replayable` to `strict_replayable`. Candidate: the handler with the most varied call graph from round 6 (MultiSourceAPI or Streaming+APIGateway — round 6's audit identified the catch distribution).

**Run A — bare promotion.** Change `/// @lint.context replayable` → `/// @lint.context strict_replayable` on the target handler. No other edits. Scan. Count diagnostics.

Expected shape:
- Every call-graph edge reachable from the promoted handler that was "unknown" under round-6 replayable now fires.
- Count is bounded by the call graph's depth-1 edge set from that handler. Round 6 had 0 diagnostics on this handler's replayable run; the Run-A count is the "annotation gap" — calls that need a tier assignment.

**Run B — annotation campaign.** Starting from Run A's diagnostics, add `@Idempotent`/`@Observational`/`@ExternallyIdempotent(by:)` or `/// @lint.effect <tier>` to each flagged callee based on the honest classification. Log each annotation in a `trial-findings.md` table: flagged symbol, chosen tier, judgment rationale.

Expected shape: Run B count decreases monotonically. If it doesn't (i.e., annotating callee X fires a new diagnostic on sub-callee Y because Y is also unannotated), the chain-depth effect is measured and reported.

**Run C — steady state.** After the campaign plateaus, re-scan. Count remaining diagnostics.

Success thresholds:
- Run A count: any non-zero count is fine — that's what the rule is measuring.
- Run B: each diagnostic's annotation is a defensible judgment, documented per-row.
- Run C: 0 diagnostics means the handler's call graph is fully classified for strict-mode. Non-zero means either an honest call-graph gap the user needs to address (e.g., a stdlib function not whitelisted) or a rule imprecision (a new FP class).
- **Adoption effort headline number:** minutes per annotation × annotations per handler. Round-6 pointfreeco baseline was roughly "1-2 minutes per annotation" on the handful they did; this round measures it on strict-mode at a different handler.

### Phase 5 — Writeup + proposal update (≈0.5 day)

Under `docs/phase2-round-9/`:

1. **`trial-findings.md`** — per-run counts; the Run B annotation table; the Run C steady-state; cross-round comparison (round 6 replayable vs round 9 strict on the same handler).
2. **`trial-retrospective.md`** — one page. Four pre-committed questions: (a) was the effort-per-handler reasonable for an adopter-facing feature? (b) what new FP classes (if any) did strict mode surface? (c) is `strict_replayable` adoption-ready or does it need another slice first? (d) what's the next unit of work — Vapor corpus, global strict mode, or `strict_retry_safe`?
3. **Amendments to `docs/idempotency-macros-analysis.md`** — add a `strict_replayable` sub-section under `@context replayable` with the opt-in strictness framing. The proposal's "formalized effect lattice" section gets one row added for strict mode's acceptance predicate.

**Acceptance:** user can answer "what does strict_replayable cost per handler, and what does it catch that replayable doesn't?" with evidence from a single real-handler campaign.

## Verification end-to-end

```
# Linter: parser + visitor + tests green on branch
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout phase-2-strict-replayable
swift package clean && swift test
# Expect: 2099 + ~30 new tests across 270 + 1-2 new suites = ~2129/272 green

# Lambda corpus: promote one handler and run each scan
cd /Users/joecursio/xcode_projects/swift-aws-lambda-runtime
git checkout -b trial-strict-replayable-round-9 2.8.0

# Run A — bare promotion
# edit one handler to `@lint.context strict_replayable`
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: N new diagnostics, each pointing at an unannotated callee

# Run B — campaign
# add @Idempotent / @Observational / @ExternallyIdempotent / doc-comment
# annotations per diagnostic
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: count decreases; every diagnostic rationalised in trial-findings.md

# Run C — steady state
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect: 0 remaining, OR documented gaps

# Unit tests re-green
cd /Users/joecursio/xcode_projects/SwiftProjectLint
swift test
# Expect: still green at the phase-2-strict-replayable tip
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/EffectAnnotationParser.swift` — `ContextEffect` + `extractContext`
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift` — new `unannotatedInStrictReplayableContext` case
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/Visitors/UnannotatedInStrictReplayableContextVisitor.swift` — new visitor
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/PatternRegistrars/UnannotatedInStrictReplayableContext.swift` — new registrar
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/UnannotatedInStrictReplayableContextVisitorTests.swift` — new tests
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/StrictReplayableContextParsingTests.swift` — new parser tests (or extension to existing context-parsing tests)
- `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime/` @ `trial-strict-replayable-round-9` — target, not pushed
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-9/` — new deliverables folder
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/idempotency-macros-analysis.md` — proposal `@context replayable` section and lattice table

## Fallback

- **Run A surfaces no diagnostics** on the candidate handler. Means the handler's call graph is already fully classified — either the chosen handler is too narrow or round 6's replayable run already implicitly proved everything. Move the promotion to a different handler (the one with the largest unique call-graph surface) and re-run. If *no* handler in the corpus produces a non-zero Run A, strict mode's value is below the noise floor for this corpus and the right next step is a second corpus before declaring the mechanism useful.
- **Run B annotation campaign produces a new FP class** (e.g., a stdlib pattern the heuristic whitelist missed, a macro-generated callee that doesn't carry an effect attribute). Catalogue the shape; file a round-9 finding. If the FP class is bounded, ship `strict_replayable` with the class documented as a known silence-via-annotation. If the class is unbounded (fires on arbitrary code), pause adoption and treat it as a round-9-follow-up slice.
- **Rule interacts badly with existing `nonIdempotentInRetryContext`** (double-fires on the same call, misses the "defer to existing rule" branch). The visitor's defer check is the highest-risk line in the implementation; bias unit tests heavily toward the "rule defers correctly" cases. Fix in-slice if surfaced; it's a single-commit fix to the predicate.
- **Budget overrun past 5 days.** Stop at Phase 3 (unit-tested rule landed on the feature branch). Defer Phase 4 validation to a follow-up round. The feature is still adopter-available — adopter evidence comes from real users rather than a trial campaign.

## Total estimated effort

Phase 0: 0.5 day • Phase 1: 0.5 day • Phase 2: 1 day • Phase 3: 1 day • Phase 4: 1 day • Phase 5: 0.5 day • **~4.5 days, budget 5 with slack.** Matches the round-7 retrospective's 3-5 day estimate. Phase 4 is the riskiest: if the annotation campaign surfaces a new FP class, the round-9 scope expands to "fix FP + re-measure," which can add a day.

## What a clean slice unlocks

If round 9 confirms:
- `strict_replayable` parser + rule land with full unit coverage
- One real-handler campaign completes under 90 minutes of annotation effort
- No new FP classes surface
- Noise profile (Run C ≈ 0) matches the round-6 clean baseline for the non-strict path

then the linter ships its **strictest-available opt-in mode** — the "flag unless proven" story the proposal has named since the earliest draft. The macros package + the linter together deliver an end-to-end adoption path: annotate with `@Idempotent` (cheap, carries a companion test via `@IdempotencyTests`), promote critical handlers to `@lint.context strict_replayable`, live with zero diagnostics as the default.

The next unit of work after a clean round 9 becomes:

1. **Third-corpus validation** — the round-7 retrospective's direction 3. Now actually interesting, because there's something qualitatively new to measure (strict-mode adoption effort on an independently-developed codebase).
2. **Global strict-mode config flag** — once one-handler-at-a-time is proven, codebase-wide opt-in is a natural scale-up slice.
3. **`strict_retry_safe` twin** — trivial clone if real adopters ask. Not before.

If round 9 produces adverse results (Run A is silent everywhere, or the annotation campaign is costly enough to make strict-mode prohibitive), the evidence points at "strict mode is real but adopter friction is high" — that's an input to adoption-advocacy work, not a reason to delete the feature. The rule ships either way.

April 2026.
