# Implementation Plan: Phase 5 — `SwiftIdempotency` Macros Package

Largest single piece of work the proposal has scoped. New Swift package, new repo, separate from the linter. Consumes the annotation surface the linter reads; adds compile-time type enforcement and test-time scaffolding the linter cannot produce.

Fourth implementation plan in this repo (after receiver-type-inference, closure-handler-annotation, and OI-3 residual). First plan whose deliverable is not an edit to the existing linter.

## Why this is the right next work

Six rounds of trial evidence have validated the linter's precision profile across two corpora (pointfreeco, swift-aws-lambda-runtime) and three code styles (function-decl, closure-bound, stored-property). Every named residual from those rounds is closed. The Open Issues list is down to OI-1 (rule-scope design question) and OI-8 (adopter-evidence-gated). There's nothing left to measure in the linter half that would meaningfully change its adoption story.

The macros package is what makes the *next qualitative step-change* possible:

- **Compile-time type enforcement.** `IdempotencyKey` as a strong type makes `UUID()`-as-idempotency-key a compile error, not a lint diagnostic. Stronger than any heuristic.
- **Test-time verification.** `@Idempotent` peer-macro-generated tests that call the annotated function twice with the same key and assert observable equivalence. A qualitatively different check than static analysis can produce.
- **Shared source of truth with the linter.** Once `@Idempotent` / `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent` exist as attributes, macro-emitted code and hand-written code feed the same rule pipeline. The linter reads attribute annotations; macros emit them. No duplication.

R5 and R6 together left the linter "well-built and waiting for users." The macros package raises the ceiling on what those users can do.

## Scope of this plan

**In scope:**

- New Swift package `SwiftIdempotency`, hosted in a new GitHub repo alongside `SwiftProjectLint`. Open-source, SwiftPM distributable, minimum Swift 5.9 (macros landed in 5.9).
- Four annotation attributes: `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`. Each as an attached macro whose primary value is existing as a recognizable attribute name; generated code is Phase 3's concern.
- `IdempotencyKey` strong type with compile-time-enforceable construction paths. Suppresses `UUID()`-style per-invocation generation by typing alone.
- `@Idempotent` peer-macro expansion that emits a companion test function calling the annotated function twice with identical arguments and asserting observable equivalence.
- `#assertIdempotent { body }` freestanding expression macro for call-site-specific idempotency assertions.
- Linter-side extension: `EffectAnnotationParser` reads attribute-form annotations alongside doc-comment-form annotations. Both forms are semantically equivalent; macro-emitted and hand-written code feed the same symbol table.
- Package documentation, example adoption, one cross-repo validation round.

**Out of scope with reasons:**

- **Production-runtime instrumentation.** Macros cannot inject into every call site silently; that requires dynamic instrumentation (swizzling, AOP, proxy objects). Swift intentionally makes this hard. Runtime safety net is test-time + compile-time + static-analysis — not macros-at-production.
- **`strict_replayable` context tier** (the "flag unless you know for sure" opt-in the user and I discussed as a follow-on). Separate slice post-macros, because it depends on `@Idempotent` being a cheap enough annotation to make strict-mode realistic to adopt.
- **Framework-specific integrations.** Vapor request-handler macros, Hummingbird middleware macros, SwiftNIO handler macros — all follow-on work. The base package stays framework-agnostic.
- **Cross-module type resolution for non-`IdempotencyKey` paths.** `UUID()`-at-call-site detection outside the strong-type boundary stays a linter rule (`missingIdempotencyKey`). Extending it to cross-module receiver-type inference is a separate slice.
- **Auto-generated mocks / dependency-injection scaffolding.** The peer-macro test generation assumes functions under test are *testable as-is* (they take their dependencies as parameters or via `@Dependency`-style injection). Making arbitrary functions testable via macro-injected mocks is out of scope.
- **Migration tooling from `/// @lint.effect` to `@Idempotent`.** One-time migration scripts can come later. The two annotation forms coexist indefinitely; teams migrate on their own schedule.

## Design

### Package structure

New repo: `Joseph-Cursio/SwiftIdempotency`. Layout:

```
SwiftIdempotency/
├── Package.swift
├── README.md
├── Sources/
│   ├── SwiftIdempotency/                    — public API (attributes, IdempotencyKey)
│   │   ├── Attributes.swift                 — @Idempotent, @NonIdempotent, etc.
│   │   ├── IdempotencyKey.swift             — the strong type
│   │   └── AssertIdempotent.swift           — runtime check helpers (#assertIdempotent expansion target)
│   ├── SwiftIdempotencyMacros/              — compiler-plugin target (macro implementations)
│   │   ├── IdempotentMacro.swift
│   │   ├── NonIdempotentMacro.swift
│   │   ├── ObservationalMacro.swift
│   │   ├── ExternallyIdempotentMacro.swift
│   │   └── AssertIdempotentMacro.swift
│   └── SwiftIdempotencyTestSupport/         — test runtime (optional test-only dependency)
│       └── IdempotencyAssertion.swift
└── Tests/
    └── SwiftIdempotencyTests/
        ├── AttributeRecognitionTests.swift
        ├── IdempotencyKeyTypeTests.swift
        ├── IdempotentPeerMacroTests.swift
        └── AssertIdempotentMacroTests.swift
```

Three products:

- `SwiftIdempotency` — library target. Users add this to their app dependencies.
- `SwiftIdempotencyMacros` — compiler plugin. Built transitively; not explicitly declared.
- `SwiftIdempotencyTestSupport` — test-only library target. Users add this to test targets for the runtime assertion infrastructure.

### Attribute macros — the annotation surface

Four attached macros. Each takes the `@attached(peer)` role; minimum expansion emits nothing, so the attribute acts as a marker until Phase 3 expansion:

```swift
@attached(peer)
public macro Idempotent() = #externalMacro(module: "SwiftIdempotencyMacros", type: "IdempotentMacro")

@attached(peer)
public macro NonIdempotent() = #externalMacro(module: "SwiftIdempotencyMacros", type: "NonIdempotentMacro")

@attached(peer)
public macro Observational() = #externalMacro(module: "SwiftIdempotencyMacros", type: "ObservationalMacro")

@attached(peer)
public macro ExternallyIdempotent(by keyParameterName: String = "") =
    #externalMacro(module: "SwiftIdempotencyMacros", type: "ExternallyIdempotentMacro")
```

Users annotate:

```swift
@Idempotent
func upsertUser(id: UUID, name: String) { ... }

@ExternallyIdempotent(by: "idempotencyKey")
func sendGiftEmail(for gift: Gift, idempotencyKey: IdempotencyKey) async throws { ... }
```

Equivalent to the existing doc-comment form; the linter treats them identically after the parser extension (Phase 5 of this plan).

### `IdempotencyKey` strong type

Design goals:
1. Cannot be constructed from `UUID()` or other per-invocation sources.
2. Can be constructed from stable upstream identifiers.
3. Is `Hashable`, `Sendable`, `Codable` for practical API use.
4. Round-trips cleanly across serialization (e.g. webhook payloads).

```swift
public struct IdempotencyKey: Hashable, Sendable, Codable {
    public let rawValue: String

    /// From an `Identifiable` entity whose `id` is stable across retries
    /// (a database primary key, a webhook event ID, etc.).
    public init<E: Identifiable>(from entity: E) where E.ID: CustomStringConvertible {
        self.rawValue = String(describing: entity.id)
    }

    /// From a string the caller has audited as stable.
    /// Deliberately explicit label — `fromAuditedString` rather than `init(_:)`
    /// so unchecked call sites are visible in review.
    public init(fromAuditedString source: String) {
        self.rawValue = source
    }

    // NO init() — cannot construct from thin air.
    // NO init(_ uuid: UUID) — UUID is per-invocation.
    // NO init() where called from ResultBuilder / per-call generator.
}
```

`UUID()` passed where `IdempotencyKey` is expected fails at compile time with `cannot convert UUID to IdempotencyKey`. `IdempotencyKey(fromAuditedString: UUID().uuidString)` is still possible — the type can't detect that — but the `fromAuditedString` label makes it visible in code review, and the existing `missingIdempotencyKey` lint rule catches it as a fallback.

### `@Idempotent` peer-macro test generation

`@Idempotent` expands to generate a peer test function:

```swift
// User writes:
@Idempotent
func upsertUser(id: UUID, name: String) async throws { ... }

// Macro expands (simplified):
@Test func testIdempotencyOfUpsertUser() async throws {
    let id = UUID()
    let name = "Test"
    try await upsertUser(id: id, name: name)
    try await upsertUser(id: id, name: name)
    // observable-equivalence assertion — see design sketch
}
```

Observable equivalence — the hard part. Options:

- **Option A: user provides a test-only side-effect sink.** The macro expects the function to accept an observation callback. Explicit, minimal, but verbose for users.
- **Option B: macro expects the function to be testable via dependency-injection.** Functions take their dependencies as parameters or via `@Dependency`-style wrappers; the test runs both invocations with the same test-doubled dependencies and asserts the doubles' captured-call lists are equal.
- **Option C: macro attaches an assertion for "same result and no throw."** Naïve but useful for pure-result functions.

Phase 3 ships **Option C** as the minimum. Tests like `testIdempotencyOfUpsertUser` call the function twice with same args, assert `async throws` doesn't throw a second time, and (for functions with return values) assert identical return values. Doesn't verify full observable equivalence, but catches the class of bug "function errors on second call" (which is common for non-idempotent mistakes).

Options A/B land in follow-up phases of this work or as a separate user-extensibility slice.

### `#assertIdempotent { body }` expression macro

```swift
// User writes:
try await #assertIdempotent {
    try await upsertUser(id: id, name: name)
}

// Macro expands to:
try await _idempotencyAssert_1({ try await upsertUser(id: id, name: name) })
```

Where `_idempotencyAssert_1` runs the closure twice and compares results. Lives in `SwiftIdempotencyTestSupport`.

Simpler than `@Idempotent` peer expansion because it's user-placed — the user picks exactly where to check. Good for testing call chains the peer macro can't easily reach.

### Linter coordination

`EffectAnnotationParser` currently reads doc comments via `combinedDocTrivia(for:)`. Phase 5 of this plan extends it to also scan `AttributeListSyntax` for `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent`. Both signal sources feed the same `DeclaredEffect` enum; rules are unchanged.

Key interaction rules:
- Both attribute and doc-comment present → same tier → silent pass-through (redundant but harmless).
- Both present with conflicting tiers → collision policy (OI-4) withdraws the entry.
- Attribute alone → works like doc comment alone.
- Doc comment alone → works unchanged (backward compat).

## Phases

### Phase 1 — Package scaffold + annotation attributes (≈1 week)

- New GitHub repo, `Joseph-Cursio/SwiftIdempotency`.
- `Package.swift` with three product targets.
- Four `@attached(peer)` macros with empty expansion (marker-only for this phase).
- `Sources/SwiftIdempotency/Attributes.swift` declaring the macros.
- `Sources/SwiftIdempotencyMacros/*.swift` implementing each macro's `PeerMacro` protocol conformance, returning `[]` from `expansion`.
- Unit tests in `AttributeRecognitionTests.swift` verifying the attributes compile and don't emit spurious code.
- README stub.

**Acceptance:** a user adds `SwiftIdempotency` as a dependency, imports the library, annotates `@Idempotent func foo()`, and their code compiles. No behavioural change beyond attribute existence.

### Phase 2 — `IdempotencyKey` strong type (≈1 week)

- `Sources/SwiftIdempotency/IdempotencyKey.swift` with the type per the design section.
- Conformances: `Hashable`, `Sendable`, `Codable`.
- Unit tests: construction from `Identifiable` entity, construction from audited string, JSON round-trip, equality semantics.
- Integration test: `let key: IdempotencyKey = UUID()` produces a compile error.
- Example usage in README.

**Acceptance:** the type compiles, round-trips, and refuses `UUID()`-style construction.

### Phase 3 — `@Idempotent` peer-macro test generation (≈2 weeks)

- Macro implementation: `IdempotentMacro` emits a peer `@Test func testIdempotencyOf<Name>` that calls the annotated function twice with synthesized test arguments.
- Test-argument synthesis: use `Identifiable` / `Codable` conformances to construct realistic inputs, OR accept a protocol that functions can conform to for custom test-argument provisioning.
- Observable-equivalence assertion: Option C (same return value + no throw on second call) for Phase 3. Ship A/B follow-up if evidence demands it.
- Compatible with both `@testable import` + Swift Testing and XCTest usage.
- Unit tests: macro expansion correctness (use `MacroTesting` library), end-to-end test invocations.
- README update.

**Acceptance:** a user annotates `@Idempotent func foo()`, runs `swift test`, and observes an auto-generated `testIdempotencyOfFoo` that executes correctly (passes for genuinely-idempotent functions, fails for non-idempotent ones).

### Phase 4 — `#assertIdempotent` expression macro (≈1 week)

- Freestanding expression macro in `AssertIdempotentMacro.swift`.
- `SwiftIdempotencyTestSupport.IdempotencyAssertion` runtime helper that runs the closure twice and compares results.
- Unit tests: macro expansion, runtime behaviour on idempotent vs non-idempotent closures.
- Documentation showing use in XCTest + Swift Testing contexts.

**Acceptance:** `try await #assertIdempotent { try await foo() }` works in both test frameworks and produces a test failure when the closure is not idempotent.

### Phase 5 — Linter integration (≈0.5 week)

- Extend `EffectAnnotationParser.parseEffect(declaration:)` and `parseContext(declaration:)` (for both `FunctionDeclSyntax` and `VariableDeclSyntax` overloads) to scan attribute lists for `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent`.
- Collision-with-doc-comment semantics: identical tier → pass, conflicting tier → collision-withdrawn.
- Unit tests against both annotation forms individually and together.
- Update `Docs/idempotency-macros-analysis.md` to describe the attribute form as first-class alongside the doc-comment form.
- No new rule; no behavioural change to rule firing.

**Acceptance:** a function annotated `@Idempotent` (attribute only, no doc comment) is treated identically by the linter as one annotated `/// @lint.effect idempotent` (doc comment only, no attribute). Full linter test suite green.

### Phase 6 — Documentation + examples (≈0.5 week)

- Full README in the `SwiftIdempotency` repo with motivation, annotation-surface examples, compile-time enforcement examples, test-generation walkthrough.
- A sample-app repo or directory showing one webhook handler annotated end-to-end with both linter and macros, including a passing and a failing test case.
- Cross-link from the `SwiftProjectLint` README to the `SwiftIdempotency` repo for shared-source-of-truth clarity.
- Update the proposal's Phase 5 section in `idempotency-macros-analysis.md` to reflect the shipped scope.

**Acceptance:** a user landing on either repo's README can follow the adoption path end-to-end in < 30 minutes.

### Phase 7 — Validation round (≈1 week)

Round 7 trial, first cross-package measurement. Target: annotate one representative Lambda handler in `swift-aws-lambda-runtime` (or a pointfreeco webhook) using *only* the attribute form + `IdempotencyKey` + `@Idempotent` peer tests. Measure:

- **Annotation-burden delta.** Attribute form vs doc-comment form — character count, readability, tooling integration.
- **Type-level catch rate.** How many places does `IdempotencyKey` as a type rule out that the linter's `missingIdempotencyKey` rule catches today? (Expectation: almost all of them, making the lint rule a fallback for untyped paths.)
- **Generated-test signal.** Do `@Idempotent`-generated tests pass on genuinely-idempotent functions? Fail on genuinely-non-idempotent ones?
- **False-positive surface.** Any new noise class?

Artefacts under `docs/phase5-round-7/`:
- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md`

**Acceptance:** round 7 produces evidence that the macros package works end-to-end on at least one real codebase with zero noise.

## Acceptance summary

- `Joseph-Cursio/SwiftIdempotency` repo ships, SwiftPM-distributable, green test suite
- Four annotation attributes compile and are linter-recognized
- `IdempotencyKey` type enforced at compile time
- `@Idempotent` auto-generates Option-C-level test scaffolding
- `#assertIdempotent` works in XCTest and Swift Testing
- Linter reads attribute annotations equivalently to doc-comment annotations
- Round 7 trial confirms end-to-end adoption works on one real handler
- Proposal's Phase 5 section updated to reflect shipped scope

## What's not in scope — summarised

| Feature | Status |
|---|---|
| Four attribute macros (`@Idempotent`, etc.) | ✅ in scope |
| `IdempotencyKey` strong type | ✅ in scope |
| `@Idempotent` peer-macro test scaffolding (Option C) | ✅ in scope |
| `#assertIdempotent` expression macro | ✅ in scope |
| Linter extension to read attribute annotations | ✅ in scope |
| Option A/B observable-equivalence (dependency-injected mocks) | ❌ deferred |
| `strict_replayable` context tier | ❌ follow-on |
| Framework-specific macros (Vapor, Hummingbird, SwiftNIO) | ❌ follow-on |
| Production-runtime instrumentation | ❌ structurally out of scope |
| Migration tooling doc-comment → attribute | ❌ not needed (coexist indefinitely) |
| Auto-generated mocks / DI scaffolding | ❌ out of scope |
| Cross-module type resolution beyond `IdempotencyKey` | ❌ separate linter slice |

## Risks

1. **Macro-library API volatility.** `SwiftSyntaxMacros` has evolved across Swift 5.9, 5.10, 6.0. Pin to the lowest supported version; test on Swift 5.9+ in CI.
2. **Test-framework dual support.** Swift Testing and XCTest have different assertion surfaces; Phase 3 / 4 macros need to generate code that works under both. Conditional compilation via `#if canImport(Testing)` is the standard pattern.
3. **Observable-equivalence is a judgment call.** Option C (return-value equality) is the minimum that ships; it's not a full correctness check. Users who want stronger guarantees need to write custom test doubles. Documented as a known limitation.
4. **Peer macro naming collisions.** `testIdempotencyOfFoo` as a generated name collides with a hand-written test of the same name. Document a renaming convention (`testIdempotencyOf<FunctionName>`) and ensure it doesn't clash with Swift Testing's `@Test` name-uniqueness rules.
5. **Linter coordination timing.** If macros ship before the linter's attribute-recognition extension lands, macro users get reduced linter coverage until the linter catches up. Mitigation: land Phase 5 of this plan (linter extension) alongside macros Phase 1 or earlier, so the attribute form works in both tools from day one.
6. **New dependency adoption friction.** The linter requires zero runtime dependencies; macros require a SwiftPM dependency on `SwiftIdempotency`. Teams that don't want the dependency stick with the doc-comment form. Acceptable trade-off — the two annotation forms are equivalent; the dependency buys the strong type and the generated tests, not the annotation.

## Estimated effort

- Phase 1: 1 week (scaffold + attributes)
- Phase 2: 1 week (IdempotencyKey)
- Phase 3: 2 weeks (peer-macro test generation — largest single phase)
- Phase 4: 1 week (`#assertIdempotent`)
- Phase 5: 0.5 week (linter extension)
- Phase 6: 0.5 week (docs + examples)
- Phase 7: 1 week (validation round)
- **Total: 7 weeks, budget 8 with slack.** Matches the 5-8 week estimate from the earlier "when would semantic resolution be worth it" discussion.

Phase 3 is the critical path. If time pressure forces a cut, the fallback is shipping Phases 1 + 2 + 5 + 7 (attributes, type, linter extension, validation) as "Phase 5.1 — annotation + typing" and deferring Phases 3 + 4 as "Phase 5.2 — test-time verification." Phase 5.1 alone is already a meaningful qualitative improvement over the pure-linter state — the type-level enforcement of `IdempotencyKey` is the single highest-leverage piece.

## What a clean Phase 5 ships

1. **The linter and macros share source of truth.** Doc comments and attributes are equivalent annotation forms; teams pick one idiom or mix; the rule system reads both.
2. **`UUID()`-as-idempotency-key is a compile error.** A whole class of missed-idempotency-key bugs is eliminated by typing alone.
3. **Idempotency is a test concern, not just a review concern.** `@Idempotent` functions auto-gain test scaffolding; `#assertIdempotent` is available for ad-hoc checks. CI catches regressions that doc-comment annotations alone cannot.
4. **`strict_replayable` becomes realistic.** Once `@Idempotent` is a cheap one-line attribute, the "annotate everything reached from a replayable context" proposition flips from "annotation campaign tax" to "write it as you go." Strict-mode opt-in (the follow-on discussed earlier) becomes a natural next slice that compounds with Phase 5 rather than competing against it.
5. **Three-tier safety net is complete.** Compile-time (types) + test-time (generated tests) + static-analysis (linter). Production-runtime stays out — but the tests catch what the types miss, and the linter catches what the tests miss.

After this: round 7's trial evidence tells us whether a third corpus (Vapor, internal microservice) is worth running, or whether the macros package is the shipping point the proposal has been building toward. Either outcome is a clean stopping place.
