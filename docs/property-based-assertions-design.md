# Property-Based Idempotency Assertions — `SwiftIdempotencyPropertyBased` (design note)

**Status:** proposed (target v0.4.0). Companion to SwiftInferProperties'
*Minimal-Counterexample & Replay-Corpus* epic
(`SwiftInferProperties/docs/v1.141 Calibration Plan.md`, workstream W6).

## Problem

Today `#assertIdempotent { … }` and `@IdempotencyTests` run the target **twice on
one fixed value** and compare with `==`:

- `#assertIdempotent` → `__idempotencyAssertRunTwice` / `__idempotencyAssertRunTwiceAsync`
- `@IdempotencyTests` → `__idempotencyInvokeTwice` per zero-arg `@Idempotent` member
- `assertIdempotentEffects(recorders:body:)` → double-invoke `body`, compare `IdempotentEffectRecorder.snapshot()`

There is **no input generation**: a fixed-input test proves `f(f(c)) == f(c)` for a
single `c`, not for the input space. `swift-property-based` is currently a
**test-only** dependency of `SwiftIdempotencyTests`; adopters never get it. REFERENCE.md
§Deferred already lists "property-based test generation / `IdempotencyTestInputProvider`"
and "parameterised `@IdempotencyTests` expansion" as not-shipped.

Separately, when a counterexample *is* found, it is a `precondition`/`Issue.record`
string — not minimal, not replayable. The ecosystem's shrinking + replay-corpus
machinery (SwiftPropertyLaws `v2.4` + SwiftInfer's `.swiftinfer/verify-corpus.json`)
exists but is unreachable from a hand-written `#assertIdempotent` test.

## Goal

Give adopters who *want* it: generated inputs → N trials → on failure, the
**minimal** counterexample (shrinking) → persisted **replayable** seed, re-checked
first on every run. Adopters who don't want it keep the lean, dependency-light core
exactly as-is.

## Design — a new opt-in product (the `SwiftIdempotencyFluent` pattern)

Mirror the existing opt-in precedent: `SwiftIdempotencyFluent` adds a FluentKit dep
that only adopters who declare it pay for. Add:

```swift
.library(name: "SwiftIdempotencyPropertyBased",
         targets: ["SwiftIdempotencyPropertyBased"]),
```
```swift
.target(
    name: "SwiftIdempotencyPropertyBased",
    dependencies: [
        "SwiftIdempotency",
        .product(name: "PropertyBased", package: "swift-property-based"),
        // corpus + Seed/Environment reuse — added once SwiftInfer v1.143 lands:
        .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
    ]),
```

`swift-property-based` graduates from test-only to a real dep **of this target
only**. The core `SwiftIdempotency` / `SwiftIdempotencyTestSupport` targets are
untouched — their dependency footprint and the fixed-input `#assertIdempotent`
semantics stay identical.

### W6.A — generated-input assertion

A property-based sibling to `__idempotencyAssertRunTwice`. Adopter supplies (or has
derived) a generator; the helper runs N trials of `f(f(x)) == f(x)`, and on failure
invokes the kit's `v2.4` shrinker to report the **minimal** failing `x`.

```swift
// SwiftIdempotencyPropertyBased
public func assertIdempotentProperty<Input, Result: Equatable>(
    over generator: Generator<Input, some SendableSequenceType>,
    trials: TrialBudget = .standard,
    seed: Seed? = nil,
    _ f: @Sendable (Input) async throws -> Result
) async rethrows
```

Optional `@IdempotencyTests(inputs:)` mode: for non-zero-arg `@Idempotent` members,
expand to `assertIdempotentProperty` instead of skipping them (closes REFERENCE.md's
"parameterised expansion" deferral). Zero-arg members keep the existing
double-invoke expansion.

### W6.B — minimal + replayable

- On failure, surface the shrunk value (from `v2.4`'s shrink-aware backend), not the
  first failing one.
- Persist `{ seed (base64), counterexample, environment }` to the **same**
  `.swiftinfer/verify-corpus.json` schema SwiftInfer v1.143 defines, reusing
  `Seed` (stateA–D / base64) and `Environment` (swiftVersion / backendIdentity /
  generatorSchemaHash) verbatim. A hand-written property test thus shares one corpus
  with SwiftInfer-generated ones.
- Corpus-first replay, `Environment`-guarded (skip-with-note on
  `ReplayEnvironmentMismatch`, never spurious-fail across toolchain skew).

### W6.C — effect-sequence assertion (seed of model-based testing)

Extend `assertIdempotentEffects` / `IdempotentEffectRecorder` the same way: generate
*sequences* of operations, run `body` over them, and on divergence shrink to the
**minimal operation sequence** that breaks effect-idempotency; persist its seed.
Keep this minimal here — full stateful/model-based testing is SwiftInfer epic #2,
not this note.

## Interop with SwiftInferProperties

- SwiftInfer v1.142's auto-bridge, when the target package depends on
  `SwiftIdempotency`, emits a `#assertIdempotent`-based regression rather than a
  bespoke `Tests/Generated/SwiftInfer/` stub — so the durable artifact uses the
  adopter's own macro. With this product present, that regression can be the
  property-based form seeded by the shrunk counterexample.
- Attribute grammar is unchanged: SwiftEffectInference's `EffectAnnotationParser`
  keeps matching `@Idempotent` / `@NonIdempotent` / `@Observational` /
  `@ExternallyIdempotent(by:)` by string. No macro renames.

## Non-goals

- No change to the core fixed-input `#assertIdempotent` semantics or its deps.
- No production-runtime instrumentation (already out of scope).
- No auto-injected mocks / DI; adopters still own test isolation.
- Full stateful/model-based generation beyond W6.C's minimal seed.

## Dependency / sequencing

Depends on SwiftPropertyLaws `v2.4` (shrinking) and SwiftInfer v1.143 (corpus schema /
`Seed`/`Environment` reuse). Can ship in parallel with SwiftInfer v1.142–v1.144.
Semver: target **v0.4.0** (no milestone/calibration convention in this repo;
releases tagged post-hoc per feature, as with 0.2.0 Fluent / 0.3.0 effect recorders).

## Tests

`SwiftIdempotencyPropertyBasedTests` (Swift Testing): generated-input pass/fail;
shrinker reports minimal counterexample (metamorphic: still fails, ≤ input,
terminates); corpus round-trip (persist → replay reproduces same counterexample);
`Environment` mismatch skips rather than fails; `@IdempotencyTests(inputs:)`
expansion via `SwiftSyntaxMacrosTestSupport`.
