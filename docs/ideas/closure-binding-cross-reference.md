# Deferred idea: first-class cross-reference for closure-bound bindings

**Status.** Explicitly out-of-scope of the closure-handler annotation slice ([`claude_phase_2_closure_handler_annotation_plan.md`](../claude_phase_2_closure_handler_annotation_plan.md)). Shipped slice makes a closure binding's **body** walkable under its own annotation. This doc captures the two remaining pieces that would make closure-bound bindings fully first-class across the rule system.

## Origin

During the closure-handler annotation plan's scope discussion (post-round-6), two related capabilities were deferred with explicit reasons:

1. **Upward body-based inference through closure bindings.** `UpwardEffectInferrer` currently visits `FunctionDeclSyntax` only. An unannotated closure binding whose body contains non-idempotent calls is not analysed — its inferred effect is never computed.
2. **Symbol-table cross-reference entries for closure bindings.** `EffectSymbolTable` keys declared effects by `FunctionSignature`. Callers of a closure binding — e.g. `handler(event, ctx)` from a different function's body — cannot look up the binding's declared annotation, because the symbol table has no entry for it.

Both were deferred on the same grounds: the round-6 motivation ("make closure-bound handler bodies walkable under their annotation") is fully served by the shipped slice. These extensions expand the feature into territory the R6 finding didn't demand.

## What the shipped slice gave us

```swift
/// @lint.context replayable
let handler: @Sendable (Event, LambdaContext) async throws -> Output = { event, context in
    // calls in here are now analysed under the replayable context
    sendEmail(event)   // fires nonIdempotentInRetryContext
}
```

Works today. Calls in `handler`'s closure body fire under the declared context.

## What's still missing

### Missing piece 1 — external-caller lookup

```swift
/// @lint.effect non_idempotent
let sender: (String) -> Void = { msg in
    rawSMTPSend(msg)
}

/// @lint.effect idempotent
func process(_ msg: String) {
    sender(msg)   // should fire idempotencyViolation, but doesn't
}
```

The call `sender(msg)` in `process`'s body looks up `sender` via `FunctionSignature`-based symbol-table lookup. The table has no entry for a closure-bound binding, so the lookup misses. The rule falls through to heuristic inference, which doesn't match either (bare name `sender` isn't whitelisted). No diagnostic fires — even though the user explicitly declared `sender` to be `non_idempotent` and `process` to be `idempotent`.

### Missing piece 2 — upward inference through un-annotated closure bindings

```swift
let helper = { data in
    try await database.insert(data)   // non-idempotent call
}

/// @lint.context replayable
func handle(_ event: Event) async throws {
    try await helper(event)   // should fire — but doesn't
}
```

Under function-decl semantics, `helper` would be an unannotated function whose body contains a non-idempotent call. Upward inference propagates `non_idempotent` to `helper`, and the replayable caller fires. For closure bindings, no such walk happens: `helper` isn't a `FunctionDeclSyntax`, so `UpwardEffectInferrer.inferEffects(in:resolveCalleeEffect:)` skips it.

## Why both are deferred

- **R6's finding was narrow.** It was about un-annotatable handler bodies, not about cross-reference lookups. The shipped slice is a complete answer to the narrow finding.
- **Scope discipline.** Adding two more surface areas (upward inference + symbol table) alongside the binding-site annotation would have tripled the slice's surface. Each piece has its own correctness questions (what's a "binding signature"? how does collision policy apply?) that deserve their own plan, not a rider on the annotation-attachment slice.
- **Zero corpus evidence demands it yet.** The Lambda corpus doesn't call its closure-bound handlers from other parts of its own source — `LambdaRuntime(body: handler)` is the only consumer, and that's a framework boundary the linter doesn't audit. Pointfreeco doesn't use closure-bound bindings at all.

## Design sketches, if either piece gets built

### Symbol-table cross-reference (for missing piece 1)

Extend `EffectSymbolTable` to accept a new entry type keyed by binding identifier:

```swift
struct ClosureBindingEntry {
    let name: String          // identifier from IdentifierPatternSyntax
    let moduleOrFileScope: ... // disambiguation across files
    let effect: DeclaredEffect
    let context: ContextEffect?
}
```

Collision policy mirrors the existing OI-4 rule: multiple bindings with the same name in the same scope (across files) and conflicting effects → withdrawn, silent. Bindings in different scopes (e.g. a `let handler` inside two different functions) don't collide.

Call-site lookup at `sender(msg)`: if `FunctionSignature`-keyed lookup misses, fall through to a name-only lookup against the closure-binding table before consulting heuristic inference. Precedence becomes:

```
declared-function-sig > declared-closure-binding > collision-withdrawn (silent)
> upward-inferred-function > heuristic-downward > silent
```

### Upward inference through closure bindings (for missing piece 2)

Extend `UpwardEffectInferrer.inferEffects` to also collect `VariableDeclSyntax` nodes whose `closureInitializer` is non-nil, walk their closure bodies the same way it walks function bodies, and produce an inference entry keyed under the binding's name.

Escape-closure policy applies unchanged inside the walked closure body. Depth tracking works the same.

## Risks and open questions

- **Binding scoping.** Unlike function decls, let/var bindings live in nested scopes. A top-level `let handler` is one thing; `func outer() { let handler = { ... } }` is another. The symbol-table entry's "scope" needs a well-defined key. Easiest first slice: file-scope top-level `let`/`var`, plus type-member stored properties, plus ignore function-local bindings entirely (their body-walk behaviour is the existing escape-closure-policy feature, not cross-reference).
- **Name collisions across files.** Two files each define `let handler = { ... }` at top level. What's the policy — collision-withdraw, or file-scoped lookup?
- **Type-less bindings.** `var handler = { ... }` with no type annotation has no identifying signature beyond its name. The symbol-table key can only be the name plus scope, not a full signature. That narrows the collision policy to name-matching, which is coarser than the existing function-signature matching.
- **Async-closure captures.** A closure binding that captures a stateful variable introduces reentrancy questions the actor-reentrancy rule already handles — but composing the two rules on a closure binding that participates in both would need a thought-through design.
- **Interaction with escape-closure policy when the binding is passed to a known escape wrapper.** If `handler` is annotated `@lint.effect non_idempotent` and then passed to `Task.detached { handler() }`, does the rule fire in the enclosing caller? Probably yes (the annotation is on the binding, not on the use-site). But it needs a clear rule.

## Trigger for promotion

Either piece becomes worth building when one of:

1. A real adopter codebase is observed to call closure-bound handlers by reference from other parts of its own source at adoption-relevant volume. Pointfreeco + swift-aws-lambda-runtime do not stress this; a web framework application (Vapor, Hummingbird) might.
2. A user of the shipped closure-binding slice asks why `handler` isn't treated as a known-effect callee when it's referenced from elsewhere — i.e. an explicit user-visible gap report.
3. The upward-inference side becomes a prerequisite for a later rule. For example, if a future "handler body must include observability" rule ships ([`missing-observability-rule.md`](missing-observability-rule.md)), it needs to walk closure-bound handler bodies the same way it walks function bodies — making the upward-inference extension a free rider.

None of those triggers exist as of the post-R6 closure-binding-slice shipping date.

## Related

- Shipped slice: [`../claude_phase_2_closure_handler_annotation_plan.md`](../claude_phase_2_closure_handler_annotation_plan.md).
- Verification doc: [`../phase2-round-6/closure-handler-verification.md`](../phase2-round-6/closure-handler-verification.md).
- Adjacent closure-region gap: [`inline-trailing-closure-annotation-gap.md`](inline-trailing-closure-annotation-gap.md).
