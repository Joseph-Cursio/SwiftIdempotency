# Implementation Plan: Closure-handler Annotation Grammar

Implementation work on `Joseph-Cursio/SwiftProjectLint`. Second implementation-plan document in this repo (after [`claude_phase_2_receiver_type_inference_plan.md`](claude_phase_2_receiver_type_inference_plan.md)). Directly motivated by the unplanned finding in [`phase2-round-6/trial-retrospective.md`](phase2-round-6/trial-retrospective.md).

## Why this is the right next work

Round 6 surfaced a grammar gap that R5 did not: roughly half of `swift-aws-lambda-runtime`'s example surface uses closure-based handlers — `LambdaRuntime(body: someClosureExpression)` — and the current `/// @lint.context` grammar attaches only to `FunctionDeclSyntax.leadingTrivia`. Un-annotatable handlers go uncovered by the retry-context rule. The R6 retro concluded: "a real adopter shipping a Lambda app in the modern Swift style would find a non-trivial fraction of their retry-exposed surface unreachable by the lint tool."

Among the remaining candidate work items after R5 and R6, this is the **cheapest slice** that delivers new signal for a real adopter shape. The macro package is the larger qualitative step (5-8 weeks); a third-corpus validation is duplicative; YAML/whitelist extensions are speculative until evidence demands them. Closure-handler annotation is small, targeted, and bounded by the round-6 evidence.

## Scope of this plan

**In scope.** Support `/// @lint.context replayable` (and `retry_safe`, `once`) and `/// @lint.effect <tier>` on **named bindings initialised by a closure expression**:

```swift
/// @lint.context replayable
let handler: @Sendable (Event, LambdaContext) async throws -> Output = { event, context in
    // body — walked as a replayable context, rule fires on non-idempotent calls here
}
```

Covers all three binding forms the Lambda examples actually use:

1. Top-level `let name: ClosureType = { ... }`
2. Top-level `var name = { ... }` (inferred type)
3. Stored property `class C { let handler: ClosureType = { ... } }`

**Out of scope with explicit reasons** (so a future round knows what was deferred vs missed):

- **Inline closure arguments without a binding** (`LambdaRuntime { event, context in ... }`). No binding site to attach the annotation to. Users who want coverage refactor to a named binding. Half the Lambda examples use this shape; documenting the refactor workaround is acceptable adoption friction, and the cleaner fix (annotation on call arguments) is a much larger grammar design problem.
- **Upward body-based inference through closure bindings.** A closure-bound handler's body currently isn't walked by `UpwardEffectInferrer`. Extending it would make the binding's *effect* (not context) propagate to callers. For R6's finding, only the context direction matters. Deferred.
- **Symbol-table cross-reference entries for closure bindings.** A different function's body that calls `handler(event, ctx)` wouldn't know `handler`'s declared effect. Same deferred-for-scope reason as upward inference — the R6 shape doesn't need it.
- **`@lint.effect` on bindings semantics beyond flagging the body.** Annotating a closure binding `@lint.effect non_idempotent` is syntactically valid under this plan, but calls to that binding from elsewhere don't benefit from the annotation. The binding's body is still walked correctly; the extra-site-of-truth behaviour comes with a later slice.
- **Type-annotation-based context inference** (e.g. "this closure's type is `@Sendable (LambdaEvent, LambdaContext) -> Output`, therefore `replayable`"). Distinct design problem, not in scope.

## Design

### The three things the parser needs to do

1. **Read annotations from `VariableDeclSyntax.leadingTrivia`**, combining with trivia between attributes/modifiers (same pattern as the existing `FunctionDeclSyntax` combined-trivia helper).
2. **Recognise that the variable's initializer is a closure**, not some other expression. A non-closure initializer (`let x: Int = 42`) with an annotation should be ignored — annotations on non-closure bindings are meaningless and silent.
3. **Apply the annotation's effect to the closure's body**, not to the variable binding itself. The rule visitor treats the closure's `.statements` the same way it treats a function decl's `.body`.

### Parser extension

Add two convenience overloads to `EffectAnnotationParser`:

```swift
public static func parseEffect(declaration: VariableDeclSyntax) -> DeclaredEffect?
public static func parseContext(declaration: VariableDeclSyntax) -> ContextEffect?
```

Trivia-collection logic mirrors the function-decl version: combine `decl.leadingTrivia` + attributes' leading/trailing trivia + modifiers' leading trivia + `bindingSpecifier` leading trivia.

### Detecting a closure-initialised binding

Helper on `VariableDeclSyntax`:

```swift
extension VariableDeclSyntax {
    /// Returns the initializer closure expression if this decl has
    /// exactly one binding and that binding is initialised by a closure
    /// literal. Returns nil for multi-binding decls, non-closure
    /// initializers, or uninitialized bindings.
    public var closureInitializer: ClosureExprSyntax? { ... }
}
```

Multi-binding decls (`let a = {}, b = {}`) are explicitly nil — Swift allows them but they're rare and ambiguous for annotation attachment. One binding per decl is the only supported form.

### Rule visitor extension

Both `IdempotencyViolationVisitor` and `NonIdempotentInRetryContextVisitor` already walk function-decl bodies under a declared context. The extension:

1. Visit `VariableDeclSyntax`.
2. If it has a closure initializer AND an annotation, push the annotation onto a scope stack before descending into the closure body.
3. Walk the closure body the same way function bodies are walked today — calls inside the closure fire the rule based on the pushed scope.
4. Pop the scope on exit.

For call-site effect lookup, the only difference: calls inside a closure-annotated scope are evaluated against the closure's declared context/effect, not the enclosing function's.

### Escape-closure gate — important distinction

`UpwardEffectInferrer.isEscapingClosure` currently treats closures passed to `Task { }`, `withTaskGroup { }`, and a handful of other known escape-sites as boundaries. For the new closure-handler case:

- A closure bound to `let handler = { ... }` and then passed to `LambdaRuntime(body: handler)` is **not** an escape closure in the `Task`-boundary sense. It's the handler's body. The rule walks it fully.
- A closure passed *as an argument inside* the handler body — e.g. `handler = { event, ctx in Task { publish(event) } }` — remains an escape boundary by the existing gate. No change needed.

In practice: the plan only needs to ensure the visitor enters the handler's outer closure (the one the annotation applies to) directly. Existing escape-gate logic is unaffected.

### No symbol-table entries yet

The rule fires on calls inside the annotated closure's body. It does NOT register the binding in the symbol table for cross-reference. Callers of `handler(...)` from other functions won't see `handler` as `replayable` — because context is the binding's body rule, not the binding's type. This asymmetry matches function-decl behaviour: `@lint.context replayable` on a function scopes to that function's body, not to callers of it. Consistent semantics.

### Diagnostic prose

No new prose. Existing rule messages reference "declared `@lint.context replayable`" — which is still true. The binding's name (rather than a function's name) flows into the existing format string: *"'handler' is declared `@lint.context replayable` but calls ..."*. A closure binding's name is what SwiftSyntax exposes via `binding.pattern` as an `IdentifierPatternSyntax`.

## Phases

### Phase 1 — Parser extension (≈0.5 day)

- New overloads in `EffectAnnotationParser`:
  - `parseEffect(declaration: VariableDeclSyntax) -> DeclaredEffect?`
  - `parseContext(declaration: VariableDeclSyntax) -> ContextEffect?`
- New helper `VariableDeclSyntax.closureInitializer -> ClosureExprSyntax?` (single binding, closure-shaped initializer).
- Unit tests at `Tests/CoreTests/Idempotency/ClosureBindingAnnotationParserTests.swift`:
  - `/// @lint.context replayable` + `let f = { ... }` → parses context
  - `/// @lint.context replayable` + `var f = { ... }` → parses context
  - Multi-binding decl (`let a = {}, b = {}`) → closureInitializer is nil
  - Non-closure initializer (`let x = 5`) → closureInitializer is nil
  - Closure binding via stored property in a class/struct/actor → parses
  - Annotation between attributes works (trivia-combining)

**Acceptance:** all parser tests green; no regression on existing function-decl parser tests.

### Phase 2 — Rule-visitor wiring (≈0.5-1 day)

Both `IdempotencyViolationVisitor` and `NonIdempotentInRetryContextVisitor` extended:

- Override `visit(_ node: VariableDeclSyntax)`.
- If the decl has a closure initializer AND an annotation, descend into the closure's body with the annotation as the active scope; otherwise skip children of the variable decl.
- Existing function-decl scope stack doesn't need structural changes — the closure's body becomes a new frame on the same stack.

Unit tests at `Tests/CoreTests/Idempotency/ClosureBindingRuleTests.swift`:

- `/// @context replayable` + `let h = { sendNotification() }` → 1 diagnostic via prefix match
- `/// @context replayable` + `let h = { _ = 42 }` → 0 diagnostics (benign body)
- `/// @effect non_idempotent` + `let h = { ... }` + replayable caller calls `h(...)` → depends on symbol-table entry (out of scope; expect 0 until Phase 4 maybe)
- `/// @effect observational` + `let h = { queue.enqueue(x) }` → 1 diagnostic (observational → inferred non_idempotent)
- Closure in a class stored property:
  ```swift
  class C {
      /// @lint.context replayable
      let handler: ... = { event in sendEmail(event) }
  }
  ```
  → 1 diagnostic
- Shadowing: declaring two bindings with the same name in different scopes with different annotations → each scope honours its own

**Acceptance:** all rule-visitor tests green; no regression on existing HeuristicInferenceTests or function-decl rule tests.

### Phase 3 — Regression (≈0.25 day)

- `swift package clean && swift test` — expect green, test count = 2049 + new closure-binding tests.
- No existing test should require modification. If one does, triage: most likely it's a test whose fixture happens to include a closure-bound variable declaration that the new parser now sees and annotates, which would be the exact behaviour we want.

**Acceptance:** full suite green.

### Phase 4 — R6 real-corpus validation (≈0.25 day)

Re-run the R6 Lambda corpus measurement, but this time with closure-handler annotations. Pick 2-3 examples from the R6 closure-based list:

- `Examples/HelloWorld/Sources/main.swift` — if it uses `let handler = { ... }` form or `LambdaRuntime { ... }` inline
- `Examples/APIGatewayV2+LambdaAuthorizer/Sources/AuthorizerLambda/main.swift` — `let simpleAuthorizerHandler: Type = { ... }` confirmed in R6 trial-scope
- `Examples/ServiceLifecycle+Postgres/Sources/Lambda.swift` — stored-property closure confirmed

For each `let`/`var` + closure-initializer shape, add `/// @lint.context replayable`. For pure-closure-argument shapes (`LambdaRuntime { ... }`), document as "refactor to named binding first" — that's the explicit workaround.

Re-run linter. Expect:
- Annotatable examples: 0 new diagnostics (same reasoning as R6 Run B — Lambda examples don't call whitelist-matching external side effects)
- Annotation coverage gap closes from ~50% to ~80% of the example surface (documented via the scope doc's updated candidate table)

Write findings to `docs/phase2-round-6/closure-handler-verification.md`. Lightweight, not a new round.

**Acceptance:** annotations that used to be un-attachable now parse; zero regression on Run A; Run B result distinguishes between "un-annotatable before" and "annotatable but silent because body doesn't match whitelist."

### Phase 5 — Documentation (≈0.25 day)

- Amend `Docs/idempotency-macros-analysis.md`: add a closure-binding-annotation subsection under Phase 1 ("Annotation grammar") or as a Phase 2 grammar extension.
- Update `Docs/rules/non-idempotent-in-retry-context.md` to mention that `@lint.context` now applies to closure-bound variables as well as function declarations.
- Optionally elevate the "inline trailing-closure" gap to an OI entry (candidate: OI-8). Short paragraph describing the limitation and the workaround.

**Acceptance:** proposal doc reflects the new capability; OI entry optionally added.

## Acceptance summary

- ≥6 new unit tests for parser + rule-visitor closure-binding behaviour
- Existing linter test suite green (no modifications to prior tests required)
- At least 2 R6 Lambda closure-handler examples successfully annotated (measured via parser no-op vs. rule fires correctly)
- Proposal doc + rule doc amended
- R6 closure-handler-verification doc added

## What's not in scope — summarised

| Feature | Status |
|---|---|
| `@lint.context` on `let handler = { ... }` bindings | ✅ in scope |
| `@lint.context` on stored-property closures | ✅ in scope |
| `@lint.effect` on closure bindings (body-scoped rule) | ✅ in scope |
| Upward inference through closure bindings | ❌ deferred |
| Symbol-table cross-reference entries for closure bindings | ❌ deferred |
| Inline `LambdaRuntime { ... }` trailing closures | ❌ deferred (documented workaround) |
| Type-annotation-based context inference | ❌ out of scope |

## Risks

1. **Multi-binding decls (`let a = {}, b = {}`).** Plan explicitly returns nil for these — they won't be annotated. Risk: a user writes this form and expects it to work. Mitigation: document the one-binding-per-decl rule in the proposal grammar section.
2. **Closure argument-label collision with existing escape-gate names.** `UpwardEffectInferrer.escapingCalleeNames` contains "task", "Task", etc. If a user names their binding `task` (lowercase), the escape gate wouldn't be triggered incorrectly — the gate checks callee names of the outer `Task { }` call, not the binding identifier. No actual collision. Worth a unit test to document.
3. **Stored-property closure with side-effectful initialisation.** A class property `let handler = { ... }` whose closure captures side-effectful state at construction time is rare but possible. Doesn't affect linter semantics (we walk the closure body regardless of capture list). No mitigation needed; just note.
4. **Performance regression.** Adding a `visit(_ VariableDeclSyntax)` override to both rule visitors costs one extra case in the SwiftSyntax dispatch loop per file. Trivial. No benchmark needed.

## Estimated effort

- Phase 1: 0.5 day (parser + unit tests)
- Phase 2: 0.5-1 day (rule-visitor extension + unit tests — the largest unit)
- Phase 3: 0.25 day (regression)
- Phase 4: 0.25 day (R6 corpus validation)
- Phase 5: 0.25 day (docs)
- **Total: 1.75-2.25 days, budget 3 with slack.** Matches the R6 retro's "1-2 days" estimate.

## What a clean closure-handler slice unlocks

1. **Lambda annotation coverage jumps from ~45% to ~85%.** Of the 19 Lambda examples, 9 were already annotatable via `func handle(...)`; this slice adds the 6-7 examples with named-closure-binding handlers. The remaining 3-4 with pure inline trailing closures stay refactor-to-annotate.
2. **Round 7 measurement regains a clean signal.** Any future Lambda-corpus round can now cover the closure-handler surface without a grammar-gap asterisk in the findings.
3. **Macro package parallelism.** The macro work (proposal Phase 5) doesn't depend on this slice; teams can invest in both simultaneously. This slice lowers adoption friction for the linter side; the macro package adds compile-time enforcement. Complementary.

A round 7 measurement could then ask: "on a corpus with mixed function-decl and closure-based handlers, does the inference fire productively at an adoption-ready rate?" Without this slice, the answer is "we can't tell — half the handler surface is unmeasured." With it, the question is answerable.
