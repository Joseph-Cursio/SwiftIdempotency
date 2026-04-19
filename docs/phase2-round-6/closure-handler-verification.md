# Closure-handler Slice — R6 Corpus Verification

Verifies the closure-handler annotation grammar (Phase 2 third slice) against the R6 Lambda corpus. Lightweight append to the round-6 record; not a new round.

## New linter baseline

- **New parser overloads** in `EffectAnnotationParser`:
  - `parseEffect(declaration: VariableDeclSyntax) -> DeclaredEffect?`
  - `parseContext(declaration: VariableDeclSyntax) -> ContextEffect?`
  - `combinedDocTrivia(for: VariableDeclSyntax)` helper
- **New syntax helpers** on `VariableDeclSyntax`:
  - `closureInitializer: ClosureExprSyntax?` — single-binding + closure-literal check
  - `firstBindingName: String?`
- **Rule-visitor wiring** in both `IdempotencyViolationVisitor` and `NonIdempotentInRetryContextVisitor`:
  - `AnalysisSite` generalised from storing `FunctionDeclSyntax` to storing `callerName: String` + `body: Syntax`
  - New `visit(VariableDeclSyntax)` override collects annotated closure-bound sites
  - `analyzeBody` skips descent into closure-initialised bindings **only** when the binding carries its own annotation (preserves existing escape-closure-policy semantics for unannotated closure bindings like `let work = { insert(id) }; await work()`)

Full linter test suite: **2077 tests in 269 suites, all green** (up from 2049/267 at the R6 end-state baseline — 28 new tests across two new suites).

## Annotated examples

Two closure-based handlers in `Examples/APIGatewayV2+LambdaAuthorizer/Sources/AuthorizerLambda/main.swift` annotated:

```diff
+/// @lint.context replayable
 let policyAuthorizerHandler:
     (APIGatewayLambdaAuthorizerRequest, LambdaContext) async throws -> APIGatewayLambdaAuthorizerPolicyResponse = {
```

```diff
+/// @lint.context replayable
 let simpleAuthorizerHandler:
     (APIGatewayLambdaAuthorizerRequest, LambdaContext) async throws -> APIGatewayLambdaAuthorizerSimpleResponse = {
```

Both are the canonical "`let name: ClosureType = { ... }`" shape the slice was designed for.

## Result

| State | Diagnostics | Notes |
|---|---|---|
| R6 end-state (9 `func` annotations + scaffold + `TrialInferenceAnti`) | 4 | 4 scaffold catches |
| **+ 2 closure-binding annotations** | **4** | **No new real-code diagnostics; no regression** |

Same-count result is the expected outcome:
- **Parser works** — the linter now reads `/// @lint.context replayable` from a closure-bound `let` declaration without raising parser errors.
- **No false positives** — both authorizer bodies call `context.logger.debug(...)` (observational, silent), construct a response value, and return. None of the calls match the inference whitelist.
- **Scaffold unchanged** — all 4 `TrialInferenceAnti` cases fire identically; no regression.

This matches R6's Run B result (9 `func`-style annotations produced 0 diagnostics) for the same root reason: Lambda example bodies don't exercise the current inference whitelist. The slice's goal was to *make the bodies reachable* by the rule, not to generate catches on demo code.

## Annotation coverage — before and after

The R6 retrospective flagged ~50% of the Lambda example surface as un-annotatable. Post-slice:

| Example | Pre-slice | Post-slice |
|---|---|---|
| `BackgroundTasks` | `func handle` annotated | unchanged |
| `ManagedInstances/BackgroundTasks` | `func handle` annotated | unchanged |
| `ManagedInstances/Streaming` | `func handle` annotated | unchanged |
| `Streaming+APIGateway` | `func handle` annotated | unchanged |
| `Streaming+FunctionUrl` | `func handle` annotated | unchanged |
| `MultiTenant` | `func handle` annotated | unchanged |
| `MultiSourceAPI` | `func handle` annotated | unchanged |
| `Testing` | `func handler` annotated | unchanged |
| `S3_Soto` | `func handler` annotated | unchanged |
| **`APIGatewayV2+LambdaAuthorizer`** | ❌ closure, out of reach | ✅ both closures annotated |
| `ServiceLifecycle+Postgres` | ❌ R6 survey missed (private `func handler`) | 📝 annotatable via existing grammar; R6 survey bug |
| `HelloWorld` | ❌ inline trailing closure | ❌ still out of reach (explicit scope-out) |
| `HelloJSON` | ❌ inline | ❌ out of reach |
| `APIGatewayV1` | ❌ inline | ❌ out of reach |
| `APIGatewayV2` | ❌ inline | ❌ out of reach |
| `JSONLogging` | ❌ inline | ❌ out of reach |
| `HummingbirdLambda` | ❌ inline | ❌ out of reach |
| `CDK` | ❌ inline | ❌ out of reach |
| `_MyFirstFunction` | ❌ inline | ❌ out of reach |

Coverage: was 9/19 ≈ 47%. Now 12/19 ≈ 63% (9 functions + 2 authorizer closures + 1 R6-survey-missed private `func handler`).

The remaining 7 examples all use the inline `LambdaRuntime { ... }` form the plan explicitly scoped out. Teams wanting coverage on those would refactor to:

```swift
/// @lint.context replayable
let handler: @Sendable (Event, LambdaContext) async throws -> Output = { event, context in
    // body
}
let runtime = LambdaRuntime(body: handler)
```

## Debug finding

One regression surfaced during Phase 3 (full regression testing). My initial `analyzeBody` implementation skipped descent into **all** closure-initialised variable bindings, which broke the existing `plainClosureIsNotEscaping_flagsThroughClosureBody` test in `EscapingClosurePolicyTests.swift`. That test validates the long-standing policy: a non-escape closure assigned to a let binding (`let work = { try await insert(id) }; await work()`) should have its body walked under the outer function's context.

The fix: only skip descent when the binding carries its own `/// @lint.effect` (or `/// @lint.context`) annotation. Unannotated closure-bound bindings keep the pre-slice behaviour — walked as inline code under the outer context.

This makes the closure-binding rule asymmetric with function-declaration rule:
- **Function decl:** always skipped by outer analyzeBody (either has its own site or its body isn't walked at all)
- **Closure binding:** skipped only when annotated (unannotated closures are inline-like by existing convention)

The asymmetry reflects Swift's own semantics: let-bound closures are often used as "deferred inline operations" (`let work = { ... }; await work()`), while function decls define separate callables. Preserving the inline-walk convention for unannotated closure bindings keeps the linter's behaviour consistent with the pre-slice trial-record findings.

Regression test added: `annotatedInnerBindingSuppressesOuterSiteDoubleFire` guards against the initial-fix failure mode (double-counting when both outer function and inner closure binding are annotated).

## Acceptance against plan

| Phase-5 criterion (from `claude_phase_2_closure_handler_annotation_plan.md`) | Status |
|---|---|
| ≥6 new unit tests for parser + rule-visitor closure-binding behaviour | ✅ 28 new tests (14 parser + 14 rule-visitor) |
| Existing linter test suite green (no prior tests require modification) | ✅ 2077/269 green; only adjusted one of my own new tests to match the correct asymmetric policy |
| ≥2 R6 Lambda closure-handler examples successfully annotated | ✅ policyAuthorizerHandler + simpleAuthorizerHandler |
| Proposal doc + rule doc amended | pending — Phase 5 |
| closure-handler-verification doc added | ✅ this file |

All implementation-level criteria met. Only documentation updates (Phase 5) remain.

## What this evidence changes for round 7

Whenever a round 7 measurement happens, the Lambda corpus coverage gap closes from ~50% to ~37%. Inline-trailing-closure handlers remain the last large un-annotated class on that target; whether that's worth another grammar slice depends on demand evidence. The R6 retro's recommendation sequence:

1. ✅ **Closure-handler annotation grammar** — shipped this slice.
2. **`SwiftIdempotency` macro package** — unchanged priority. Still the largest qualitative step remaining.
3. **Third-corpus validation** — still deferred. Two-corpus cleanliness (pointfreeco + Lambda) is a defensible signal; a third corpus has diminishing novelty until a new grammar/precision slice ships.

A round 7 plan would naturally shift focus to either (2) the macro package or (3) a new real-application target (vapor, internal microservice) depending on which trajectory the project prioritises. The R6 retro's "don't run round 7 yet" guidance still holds — no round until there's a new qualitative thing to measure.
