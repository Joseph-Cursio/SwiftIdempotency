# Trial: Swift Idempotency Linter vs. `apple/swift-aws-lambda-runtime`

## Context

The design proposal at `/Users/joecursio/xcode_projects/swiftIdempotency/docs/idempotency-macros-analysis.md` specifies a multi-layer Swift idempotency enforcement system. Nothing has been built yet. The user wants to road-test the ideas — specifically, to measure whether the minimum Phase-1 linter produces a tolerable false-positive rate on a well-maintained real codebase. The proposal itself names `apple/swift-aws-lambda-runtime` as the ideal validation target: Lambda SQS/SNS handlers are *objectively* at-least-once by spec, so `@context replayable` annotations are unambiguously correct.

**User's framing:** "This library needs to address idempotency, and we can count on there being few, perhaps zero, bugs. I expect anything found is a candidate for a false positive." The trial's real question is rule quality, not bug-hunting.

## What already exists — shapes the scope

1. **SwiftProjectLint** at `/Users/joecursio/xcode_projects/SwiftProjectLint` is a working modular SwiftSyntax linter (Swift 6.2, SwiftSyntax 602.0.0, 150 rules, built today). It has exactly the infrastructure the proposal assumes: `BasePatternVisitor`, `RuleIdentifier` enum, `CrossFileAnalysisEngine`, `SwiftSyntaxPatternRegistry`, the category-based rule layout.

2. **`ActorReentrancyVisitor` already ships in SwiftProjectLint.** It implements the guard-await-insert AST pattern the proposal calls `actorReentrancyIdempotencyHazard`, including false-positive suppression for resource-binding guards. Files: `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/ActorReentrancyVisitor.swift`, test suite, rule doc. The trial does **not** build this rule; it benchmarks the existing one against the proposal's spec.

3. **`swift-aws-lambda-runtime` is not cloned locally.** It's on Swift 6.0, release 2.8.0 (Feb 2026). Handler protocols are closure-based async. It has `Examples/` (APIGatewayV2, HelloJSON, Streaming, etc.) but **no SQS/SNS samples** — those event types live in the separate `swift-aws-lambda-events` package. The runtime itself has no retry loop (AWS Lambda retries externally), so `@context replayable` has no natural application to runtime internals.

## Scope commitment (guardrail against creep)

The proposal's companion critique specifically warns that the system is too broad. The trial builds only Phase 1 of the proposal's roadmap. Explicitly **out of scope**:

- Effect inference of any kind
- Cross-file propagation (per-file symbol table only)
- Tiers beyond `idempotent` / `non_idempotent` (no `transactional_idempotent`, no `externally_idempotent`, no `unknown`, no `pure`)
- Contexts beyond `replayable` / `retry_safe` (no `once`, no `dedup_guarded`)
- Strict mode
- Scoped idempotency (`idempotent(by:)`)
- `@lint.assume`, `@lint.unsafe`, suppression grammar, grammar versioning
- `@Idempotent` macro, `IdempotencyTestable`, `IdempotencyKey` strong type, `#assertIdempotent`
- Protocol-based layer (`IdempotentOperation`, etc.)

Anything the trial surfaces that would require expanding this list is recorded as a new Open Issue in the proposal — **not** fixed in-trial.

## Phases

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git pull && swift package clean && swift test`. Must be green before any changes.
- `git pull` in `/Users/joecursio/xcode_projects/swiftIdempotency` (docs only; no build).
- Clone `apple/swift-aws-lambda-runtime` at tag **2.8.0** (pinned for reproducibility across the user's two machines) into `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime`. Record the exact commit SHA in `trial-scope.md` below.
- In SwiftProjectLint: create branch `idempotency-trial` from `main`, push to origin. Cross-machine sync uses this single branch.
- Write `/Users/joecursio/xcode_projects/swiftIdempotency/docs/trial-scope.md` — short doc that restates the scope commitment above plus the pinned runtime tag/SHA. This is the text the plan author points at when a finding tempts scope expansion.

**Acceptance:** green tests; pinned clone; branch pushed; scope note committed.

### Phase 1 — Build the MVP linter (≈1.5 days)

Two new rules plus parser and symbol table, following SwiftProjectLint's conventions exactly.

**New category:** `idempotency` (sibling to `stateManagement`, `codeQuality`, etc.).

**New rule identifiers** in `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift`:
- `idempotencyViolation` — `@lint.effect idempotent` function calls a `@lint.effect non_idempotent` function
- `nonIdempotentInRetryContext` — `@context replayable` / `@context retry_safe` function calls a `non_idempotent` function

**Existing rule `actorReentrancy` is left where it is.** No duplication, no rename. The trial references it via its existing identifier.

**New files:**
- `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/Visitors/IdempotencyVisitor.swift` — extends `BasePatternVisitor`; single-pass AST traversal.
- `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/PatternRegistrars/IdempotencyViolation.swift`
- `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/PatternRegistrars/NonIdempotentInRetryContext.swift`
- `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/EffectAnnotationParser.swift` — reads `/// @lint.effect <tier>` and `/// @lint.context <kind>` out of `leadingTrivia`. Two tiers, two contexts. Unknown tokens ignored silently.
- `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/EffectSymbolTable.swift` — per-file `[FunctionName: (DeclaredEffect?, ContextEffect?)]`.

**Modified files:**
- `Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/PatternCategory.swift` — add `idempotency` case.
- `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/BuiltInRuleRegistration.swift` — register the two new rules.

Reuse `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/ActorReentrancyVisitor.swift` as the structural template.

**Acceptance:** `swift package clean && swift test` still green. `swift run CLI /tmp/stub --categories idempotency` runs without error.

### Phase 2 — Unit-test fixtures (blocking gate, ≈0.5 day)

Before pointing the linter at real code, each rule must pass a canonical positive, canonical negatives, and adversarial negatives. The critique's "false positives from heuristic rules" warning is earned only if these exist.

Tests at `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/`, mirroring `Tests/CoreTests/CodeQuality/ActorReentrancyVisitorTests.swift` in shape.

**`idempotencyViolation` fixtures:**
- Positive: `@effect idempotent` calls `@effect non_idempotent` → 1 diagnostic.
- Negative: `idempotent` calls `idempotent` → 0.
- Negative: unannotated calls `non_idempotent` → 0 (unknown stays unknown in Phase 1).
- Adversarial: `non_idempotent` callee is a method on `self` (method name-resolution is the top parser-bug risk).
- Adversarial: callee name collides with a local variable (parser must distinguish).

**`nonIdempotentInRetryContext` fixtures:**
- Positive: `@context replayable` calls `non_idempotent` → 1 diagnostic.
- Negative: `replayable` calls `idempotent` only → 0.
- Adversarial: `replayable` contains `Task { ... }` that calls `non_idempotent`. **Decide and document** whether Phase 1 traverses into closures (recommend: yes for unescaping, no for escaping) — record the decision in the visitor's doc comment.
- Adversarial: function carries both `@context replayable` and `@effect idempotent` and calls `non_idempotent` — both rules must fire.

**`actorReentrancy` fixture (regression, not new-code):**
- Confirm existing tests pass unchanged.
- Add one fixture matching the proposal's canonical `processedIDs.contains → await → processedIDs.insert` to document spec alignment. Quote this in Phase 5 write-up.

**Acceptance:** all fixtures pass. If any fail, fix the rule; do not proceed to Phase 3.

### Phase 3 — Positive demonstration (≈0.5 day)

Reproduce the proposal's worked example exactly. This is the clean artifact for the write-up.

- New Swift package at `/Users/joecursio/xcode_projects/swift-lambda-idempotency-demo/`. Imports `swift-aws-lambda-runtime` 2.8.0 as a dependency. Do **not** fork the runtime.
- Two handler states, both using `LambdaRuntime` closure form with a hand-crafted stub `Database` type:
  1. **Before:** `@context replayable` handler calls `db.insert(...)` where `db.insert` is annotated `@effect non_idempotent`. Expect exactly one `nonIdempotentInRetryContext` diagnostic.
  2. **After:** call changed to `db.upsert(...)` annotated `@effect idempotent`. Expect zero diagnostics.
- Capture CLI output verbatim for both runs.

**Acceptance:** before/after transcripts match the proposal's Phase 1/Phase 2 worked example shape.

### Phase 4 — False-positive baseline on the real runtime (≈1 day)

This is the phase that answers the user's actual question.

**Run A — full runtime, no annotations.**
`swift run CLI /Users/joecursio/xcode_projects/swift-aws-lambda-runtime --categories idempotency`. The two annotation-gated rules are expected to produce **zero diagnostics** (no `@lint.effect`/`@context` annotations exist in the runtime). Any diagnostic here is a parser bug reading something as an annotation that isn't — itself a finding worth recording.

**Run B — actor-reentrancy structural rule.**
`swift run CLI /Users/joecursio/xcode_projects/swift-aws-lambda-runtime --categories codeQuality --threshold warning` filtered to `actorReentrancy`. Some diagnostics expected; each is the user's false-positive candidate. Triage into three buckets:
- **A — true positive** (rare given codebase quality, but possible — the bug is subtle by design).
- **B — correct AST match, design-intent mismatch** (e.g., a dictionary used for connection pooling matches the pattern but isn't an idempotency gate). **This is what the user cares about.** For each, record the one-sentence reason the AST cannot distinguish intent — this directly feeds OI-1 in the proposal.
- **C — rule bug** (misidentifies non-matching pattern). Fix if trivial; otherwise record.

**Run C — single annotated handler in `Examples/`.**
On a throwaway local-only branch of the cloned runtime (do not push), annotate one handler (e.g., `Examples/HelloJSON`) with `/// @context replayable` and re-run. Surfaces the "island of annotations" UX problem without committing to broad annotation coverage.

**Expected failure modes per rule:**
- `idempotencyViolation`: on un-annotated source should produce zero. Non-zero = parser over-triggering.
- `nonIdempotentInRetryContext`: on un-annotated source cannot produce diagnostics (structurally gated). Real risk surfaces in Run C: **any annotated handler will eventually call `context.logger.info(...)`.** Logging is non-idempotent under a strict reading but nobody treats it as a retry hazard. The proposal has no tier between `idempotent` and `non_idempotent` for telemetry-only effects. **This is the gap the trial exposes that cannot be fixed in scope.** Record.
- `actorReentrancy`: `LambdaRuntime` itself is an actor in 2.x. Connection-pooling or cache dictionaries with guard/await/insert shape will match structurally without being idempotency gates. Canonical bucket-B finding → maps to proposal's OI-1.

**Acceptance:** triaged table with counts per bucket for Run B; annotated-handler transcript for Run C; any Run A non-zero treated as a bug.

### Phase 5 — Write-up (≈0.5 day)

Three artifacts.

1. **`/Users/joecursio/xcode_projects/swiftIdempotency/docs/trial-findings.md`** — counts per rule, triaged buckets for `actorReentrancy`, representative quoted diagnostics, Phase 3 before/after transcripts verbatim, link to sample-package source and throwaway annotated-handler diff.

2. **Updates to `docs/idempotency-macros-analysis.md` Open Issues section** — new issues surfaced by the trial. At minimum: (OI-3) the logging/telemetry non-idempotent conflation from Phase 4; (OI-4) per-file symbol table visibility gap when handlers call across module boundaries — which is working *as specified* for Phase 1 but the user should see it happen before agreeing Phase 1 ships; any additional bucket-B patterns from `actorReentrancy` triage that refine OI-1's scope question.

3. **`/Users/joecursio/xcode_projects/swiftIdempotency/docs/trial-retrospective.md`** — one page, no more. Did the scope commitment hold? Which findings tempted expansion? Which un-built rules (effect inference, cross-file, `externally_idempotent`, protocol layer) would have changed the triage outcome? Protects the next trial from scope creep by writing down what this one cost.

**Acceptance:** user can answer "what's the false-positive rate of this linter on a well-maintained codebase?" with a triage table, not a vibe.

## Verification end-to-end

From a fresh terminal on either machine:

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout idempotency-trial && git pull
swift package clean && swift test                    # Phase 1 + 2 pass

cd /Users/joecursio/xcode_projects/swift-lambda-idempotency-demo
# Revert to the "before" state of Phase 3 commit:
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect exactly one nonIdempotentInRetryContext diagnostic.
# Revert to the "after" state:
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect zero diagnostics.

swift run --package-path ../SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
  --categories idempotency
# Expect zero diagnostics (un-annotated source; annotation-gated rules).

swift run --package-path ../SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
  --categories codeQuality --threshold warning
# actorReentrancy diagnostics: triage per trial-findings.md.
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/ActorReentrancyVisitor.swift` — template + benchmark
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/` — where `EffectAnnotationParser` and `EffectSymbolTable` land
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift` — add two cases
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/BuiltInRuleRegistration.swift` — register new rules
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/idempotency-macros-analysis.md` — target of Phase 5 Open Issues edits

## Total estimated effort

Phase 0: 0.5 day • Phase 1: 1.5 days • Phase 2: 0.5 day • Phase 3: 0.5 day • Phase 4: 1 day • Phase 5: 0.5 day • **~4.5 days, budget 6 with slack.** The Phase 2 adversarial fixtures are the most important investment — every hour there buys credibility in Phase 4.
