# Implementation Plan: Receiver-Type Inference (Phase 2 second slice)

Implementation work on `Joseph-Cursio/SwiftProjectLint`, not a measurement round. The first plan in this repo that is not a trial plan — breaks from the `claude_phase_N_round_M_plan.md` naming for that reason.

Companion to [`claude_phase_2_round_5_plan.md`](claude_phase_2_round_5_plan.md) and to the `phase2-round-5/trial-retrospective.md` recommendation. This plan ships the one piece of machinery the round-5 retrospective identified as the clearest next priority.

## Why this is the right next work

Round 5 surfaced two convergent failure modes of the first-slice bare-name heuristic:

- **Too broad:** `users.append(contentsOf: teammates)` fired `nonIdempotentInRetryContext` on a local Swift `Array` mutation. (Run D on pointfreeco.)
- **Too narrow:** `sendGiftEmail → sendEmail → mailgun.sendEmail` chain silent — no exact `send` match anywhere. (Run B on pointfreeco.)

The round-5 retrospective ruled out YAML whitelists and bare prefix matching as viable first fixes. It named receiver-type inference as the single additive slice that improves both ends of the precision problem:

- Distinguishes `Array<User>.append(...)` from `SomeQueue.append(...)` → fixes too-broad.
- Distinguishes `Mailgun.sendEmail(...)` from hypothetical stdlib `Whatever.sendEmail(...)` → *enables* prefix matching to be added later safely (out of scope for this plan; plan addresses only the receiver-type gate).

## Scope of this plan

**In scope.** A receiver-type gate that excludes stdlib-collection operations from bare-name inference matches. User-defined receivers continue to match the existing whitelists unchanged.

**Out of scope** (with explicit reasons, so round 6 can revisit):

- **YAML-configurable user whitelist.** Round-5 retro ruled this out as first addition. A team can't solve stdlib-level noise (like `Array.append`) via YAML because `Array` is not their code. YAML's strength is in the *second* problem (too-narrow — team adds `Mailgun.sendEmail` to a project list), which this plan intentionally leaves unsolved.
- **Prefix matching (`sendEmail` → `send`).** Round-5 retro: "prefix matching without receiver-type gating is a net negative." With this plan's receiver-type gate in place, prefix matching becomes viable, but it's a separate design decision with its own risks (false positives on user-defined `sendLogToConsole`-shaped names). Defer to a follow-up plan after round 6 evidence.
- **Real type resolution.** This plan does *syntactic* receiver-type inference — it reads what the source code literally says (parameter annotations, pattern-binding annotations, literal shapes). It does *not* do semantic type resolution: no Sema, no `swift symbolgraph`, no `SwiftSyntaxMacros` type checker, no import-graph walking, no generic-parameter substitution, no protocol-conformance resolution. Those are the correct tools for the "what is this expression's type?" question in general, and this plan deliberately does not reach for them. Building a semantic resolver would be ~10× the work of the syntactic one (probably 5-8 weeks rather than 3-5 days) — it requires either running the Swift compiler frontend as a library dependency (`swift-syntax` alone is not enough; you'd need `SwiftParser` plus something like `SwiftCompilerPlugin` or a `swift-driver` integration) or wiring into `sourcekit-lsp` / symbolgraph-extract. Both introduce a new runtime cost, a new toolchain dependency surface, and a new failure mode (what happens when the user's code doesn't compile?). The syntactic approach is intentionally a tenth of the cost for 80% of the precision — the remaining 20% of cases (chained expressions, generic receiver types, cross-module type aliases) return `.unresolved` and fall through to the existing bare-name behaviour, which is the exact round-5 baseline. No regression; no new semantic infrastructure.
- **User-defined type-qualified whitelists.** No baked-in knowledge of specific server-side libraries (Mailgun, Stripe, SwiftNIO). That's YAML territory.

## Design

### What "receiver-type inference" means here

This is a **syntactic** resolver, not a semantic one. The distinction matters because it's tempting to scope-creep into real type inference and the work estimate blows up from days to weeks.

The resolver answers *"what does the source code literally say this receiver's type is?"* — it reads type annotations (`let x: Array<Int>`), literal shapes (`[1, 2]` is an Array), and constructor-call names (`Queue()` → `Queue`). That's it. It does not answer *"what type does the Swift compiler infer for this expression?"* — that question requires Sema, and Sema requires running (or embedding) the compiler frontend.

The syntactic approach lands at roughly 10% of the cost of a semantic one and handles the ~80% of cases that matter for stdlib-collection exclusion: parameters, local bindings, stored properties, and literals all carry or imply their types lexically. The remaining ~20% (chained expressions, generic-parameter receivers, return-type inference, protocol-existential receivers) return `.unresolved` and fall through to the existing bare-name heuristic — the exact round-5 behaviour. No regression; worst case is that some noise diagnostics persist unchanged until a future slice addresses them.

### New module: `ReceiverTypeResolver`

One file: `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/ReceiverTypeResolver.swift`.

```swift
public enum ResolvedReceiverType {
    case stdlibCollection(String)   // "Array", "Set", "Dictionary", "String", "Optional"
    case named(String)              // any other resolvable type name
    case unresolved
}

public enum ReceiverTypeResolver {
    public static func resolve(_ expr: ExprSyntax) -> ResolvedReceiverType
}
```

Resolution sources, in precedence order (first match wins):

1. **Literal shape.** `[1, 2]` → `stdlibCollection("Array")`. `["a": 1]` → `stdlibCollection("Dictionary")`. `"foo"` → `stdlibCollection("String")`. `nil` → `stdlibCollection("Optional")`. `Set([1, 2])` → `stdlibCollection("Set")`.
2. **Constructor call.** `UUID()` → `named("UUID")`. `Array<Int>()` → `stdlibCollection("Array")`. `Queue()` → `named("Queue")`. Extract callee identifier; map stdlib types to `.stdlibCollection`, others to `.named`.
3. **Simple-identifier receiver with local binding.** For `foo.bar(...)`, walk up the parent chain from the call to find the nearest enclosing scope (function body, closure body, top-level). Look for a `let foo: Type = ...` or `var foo = <expr>` binding. If typed, return that type. If untyped, recursively resolve the initializer expression via steps 1-2.
4. **Simple-identifier receiver matching a function parameter.** Walk up to the enclosing `FunctionDeclSyntax` / `InitializerDeclSyntax` / `ClosureExprSyntax`. Match receiver name against parameter names; extract parameter type annotation.
5. **Simple-identifier receiver matching a stored property of the enclosing type.** Walk up to the enclosing `ClassDeclSyntax` / `StructDeclSyntax` / `ActorDeclSyntax`. Match receiver name against member bindings; extract type annotation.
6. **Member-access with `self.` prefix.** Same as step 5 but targeting `self.<name>`.
7. **Everything else.** Return `.unresolved`.

Conservative-by-design: when any step produces ambiguity (generic parameter, chained access, computed property without type annotation), return `.unresolved`. The downstream decision tree treats `.unresolved` as "fall through to existing bare-name heuristic" — the worst case matches current round-5 behaviour.

### Cross-check with `LocalTypeCollector`

`LocalTypeCollector` (already in the visitors package) collects names of every type declared in the project. Before emitting `.stdlibCollection("Array")`, the resolver checks that `Array` is not shadowed by a local type declaration. Pathological case: a team defines their own `Array` type. Very rare, but the check is cheap — one Set membership lookup.

### New module: `StdlibExclusions`

One file: `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/StdlibExclusions.swift`.

Hard-coded pairs of `(receiverTypeName, methodName)` where the stdlib operation is known to be local-only:

```swift
enum StdlibExclusions {
    static let excluded: Set<TypeMethodPair> = [
        TypeMethodPair("Array", "append"),
        TypeMethodPair("Array", "insert"),
        TypeMethodPair("Array", "remove"),
        TypeMethodPair("Array", "removeAll"),
        TypeMethodPair("Array", "removeFirst"),
        TypeMethodPair("Array", "removeLast"),
        TypeMethodPair("String", "append"),
        TypeMethodPair("String", "insert"),
        TypeMethodPair("Set", "insert"),
        TypeMethodPair("Set", "remove"),
        TypeMethodPair("Set", "removeAll"),
        TypeMethodPair("Dictionary", "removeValue"),
        TypeMethodPair("Dictionary", "updateValue"),
    ]

    static func isExcluded(receiver: ResolvedReceiverType, method: String) -> Bool
}
```

Note: `Set.insert` is idempotent by set semantics. The current bare-name whitelist classifies `insert` as non_idempotent across the board. Receiver-type gating restores correctness on sets.

### Wire into `HeuristicEffectInferrer`

Smallest possible change to `HeuristicEffectInferrer.infer(call:)`:

```swift
public static func infer(call: FunctionCallExprSyntax) -> DeclaredEffect? {
    guard let (calleeName, receiverName) = callParts(of: call.calledExpression) else {
        return nil
    }

    // Observational — unchanged
    if let receiverName,
       isLoggerReceiver(receiverName),
       loggerLevelMethods.contains(calleeName) {
        return .observational
    }

    // Bare-name whitelist — now receiver-type gated.
    if idempotentNames.contains(calleeName) || nonIdempotentNames.contains(calleeName) {
        if let receiverExpr = receiverExpression(of: call),
           StdlibExclusions.isExcluded(
             receiver: ReceiverTypeResolver.resolve(receiverExpr),
             method: calleeName) {
            return nil   // stdlib exclusion — no anchor
        }
        if idempotentNames.contains(calleeName) { return .idempotent }
        if nonIdempotentNames.contains(calleeName) { return .nonIdempotent }
    }

    return nil
}
```

Preserves `inferenceReason(for:)` output for non-excluded cases unchanged. Exclusions are silent — they return nil from `infer(call:)`, matching the "no heuristic applies" path, so no new diagnostic prose is needed.

### No API change to consumers

`IdempotencyViolationVisitor` and `NonIdempotentInRetryContextVisitor` (both in `Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Idempotency/Visitors/`) call `HeuristicEffectInferrer.infer(call:)` without a context parameter. The resolver walks parent chains internally. Rules do not change.

Same for `EffectSymbolTable.applyUpwardInference(multiHop:)` — passes `HeuristicEffectInferrer.infer(call:)` as `heuristicEffectForCall`. Unchanged.

## Phases

### Phase 1 — `ReceiverTypeResolver` module (1-1.5 days)

- New file `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/ReceiverTypeResolver.swift`.
- Implements the 7 resolution sources in precedence order.
- Unit tests at `Tests/CoreTests/Idempotency/ReceiverTypeResolverTests.swift`:
  - Literal: `[1, 2].append(...)` → `stdlibCollection("Array")`
  - Dictionary literal: `["a": 1].updateValue(...)`
  - Constructor: `Array<Int>().append(...)`, `Queue().append(...)`, `UUID().uuidString`
  - Parameter: `func foo(x: Array<Int>) { x.append(...) }`
  - Local binding (typed): `let x: [Int] = []`, call `x.append(1)`
  - Local binding (untyped from literal): `var x = [1, 2]; x.append(3)`
  - Local binding (untyped from constructor): `let q = Queue(); q.append("a")`
  - Stored property: `class C { let q: Queue }; ...q.append(...)`
  - `self.` prefix: `class C { var items: [Int] = []; func f() { self.items.append(1) } }`
  - Unresolved: chained access, computed property without type, global variable
  - Shadowing: local type named `Array` → `named("Array")`, not `stdlibCollection`

**Acceptance:** all 11+ test cases green.

### Phase 2 — `StdlibExclusions` table (0.5 day)

- New file `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/StdlibExclusions.swift`.
- Initial exclusion set per the Design section.
- Unit tests at `Tests/CoreTests/Idempotency/StdlibExclusionsTests.swift`:
  - Every pair in the table returns true
  - `(Array, enqueue)` → false (enqueue not an Array method)
  - `(named("UserQueue"), append)` → false (not stdlib)
  - `(unresolved, append)` → false

**Acceptance:** all table entries covered; conservative behaviour on non-stdlib confirmed.

### Phase 3 — Wire into `HeuristicEffectInferrer` (0.5 day)

- Modify `HeuristicEffectInferrer.infer(call:)` per the Design section.
- Extend `HeuristicInferenceTests.swift` with:
  - `users.append(contentsOf: teammates)` where `users` is `var users = [owner]` → nil (excluded)
  - `queue.append("a")` where `queue` is `Queue()` → `.nonIdempotent` (still fires)
  - `set.insert(1)` where `set` is `Set<Int>()` → nil (Set.insert excluded)
  - `userSet.insert("tag")` where `userSet` is user-defined `UserSet()` → `.nonIdempotent` (still fires)

**Acceptance:** exactly the 4 new unit cases above pass; every existing heuristic test still passes unchanged.

### Phase 4 — Regression (0.5 day)

- `swift package clean && swift test` in `/Users/joecursio/xcode_projects/SwiftProjectLint`.
- Expected: all 1976 tests green (same as pre-change baseline) plus the new receiver-type-resolver tests and stdlib-exclusion tests and new inference cases.
- No existing test should require modification. If one does, pause and audit: this plan adds a gate that silences some matches — if that silences a test fixture, it's either (a) the fixture was testing the very behaviour we want to fix (update the fixture) or (b) a real regression (stop).

**Acceptance:** green.

### Phase 5 — Self-validation against R5 fixtures (0.5 day)

No new linter branch. Land the change on `main`, then re-run R5's exact fixtures against the new linter tip:

- Re-run **Run D**: pointfreeco `trial-inference-local` branch. Expect **5 diagnostics** total (down from 6) — the `handleFailedPayment → removeBetaAccess` diagnostic should disappear because `users.append(contentsOf: teammates)` now hits the stdlib exclusion.
- Re-run **Run C**: TrialInferenceAnti.swift synthetic cases. Expect **5 positives / 4 negatives unchanged** — cases 1-5 use user-defined types (`R5Queue`, `R5Logger`, etc.) or bare globals, none of which are stdlib collections. Zero regression.
- Re-run **Run B**: expect **0 diagnostics unchanged** — too-narrow case is intentionally not in scope for this plan.

Document results in `docs/phase2-round-5/post-fix-verification.md` as a lightweight append to the round-5 record. No new round number; this is a verification delta, not a new measurement round.

**Acceptance:** Run D drops by exactly 1 (the noise diagnostic), Run C unchanged, Run B unchanged.

### Phase 6 — Documentation (0.5 day)

- Amend `Docs/idempotency-macros-analysis.md` in the linter repo: the "Still deferred" bullet under "Phase 2: Heuristic Inference" currently lists receiver-type inference as deferred. Move it to the "first slice shipped" list and document the stdlib-exclusion scope.
- Add or update `Docs/rules/` entries for `nonIdempotentInRetryContext` and `idempotencyViolation` if the diagnostic prose needs any clarification note about stdlib exclusions. Expected: none needed — exclusions are silent, so user-facing prose is unchanged.
- Update `CLAUDE.md` in the linter repo only if the architecture section references the inference machinery (spot-check during this phase).

**Acceptance:** proposal document reflects the new capability; no stale "deferred" claim for receiver-type inference.

## Verification end-to-end

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout main
# ... apply changes per phases 1-3 ...

swift package clean && swift test
# Expect: green, test count = 1976 + (new resolver tests) + (new exclusion tests) + (4 new inference cases)

# R5 fixture re-run
cd /Users/joecursio/xcode_projects/pointfreeco
git checkout trial-inference-local
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI . \
  --categories idempotency
# Expect: 5 diagnostics (not 6). The removeBetaAccess diagnostic is gone.
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/ReceiverTypeResolver.swift` — new
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/StdlibExclusions.swift` — new
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/HeuristicEffectInferrer.swift` — modified (the infer method)
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/ReceiverTypeResolverTests.swift` — new
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/StdlibExclusionsTests.swift` — new
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Tests/CoreTests/Idempotency/HeuristicInferenceTests.swift` — extended (4 new cases)
- `/Users/joecursio/xcode_projects/SwiftProjectLint/Docs/idempotency-macros-analysis.md` — Phase 2 section amended
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase2-round-5/post-fix-verification.md` — new, lightweight re-run record

## Risks

1. **Resolver fails to identify `users` as an Array, Run D noise persists.** Mitigation: dedicated unit test for exactly that shape (`var users = [owner]; users.append(contentsOf: teammates)`). Phase 5 self-validation is the corpus-level check.
2. **Resolver wrongly classifies a user-defined type as stdlib** (e.g. `Array` shadowed locally). Mitigation: `LocalTypeCollector` shadowing check before emitting `.stdlibCollection`.
3. **Performance regression.** Walking parent chains per call site is O(D) per call where D is typical nesting depth (<20). On pointfreeco's 918 files, expected sub-second per file. Mitigation: benchmark Run D before-and-after; if degradation is > 50%, move to precomputed parent caches.
4. **Scope creep into YAML or prefix matching.** Flagged explicitly here: the plan silences a specific class of noise and does nothing else. If Run D's other noise (not yet seen) appears, log it; don't expand this plan.

## Estimated effort

- Phase 1: 1-1.5 days (resolver + tests — the largest unit)
- Phase 2: 0.5 day
- Phase 3: 0.5 day
- Phase 4: 0.5 day
- Phase 5: 0.5 day
- Phase 6: 0.5 day
- **Total: 3.5-4 days, budget 5 with slack.** Matches R5 retro's "3-5 days" estimate.

## What a clean receiver-type inference unlocks

1. **Round 6 measurement plan** — re-runs R5 fixtures with the new gate plus a wider FP audit on `trial-inference-local`. The null hypothesis ("inference is adoption-ready") is now testable with Run D's stdlib-noise class removed.
2. **Prefix matching reconsideration** — R5 retro called prefix matching "a net negative without receiver-type gating." With this plan shipped, prefix matching becomes viable; design decision is whether the too-narrow problem (Run B) is worth solving via a gated prefix whitelist or via YAML. Separate plan.
3. **YAML re-evaluation** — YAML's primary value (user-defined positive whitelist entries like `Mailgun.sendEmail`) is still real. This plan doesn't preclude YAML; it just ships the more-urgent piece first.
4. **Set-semantic correctness** — `Set.insert` being excluded via the stdlib table is a quiet win. The current linter incorrectly classifies `knownFeatureFlags.insert(flag)` as non-idempotent; after this plan, set mutations are correct.
