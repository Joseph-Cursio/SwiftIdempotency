# Deferred idea: annotations on inline trailing-closure Lambda handlers

**Status.** Known scope gap. Explicitly out-of-scope for the closure-binding annotation slice that shipped post-round-6. Captured here because ~37% of `swift-aws-lambda-runtime`'s example surface still can't be annotated without a source refactor, and if demand evidence surfaces from a real adopter, this is the next bounded grammar slice to consider.

## Origin

Surfaced during round 6's Phase-0 handler survey on `swift-aws-lambda-runtime` at `2.8.0`. The R6 retrospective named closure-based Lambda handlers as a grammar-gap finding: roughly half the example surface was un-annotatable because `/// @lint.context` / `/// @lint.effect` attached only to `FunctionDeclSyntax`. A ~2-day implementation plan ([`claude_phase_2_closure_handler_annotation_plan.md`](../claude_phase_2_closure_handler_annotation_plan.md)) shipped the closure-binding slice — annotations now attach to single-binding `VariableDeclSyntax` nodes whose initialiser is a closure literal, covering the `let handler: ClosureType = { ... }` form.

Post-slice coverage on the `Examples/` surface: ~47% → ~63% (9 function handlers + 1 R6-survey-missed private `func handler` + 2 authorizer closures out of 19 examples). The remaining ~37% — seven examples plus one internal function — uses the inline trailing-closure form:

```swift
let runtime = LambdaRuntime { (event: Request, context: LambdaContext) in
    // handler body — no binding to attach `/// @lint.context` to
}
```

Affected examples:

- `HelloWorld`
- `HelloJSON`
- `APIGatewayV1`
- `APIGatewayV2`
- `JSONLogging`
- `HummingbirdLambda`
- `CDK`
- `_MyFirstFunction`

All eight handlers are objectively `@context replayable` by Lambda invocation semantics — they're triggered by SQS/SNS/API-Gateway redeliveries that retry. None can currently be annotated without a source edit that pulls the trailing closure into a named binding.

## The documented workaround

```swift
/// @lint.context replayable
let handler: @Sendable (Event, LambdaContext) async throws -> Output = { event, context in
    // same body as before
}
let runtime = LambdaRuntime(body: handler)
```

This refactor is:

- **Mechanical.** One extraction per handler; SwiftSyntax makes it automatable if a mass migration is ever needed.
- **Type-preserving.** The closure's Lambda handler signature flows through the binding's type annotation unchanged; `LambdaRuntime(body:)` accepts the binding via its existing overload.
- **Non-destructive.** No runtime behaviour change, no allocation change (Swift inlines trivially-referenced `let` closures).

The closure-binding slice's plan explicitly lists this as the sanctioned workaround, and the round-6 closure-handler verification doc says "teams wanting coverage on those would refactor." That's a real adoption friction point — but a small and self-contained one, and the trade is against a much larger grammar slice (see next section).

## Why this wasn't the default

Three reasons the inline case was explicitly scoped out:

1. **No binding site to attach the annotation to.** For `LambdaRuntime { event, ctx in ... }`, the closure is an argument expression, not a declaration. Doc comments attach to declarations. Making the linter treat a *call-expression's argument position* as an annotation anchor is a qualitatively different grammar change from "parse doc-comment leading trivia on a variable decl."
2. **Ambiguity on multi-closure calls.** If a call takes more than one closure argument, which closure does the annotation apply to? Resolving that requires either (a) a positional rule ("only the trailing closure counts"), (b) labelled closures with labelled annotations (e.g. `/// @lint.context.body replayable`), or (c) typed-argument inference ("the annotation applies to the closure whose type matches a Lambda-handler shape"). Each has its own design debt.
3. **Inline-only APIs are a regression in adopter friction regardless.** Any static-analysis annotation grammar ends up wanting *something* to attach to; teams shipping handlers inside `LambdaRuntime { }` trailing closures are already opting into a form that's harder to test, harder to share across runtimes, and harder to unit-test in isolation. The refactor to a named binding has second-order benefits beyond annotation coverage; treating it as a prerequisite isn't pure adoption tax.

The closure-binding slice chose the ~10× cheaper design (named-binding attachment) that covers the majority of real codebases, with the inline case documented as a refactor-then-annotate path.

## What a future slice would look like

If a real adopter's codebase is dominated by the inline form and refactoring is declined, the targeted fix is a grammar extension to `EffectAnnotationParser` that:

1. Recognises doc-comment leading trivia on the **call argument** containing a trailing or single-closure-argument expression.
2. Resolves a single-closure-argument-per-call rule by matching the first closure argument syntactically (labels or position-based — design decision).
3. Handles the "doc comment lives on the preceding line, above the `LambdaRuntime(` call" case, which typically means the annotation is attached to the *whole call expression's* leading trivia rather than the argument's.

Implementation-wise, this is a larger slice than the let-binding one:

- Two trivia-attachment sites to handle (pre-call vs. pre-closure-argument) with overlap rules
- The rule visitor needs a third analysis-site shape (call-argument closures) alongside function decls and closure-bound variable decls
- Ambiguity rules around multi-closure calls need a clear policy, preferably with a deterministic error on over-matching rather than a silent first-wins

Rough estimate if demand surfaces: 3-5 days of work, similar in scope to the receiver-type-inference slice rather than the 2-day closure-binding slice. The evidence bar for shipping it: at least one real codebase where the refactor-to-named-binding workaround is refused on non-trivial grounds (e.g., a large-scale Lambda deployment already shipped in inline form with strict code-freeze). As of post-R6, no such evidence exists — `swift-aws-lambda-runtime`'s own examples are the only known instance of the shape, and they're sample code where editing for annotation support is a non-issue.

## Open questions for a future slice

- **Labelled vs. positional.** If we want to annotate the body closure of a call that takes multiple closures, do we need a new grammar form (`/// @lint.context.body replayable`)?
- **Call-site vs. closure-expression trivia.** Which position wins when both are present (unlikely in practice but possible)?
- **Interaction with `@Sendable` and other closure attributes.** Attribute-trivia routing is already a known fragile area (see `doc-comments-after-attributes.md` in this folder); the inline-closure slice would sit in the same region of the codebase.
- **SwiftSyntax layout.** Trailing-closure arguments may or may not have their own leading trivia at the syntax-node level (versus being attached to the preceding token). The implementation needs to verify trivia routing before committing to an approach.

## Related work in this folder

- [`doc-comments-after-attributes.md`](doc-comments-after-attributes.md) — the attribute-trivia routing bug that the closure-binding slice's combined-trivia helper already works around. The inline-closure slice would be in the same neighbourhood.

## Trigger for promotion

Promote this idea to an active plan when one of:

1. A real adopter brings a codebase dominated by the inline form and refuses the refactor path, with a named motivation (regulatory freeze, external dependency).
2. A future round-N measurement on a non-Lambda corpus finds the same shape at adoption-blocking volume (unlikely; inline-trailing-closure handlers are a Lambda-idiom phenomenon).
3. A new grammar feature is being designed that needs argument-position annotation attachment for a different rule, making the inline-closure case a free rider on the broader work.

None of those triggers exist as of the post-R6 closure-binding-slice shipping date. The refactor-to-named-binding workaround is the sanctioned path until evidence says otherwise.

## 2026-04-21 update: prospero round (production-app #4)

**Trigger #2 met, but severity is LOWER than predicted.** Prospero (`samalone/prospero`, a Hummingbird 2.x production app — first Hummingbird prod road-test) uses the inline-trailing-closure form as its *primary* handler shape: every HTTP handler lives inside `router.get/post { request, context in ... }` closures registered from `addXRoutes(to router:, ...)` helper functions. This is **adoption-blocking volume on a non-Lambda corpus**, disconfirming the "unlikely" parenthetical above.

**However**, the prospero round also surfaced a mitigating finding that significantly reduces the severity. The linter's body walker **does traverse trailing closures inside an annotated enclosing function's body**. Annotating the *enclosing registration function* — `addPatternRoutes`, `addForecastRoutes`, `addCalendarRoutes` — with `/// @lint.context replayable` produces diagnostics on all internal calls inside the 7+ trailing closures it registers (9 diagnostics from a single annotation on `addPatternRoutes`, covering `pattern.save`, `pattern.delete`, `hueService.recomputeHues`, and router-DSL false positives). **The enclosing-function annotation is a viable workaround.**

Caveats:

1. **Coarse-grained tier only.** All closures inside the annotated function share the same context tier. Adopters wanting per-route differentiation (e.g. `replayable` POSTs + `observational` GET health-checks in one registrar) must split into separate helper functions or refactor to named handlers. Prospero didn't need this granularity — its `addXRoutes` helpers each cover a single tier's worth of routes.
2. **Diagnostic UX.** The linter reports `addPatternRoutes calls pattern.save` with the line number of the `pattern.save` call (inside the closure). Adopters reading the diagnostic need to map the line back to the specific closure that contains it. Not a correctness issue, a readability one.
3. **Depends on the body-walker behaviour remaining stable.** If a future refactor of the call-graph walker restricts itself to direct-body call sites (no descent into closure literals), this workaround breaks. Low risk given the current visitor design, but worth a test-case to lock in.

Given the workaround, this idea is **reclassified from "deferred pending adopter demand" to "deferred — workaround viable, documented"**. Active promotion is still blocked on trigger #1 (an adopter that refuses the enclosing-function annotation path, which requires a codebase where even the `addXRoutes` helpers don't exist — all routes registered inline at top-level). Prospero doesn't fit that: its `addXRoutes` structure is idiomatic Hummingbird, and the workaround composes cleanly with it.

See [`../prospero/trial-findings.md`](../prospero/trial-findings.md) §"Trailing-closure workaround effectiveness" for the workaround's evidence + measurement.
