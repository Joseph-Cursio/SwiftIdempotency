# Implementation Plan: OI-3 Residual — Subscript-set + Compound-assignment Write Detection

Third implementation-plan document in this repo (after the receiver-type-inference and closure-handler-annotation plans). Targets the residual sub-gap named in `idempotency-macros-analysis.md` §OI-3: subscript-set claims (`self.table[key] = value`) and compound assignments (`count += 1`) on tracked stored properties are not currently recognised as writes inside `ActorReentrancyVisitor.collectAssignments`.

## Why this is the right closing act before macros

Three convergent reasons:

1. **It's been named since round 1.** OI-3's "Remaining sub-gap" paragraph has sat in the proposal doc since the April 2026 trial. Every subsequent round has noted the gap without closing it. The macros package is a larger investment whose scope doesn't touch this code path — closing the sub-gap now leaves a clean `actorReentrancy` rule behind the macros work, not a pending-residual one.
2. **The fix is bounded and local.** Both sub-gaps live in a single function (`collectAssignments`) and both require the same shape of fix: extend LHS resolution to descend through `SubscriptCallExprSyntax`, and extend the operator-class check from `AssignmentExprSyntax` to include compound-assignment forms. No cross-file dependencies, no symbol-table changes, no new rule infrastructure.
3. **Low risk.** The `actorReentrancy` rule is structural (not annotation-gated) and its existing fixtures cover the resolved portions of OI-3. Adding two new write-detection forms is additive — it catches things it didn't catch before, doesn't change the semantics of what it already catches.

## Scope of this plan

**In scope:**
- **Subscript-set claims as LHS of `=`:**
  ```swift
  self.table[key] = value    // tracked prop: `table`, operator `=`
  queue[id] = .pending       // tracked prop: `queue`, operator `=`
  self.cache[id.uuidString] = .completed
  ```
- **Compound assignments on direct identifiers or `self.` member access:**
  ```swift
  count += 1                 // tracked prop: `count`, op `+=`
  self.count += 1
  self.processedIDs &= other // tracked prop: `processedIDs`, op `&=`
  ```
- **Compound assignments on subscripts (combination of the above):**
  ```swift
  self.table[key] += value   // tracked prop: `table`, op `+=`, LHS is subscript
  counters[id] += 1
  ```

**Out of scope with reasons:**
- **Chained subscripts.** `self.grid[row][col] = value` — LHS is a nested `SubscriptCallExprSyntax`. First slice handles one level of subscript; chained is structurally similar but rare in the sentinel-set idiom the rule targets.
- **Property chains through non-`self` bases.** `otherActor.state = .done` — out of rule scope entirely (the rule only tracks the enclosing actor's stored properties).
- **Dynamic-member-lookup subscripts.** `@dynamicMemberLookup`-backed `self[dynamicMember: "table"] = value` is valid Swift but is not a sentinel-set idiom. Out of scope.
- **Custom operators ending in `=`.** User-defined `infix operator ??=` or similar. Deferred until evidence demands it; the standard compound-assignment operators cover every real-world case in the rule's target pattern.
- **Write detection in nested function / closure bodies.** `collectAssignments` already returns on `FunctionDeclSyntax` and `ClosureExprSyntax` — this slice preserves that boundary.

## Design

### The current shape

`ActorReentrancyVisitor.collectAssignments` has two branches today:

1. **Direct-assignment branch.** `SequenceExprSyntax` whose elements are `[LHS, AssignmentExprSyntax, RHS]`. LHS is either `DeclReferenceExprSyntax` (matching `propertyName`) or `MemberAccessExprSyntax` with `self.` base and property-name member.
2. **Mutating-method branch.** `FunctionCallExprSyntax` whose callee is `receiver.method(...)`, receiver resolves via `trackedPropertyName`, method name is in the `mutatingMethodNames` whitelist.

### What needs to change

**Subscript LHS resolution.** The current direct-assignment branch checks only `DeclReferenceExprSyntax` and `MemberAccessExprSyntax` for the LHS. Add a third case: `SubscriptCallExprSyntax` whose `calledExpression` resolves via `trackedPropertyName`. Mirror the existing `trackedPropertyName` helper so subscript LHS resolution is symmetric with mutating-method LHS resolution.

**Compound-assignment operator recognition.** SwiftSyntax parses `a += b` as `SequenceExprSyntax` with elements `[a, BinaryOperatorExprSyntax(+=), b]`. The existing check `elements[1].is(AssignmentExprSyntax.self)` misses this. Change the check to either:

- Option A: `AssignmentExprSyntax || (BinaryOperatorExprSyntax && operator text is in compound-assignment set)`.
- Option B: `AssignmentExprSyntax || (BinaryOperatorExprSyntax && operator text ends with "=" and isn't in {"==", "!=", "===", "!==", "<=", ">="})`.

Option B is more general and robust to custom compound operators. Option A is safer against misclassification if a custom infix operator happens to end in `=` but isn't semantically a write. For this slice: **Option A with a hardcoded list** — standard compound-assignment operators only. Custom-operator support is deferred (listed in out-of-scope).

Compound-assignment operator list:
```
+=   -=   *=   /=   %=
<<=  >>=
&=   |=   ^=
&+=  &-=  &*=
&<<=  &>>=
```

### Helper function refactor

Extract the LHS resolution logic to a helper `trackedPropertyName(lhs:in:)` that handles all three shapes uniformly:

```swift
private func trackedPropertyName(
    lhs: ExprSyntax,
    in propertyNames: Set<String>
) -> String? {
    // `X` as bare identifier
    if let ref = lhs.as(DeclReferenceExprSyntax.self),
       propertyNames.contains(ref.baseName.text) {
        return ref.baseName.text
    }
    // `self.X`
    if let member = lhs.as(MemberAccessExprSyntax.self),
       let base = member.base?.as(DeclReferenceExprSyntax.self),
       base.baseName.text == "self",
       propertyNames.contains(member.declName.baseName.text) {
        return member.declName.baseName.text
    }
    // Subscript: `X[...]` or `self.X[...]`
    if let subscriptExpr = lhs.as(SubscriptCallExprSyntax.self) {
        return trackedPropertyName(lhs: subscriptExpr.calledExpression, in: propertyNames)
    }
    return nil
}
```

Single recursive helper. Direct-assignment branch and compound-assignment branch both call it. Reduces the existing `trackedPropertyName(receiver:in:)` helper to a pass-through (or unifies the two).

### Why not go broader

Option B (general "ends-in-=" detection) was considered and declined. Two reasons:
- **Safer default.** A custom infix operator `?~=` (hypothetical, but valid Swift grammar) would match Option B's criterion without semantically being a write. Hardcoded list rules this out.
- **Zero corpus evidence for custom compound operators.** All three trial corpora (pointfreeco, Hummingbird, swift-aws-lambda-runtime) use only standard operators in the actor-reentrancy-targeted idiom. Adding general detection without evidence is speculative.

If a future trial round surfaces a real-code custom compound operator that should be recognised as a write, widen the detection then.

## Phases

### Phase 1 — LHS resolution helper (≈0.25 day)

Refactor the existing `trackedPropertyName(receiver:)` helper into a unified `trackedPropertyName(lhs:)` that handles `DeclReferenceExprSyntax`, `MemberAccessExprSyntax` with `self.` base, and `SubscriptCallExprSyntax` (recursive on `.calledExpression`). Update the mutating-method call site to route through the unified helper.

Behavioural invariant: no regression on existing `actorReentrancy` fixtures. The refactor preserves all resolution paths.

**Acceptance:** existing test suite green; unified helper compiles; call-site updates mechanical.

### Phase 2 — Subscript-set claims (≈0.5 day)

Wire subscript-LHS recognition into the direct-assignment branch of `collectAssignments`. Minimal change: the existing `if let declRef = ... else if let memberAccess = ...` ladder gains a third arm using the unified helper.

New tests in the existing `ActorReentrancyIdempotencySpecTests` file:

```swift
@Test func subscriptSetClaim_flagsAsWrite() {
    // Inside an actor method with guard-then-await-then-write pattern.
    // Claim is `self.table[key] = value` — should be recognised as
    // the sentinel-set mutation.
}

@Test func barelySubscriptSetClaim_flagsAsWrite() {
    // `queue[id] = .pending` — no `self.` prefix.
}

@Test func subscriptSetOnNonTrackedProperty_staysSilent() {
    // `other[key] = value` where `other` isn't a tracked property.
}
```

**Acceptance:** three new fixtures green; existing fixtures green.

### Phase 3 — Compound assignments (≈0.5 day)

Add the compound-assignment operator detection. Check element[1] for `BinaryOperatorExprSyntax` whose `.operator.text` is in the hardcoded compound-assignment set. When matched, resolve LHS via the unified helper and append to results.

New tests:

```swift
@Test func compoundAssign_plusEquals_flagsAsWrite() {
    // `count += 1` where `count` is tracked.
}

@Test func compoundAssign_selfPrefix_flagsAsWrite() {
    // `self.count += 1`
}

@Test func compoundAssign_bitwise_flagsAsWrite() {
    // `processedIDs &= other` — edge case on Set-algebra mutation.
}

@Test func compoundAssign_onSubscript_flagsAsWrite() {
    // `self.table[key] += value` — combines subscript + compound.
}

@Test func comparisonOperators_notFlagged() {
    // `if count == other { ... }` must not fire the compound-assign
    // detection. Regression guard for the "ends in =" confusion.
}
```

**Acceptance:** all new fixtures green; existing fixtures unchanged.

### Phase 4 — Regression (≈0.25 day)

`swift package clean && swift test` on the full linter suite. Expected: green, test count = current (2077) + 8 new fixtures (3 subscript + 5 compound).

No existing test should require modification. If one does, audit: likely a test whose fixture happens to use a write form that's now recognised, which would mean the test was passing for the wrong reason previously — flip the expectation.

**Acceptance:** green full suite.

### Phase 5 — Documentation (≈0.25 day)

Three small updates:

1. **`Docs/idempotency-macros-analysis.md` OI-3 text.** Remove the "Remaining sub-gap" paragraph and replace with a short "Fully resolved" note, citing the commits that shipped this slice.
2. **`Docs/rules/actor-reentrancy.md` (if present)** — add a one-line mention of the expanded write-detection surface. Likely already phrased as "writes to tracked properties" at a general level; if so, no edit needed.
3. **`mutatingMethodNames` comment block** — note that the comment's "narrow whitelist" wording still applies; compound-assignment detection is orthogonal (operator-based, not method-name-based).

**Acceptance:** proposal doc reflects full resolution; rule-doc audit complete.

## Acceptance summary

- 8 new unit tests (3 subscript-set, 5 compound-assignment including the combined `table[key] += x` case)
- Existing linter suite green (no pre-existing test modified)
- `collectAssignments` has a unified LHS-resolution helper shared across three recognition paths (direct, mutating-method, subscript) and two operator classes (`=`, compound)
- OI-3 fully resolved in the proposal doc

## Out of scope — summarised

| Feature | Status |
|---|---|
| Subscript-set LHS via `self.X[...]` or `X[...]` | ✅ in scope |
| Compound assignments on direct identifier / `self.` member | ✅ in scope |
| Compound assignments on subscripts | ✅ in scope |
| Chained subscripts (`self.grid[row][col] = value`) | ❌ deferred |
| Dynamic-member-lookup subscripts | ❌ out of scope |
| Writes through non-`self` bases (`otherActor.state = .done`) | ❌ out of rule scope |
| Custom compound operators ending in `=` | ❌ deferred |
| Writes in nested function / closure bodies | ❌ preserves existing boundary |

## Risks

1. **Operator-text-based detection misclassifies a custom operator.** Mitigated by using a hardcoded list (Option A) rather than a "ends-in-=" heuristic (Option B). A custom `?~=` operator wouldn't appear in the list and would not fire.
2. **Subscript LHS resolution recurses indefinitely on a pathological tree.** The recursion in `trackedPropertyName(lhs:)` descends through `SubscriptCallExprSyntax.calledExpression`; SwiftSyntax trees are finite, so recursion terminates. No explicit depth cap needed, but could add one if future fuzz testing surfaces a deeply-nested-subscript pattern that produces measurable stack growth.
3. **Refactor of `trackedPropertyName(receiver:)` touches existing call sites.** Mitigated by Phase 1's explicit scope — refactor-only, no semantic change, existing tests catch any regression.
4. **"Comparison operators" false-positive risk.** `if count == other { ... }` parses as `SequenceExprSyntax` with `BinaryOperatorExprSyntax(==)`. The hardcoded compound-assignment list excludes `==`, `!=`, `<=`, `>=`, `===`, `!==`. Regression test (`comparisonOperators_notFlagged`) locks this in.

## Estimated effort

- Phase 1: 0.25 day (helper refactor)
- Phase 2: 0.5 day (subscript + 3 fixtures)
- Phase 3: 0.5 day (compound-assignment + 5 fixtures)
- Phase 4: 0.25 day (regression)
- Phase 5: 0.25 day (docs)
- **Total: 1.75 days, budget 2 with slack.** Faster than R6's closure-handler slice because there's no visitor-boundary refactor or new AST-shape handling — just extension of an existing analysis function.

## What this unlocks

- **OI-3 fully resolved.** The proposal's Open Issues section loses its longest-standing residual, leaving only OI-1 (rule scope) and OI-8 (inline trailing closures) as open items — both explicitly deferred-by-design rather than deferred-by-backlog.
- **Clean handoff to the macros work.** The next large investment (macros package) layers on top of a complete structural ruleset rather than a complete-minus-one.
- **Actor-reentrancy rule is feature-closed.** Every post-round-1 enhancement (mutating-method whitelist, subscript-set, compound-assignment) has shipped. Future rounds can treat the rule as a fixed baseline and measure *adoption*, not evolution.
