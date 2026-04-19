# Trial Findings — Swift Idempotency Linter vs. `apple/swift-aws-lambda-runtime` 2.8.0

Results from executing the Phase 1 linter against the target codebase. Scope was fixed in advance by [`trial-scope.md`](trial-scope.md). This report is strictly descriptive; proposal revisions driven by these findings are in the Open Issues section of [`../idempotency-macros-analysis.md`](../idempotency-macros-analysis.md), and scope-discipline commentary is in [`trial-retrospective.md`](trial-retrospective.md).

## Test vehicle

- **Linter:** `SwiftProjectLint` branch `idempotency-trial`, forked from `main @ 70ba1a5`.
- **Target:** `swift-aws-lambda-runtime` 2.8.0, SHA `553b5e3716ef8e922e57b6f271248a808d23d0fb`.
- **Demo package:** `/Users/joecursio/xcode_projects/swift-lambda-idempotency-demo/`.

Three annotation-gated tiers plus the existing structural rule:

| Identifier | Category | Source |
|---|---|---|
| `idempotencyViolation` | `idempotency` (new) | built in Phase 1 |
| `nonIdempotentInRetryContext` | `idempotency` (new) | built in Phase 1 |
| `actorReentrancy` | `codeQuality` (existing) | already shipping; benchmarked against the proposal's `actorReentrancyIdempotencyHazard` spec |

## Phase 2 — unit fixtures (blocking gate)

15 fixtures across 4 suites (`IdempotencyViolationVisitorTests`, `NonIdempotentInRetryContextVisitorTests`, `IdempotencyRuleInteractionTests`, `ActorReentrancyIdempotencySpecTests`). Full suite status after Phase 1 + 2: **1815 tests in 247 suites passed, 1 known issue**.

Post-OI-3 status (after the follow-up fix described below): **1817 tests in 247 suites passed, 0 known issues** — the known-issue fixture unblocked and two new regression guards added.

### Phase-2 finding: existing `actorReentrancy` rule missed the fix pattern — now resolved

The proposal's canonical fix is to claim the slot with `processedIDs.insert(id)` *before* the `await`, and compensate with `processedIDs.remove(id)` in `catch`. The existing `actorReentrancy` visitor's `collectAssignments` originally recognised `SequenceExprSyntax` whose second element is `AssignmentExprSyntax` (i.e., a literal `=`). It did not treat `Set.insert(_:)` or other mutating-method calls as writes. So the proposal's fix pattern tripped the rule.

**Resolution (follow-up commit):** `collectAssignments` now also recognises `FunctionCallExprSyntax` whose callee is a `MemberAccessExprSyntax` with a base resolving to a tracked stored property (either `X` or `self.X`), *and* whose method name is in a small whitelist of standard-library mutating methods (`insert`, `append`, `remove`, `removeAll`, `updateValue`, `formUnion`, `subtract`, `merge`, etc.). The whitelist is kept narrow so `processedIDs.contains(id)` and other non-mutating reads are not silently treated as writes — a regression guard fixture locks this in.

- Fixture: `ActorReentrancyIdempotencySpecTests.claimBeforeSuspension_noDiagnostic` now passes without `withKnownIssue`.
- Additional regression fixtures: `selfQualifiedMutatingMethodClaim_noDiagnostic` and `containsCallIsNotMistakenForWrite`.
- Still a sub-gap: subscript-set (`self.X[key] = value` as a claim) and compound-assignment operators on tracked collections. Noted in OI-3.

## Phase 3 — positive demonstration (before / after)

Demo package, single `/// @lint.context replayable` handler, unmodified `swift-aws-lambda-runtime` 2.8.0 dependency.

**Before state** (`try await db.insert(order)` where `db.insert` is declared `@lint.effect non_idempotent`):

```
Sources/Demo/OrderHandler.swift:32: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'handle' is declared `@lint.context replayable` but calls 'insert', which is declared `@lint.effect non_idempotent'.
  suggestion: Replace 'insert' with an idempotent alternative, or route the call through a deduplication guard or idempotency-key mechanism.

Found 1 issue (1 error)
```
CLI exit code: `2`.

**After state** (`try await db.upsert(order)` where `db.upsert` is declared `@lint.effect idempotent`):

```
No issues found.
```
CLI exit code: `0`.

The rule fires exactly where the proposal's worked example predicts and goes silent when the call site is fixed. No false positives in the positive-demonstration source.

## Phase 4 — false-positive baseline on the real runtime

### Run A: annotation-gated rules on un-annotated source

```
$ swift run CLI /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
    --categories idempotency
No issues found.
```
CLI exit: `0`. Zero diagnostics, as expected. Annotation-gated rules behave correctly: no annotation, no signal. The `EffectAnnotationParser` did not misread any doc comment elsewhere in the runtime as an annotation.

### Run B: structural `actorReentrancy` rule on un-annotated source

```
$ swift run CLI /Users/joecursio/xcode_projects/swift-aws-lambda-runtime \
    --categories codeQuality --threshold warning
…
Sources/AWSLambdaRuntime/HTTPClient/LambdaRuntimeClient.swift:221: warning: [Actor Reentrancy] Actor reentrancy risk in 'write': 'lambdaState' is checked before await but not updated, allowing concurrent callers to pass the same guard.
Sources/AWSLambdaRuntime/HTTPClient/LambdaRuntimeClient.swift:246: warning: [Actor Reentrancy] Actor reentrancy risk in 'writeAndFinish': 'lambdaState' is checked before await but not updated, allowing concurrent callers to pass the same guard.
Sources/AWSLambdaRuntime/HTTPClient/LambdaRuntimeClient.swift:271: warning: [Actor Reentrancy] Actor reentrancy risk in 'reportError': 'lambdaState' is checked before await but not updated, allowing concurrent callers to pass the same guard.
```

Three diagnostics, all in the same file on the same stored property `lambdaState`.

**Triage — all three:**

| Bucket | Count | Notes |
|---|---|---|
| A — true positive | 0 | |
| B — AST match, design-intent mismatch | 3 | `lambdaState` is a state-machine discriminator, not an idempotency gate |
| C — rule bug | 0 | |

#### Shape of the Category-B finding

`LambdaRuntimeClient` stores `lambdaState: State`, where `State` is an enum whose cases encode the position in a linear request lifecycle (`idle → waitingForNextInvocation → waitingForResponse → sendingResponse → sentResponse`). The three flagged methods (`write`, `writeAndFinish`, `reportError`) all follow the same shape:

```swift
switch self.lambdaState {
case .sendingResponse(let requestID):
    let handler = try await self.makeOrGetConnection()
    guard case .sendingResponse(requestID) = self.lambdaState else {
        fatalError("Invalid state: \(self.lambdaState)")
    }
    return try await handler.writeResponseBodyPart(...)
}
```

The rule flags the `guard case …= self.lambdaState` as a check, sees the subsequent `try await handler.writeResponseBodyPart(…)`, and finds no intervening assignment to `lambdaState`. That pattern match is structurally correct.

But the design intent is different. The guard is a **post-await invariant assertion** that `fatalError`s if another caller mutated the state — a defensive crash, not an idempotency gate trying to deduplicate work. The `requestID` in the pattern ensures cross-invocation callers take different paths; concurrent writes for the same `requestID` are legitimate (streaming a response body). The rule has no way to distinguish "dedup gate" from "state-machine invariant," so it treats both as the same pattern.

**This is the canonical Category-B finding the user predicted.** "A well-maintained codebase should produce findings that are mostly false positives." For `actorReentrancyIdempotencyHazard` specifically, the false-positive mechanism is visible and describable: state-machine defensive assertions match the guard-await-check AST shape but have different semantics.

Noise rate on a realistic target: **3 false positives** in a ~100-file runtime, or roughly **one per critical stateful-actor file**. Not catastrophic, but high enough that it justifies the proposal's OI-1 question about rule scope.

### Post-OI-3 re-run — same three findings

After widening `collectAssignments` to recognise mutating-method calls (the OI-3 fix described under Phase 2), Run B was repeated. The diagnostic count and locations are unchanged — still 3 findings in `LambdaRuntimeClient.swift` on `lambdaState`. The explanation: the runtime's state-machine methods use plain `self.lambdaState = .nextCase(...)` assignments, which the rule already detected. The OI-3 fix addresses a different sub-pattern — method-call-based claims — that the runtime does not happen to use. **OI-3 was real but orthogonal to the Category-B state-machine pattern.** The OI-1 scope question is the one that would change these 3 findings; OI-3 alone does not.

Full transcript: `trial-transcripts/lambda-runB-post-oi3.txt`.

### Run C: one annotated Example handler

`Examples/HelloJSON/Sources/main.swift`, annotated `/// @lint.context replayable` on a new `handle(event:context:)` function on the throwaway local branch `trial-annotation-local`. Re-ran `--categories idempotency`.

```
No issues found.
```

Zero diagnostics. Expected, but **uninformative**: `HelloJSON` is a pure transformation — it computes `HelloResponse` from `HelloRequest` with no side-effecting calls to anything in the per-file symbol table. The rule has nothing to cross-reference even though the annotation is correctly applied. This surfaces the "island of annotations" UX: a single annotated handler in an otherwise un-annotated codebase produces silence regardless of whether the handler would be safe in reality.

## Additional observations not tied to a specific run

- **Per-file symbol table visibility (since resolved — see OI-4 follow-up below).** The demo package's `db.insert` was originally defined in the same file as `handle`, so the rule resolved it. A realistic handler imports `db` from another module or file; the per-file symbol table would not see it and no diagnostic would fire. This was logged as OI-4, then resolved in a follow-up by pulling cross-file propagation into Phase 1.
- **Telemetry / logging tolerance gap.** The demo's "before" state does not exercise this, but any realistic handler will call `context.logger.info(...)`. If `Logger.info` were annotated `@lint.effect non_idempotent` (strictly true — each call appends a log line) the rule would fire inside any `@context replayable` handler, producing noise. No current lattice position distinguishes "business-state effect" from "observational effect." The demo deliberately did not exercise this; it is surfaced here for OI-5.
- **Closure-traversal policy.** The two new visitors stop at escaping-closure boundaries (`Task { }`, `withTaskGroup`, `.task { }`). Documented in the visitor source. Phase-2 fixtures lock in the behaviour; a `@context replayable` caller that spawns a `Task { ... }` calling a `non_idempotent` function produces no diagnostic. Working-as-specified for Phase 1.

## Summary

| Run | Expected | Observed | Pass? |
|---|---|---|---|
| Phase 3 before | 1 `nonIdempotentInRetryContext` | 1 | ✅ |
| Phase 3 after | 0 | 0 | ✅ |
| Phase 4 Run A | 0 on idempotency rules | 0 | ✅ |
| Phase 4 Run B | some `actorReentrancy`, triage for category | 3 diagnostics, all Bucket B | ✅ (as predicted) |
| Phase 4 Run C | 0 on single annotated handler (silent, possibly uninformative) | 0 | ✅ |

The MVP linter runs without crashing, produces zero false positives on the annotation-gated rules in un-annotated source, produces actionable diagnostics on the positive demo, and produces a manageable number of design-intent-mismatch findings on the structural rule. Phase 1 of the proposal is defensible as-is for adoption; no Phase-1 rule was demonstrated to produce false positives under annotation. The structural rule shows the predicted Category-B pattern and motivates the OI-1 scope question.

## Post-trial follow-ups folded back in

Four Open Issues were surfaced during the trial and subsequently addressed in follow-up commits on the same branch:

- **OI-3 (actorReentrancy write detection).** `collectAssignments` widened to recognise mutating-method calls on tracked stored properties. Regression fixture confirms `contains(_:)` and similar reads are not mistaken for writes. Orthogonal to the three Category-B findings on `LambdaRuntimeClient`.
- **OI-4 (per-file symbol table).** Both idempotency visitors conform to `CrossFilePatternVisitorProtocol`; `EffectSymbolTable` now accumulates across every file in the analysis via `merge(source:)`. Collision policy: bare-name collisions withdraw the entry (conservative, provisional). Demo package restructured to validate cross-file resolution end-to-end. New `CrossFileIdempotencyTests` suite covers the positive path plus three collision cases.
- **OI-5 (observational tier).** Promoted into the lattice at the same tier as `idempotent`. Parser recognises `@lint.effect observational`; violation rules extended to flag observational-declared callers that call idempotent or non_idempotent callees. 9 new fixtures.
- **Escaping-closure coverage / SwiftUI `.task` bug.** Coverage on the two visitors went from 72–78% regions to 84–91% regions. The dead `MemberAccessExprSyntax` branch in `isEscapingClosure` was removed and `"task"` added to the whitelist so SwiftUI's `.task { … }` modifier is now honoured as an escape boundary.

Post-follow-ups suite status: **1844 tests / 251 suites, zero known issues, SwiftLint clean.**
