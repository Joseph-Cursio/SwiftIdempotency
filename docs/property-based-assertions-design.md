# Property-Based Idempotency Assertions — `SwiftIdempotencyPropertyBased` (design note)

**Status:** **W6.A + W6.C shipped (v0.4.0); W6.B rejected.**
`SwiftIdempotencyPropertyBased` ships `assertIdempotentProperty(over:)` (W6.A)
and `assertIdempotentEffectsProperty(over:makeRun:)` (W6.C). **W6.B (a corpus
for hand-written property tests) is rejected:** `swift-property-based` already
provides `FixedSeedTrait` / `.fixedSeed(_:)` — its own seed-based replay for
re-running a failing property — so a custom corpus would duplicate it, and
sharing SwiftInfer's corpus is a wrong-direction cross-repo dependency (plus the
seed-model mismatch noted below). The replay idiom for these tests is
`@Test(.fixedSeed("…"))`. Companion to SwiftInferProperties'
*Minimal-Counterexample & Replay-Corpus* epic
(`SwiftInferProperties/docs/v1.141 Calibration Plan.md`, workstream W6).

> **Shipped note (W6.A).** Simpler than the original sketch below: the shrinking
> comes from `swift-property-based`'s own `propertyCheck` (which generates inputs
> **and** shrinks), so W6.A needs **only** a `swift-property-based` dep — *not*
> `PropertyLawKit`/`Seed`/the v2.6 kit shrinker. The shipped signature is
> `assertIdempotentProperty(over generator: Generator<Input, _>, count: Int = 100, _ operation: (Input) async throws -> Result) async`;
> it records a Testing issue via `#expect` (non-fatal) so a failing property is
> shrunk to the minimal input — the gap `PropertyBasedAssertIdempotentTests`
> documented. The `Seed`/`Environment`/corpus machinery below is W6.B (deferred);
> note the verify corpus uses SwiftInfer's own `SeedHex`, not SwiftPropertyLaws'
> `Seed` (see the v1.141 plan's v1.143 correction), so W6.B's corpus reuse needs
> revisiting against that reality.

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
machinery (SwiftPropertyLaws `v2.6` + SwiftInfer's `.swiftinfer/verify-corpus.json`)
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
invokes the kit's `v2.6` shrinker to report the **minimal** failing `x`.

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

### W6.B — minimal + replayable — **REJECTED**

> Not built. Shrinking already comes from `propertyCheck` (W6.A/C surface the
> minimal failing input/sequence). The persistence half is rejected:
> `swift-property-based`'s `FixedSeedTrait` (`.fixedSeed(_:)`) already replays a
> failing property from its seed — a custom corpus would duplicate it; it doesn't
> expose the failing seed/minimal programmatically for auto-persistence (would
> need forking the runner); reconstructing a typed input from a stored string is
> infeasible; and "share SwiftInfer's `.swiftinfer/verify-corpus.json`" is a
> wrong-direction cross-repo dependency *and* a seed-model mismatch (SwiftInfer's
> corpus stores its own `SeedHex`, not SwiftPropertyLaws' `Seed`). Replay idiom
> for these tests: `@Test(.fixedSeed("…")) func …`. The original sketch follows
> for the record.

- On failure, surface the shrunk value (from `v2.6`'s shrink-aware backend), not the
  first failing one.
- Persist `{ seed (base64), counterexample, environment }` to the **same**
  `.swiftinfer/verify-corpus.json` schema SwiftInfer v1.143 defines, reusing
  `Seed` (stateA–D / base64) and `Environment` (swiftVersion / backendIdentity /
  generatorSchemaHash) verbatim. A hand-written property test thus shares one corpus
  with SwiftInfer-generated ones.
- Corpus-first replay, `Environment`-guarded (skip-with-note on
  `ReplayEnvironmentMismatch`, never spurious-fail across toolchain skew).

### W6.C — effect-sequence assertion (seed of model-based testing) — **SHIPPED**

Shipped as `assertIdempotentEffectsProperty(over:makeRun:)`: generates action
sequences, builds a fresh system per trial via `makeRun` (returning the
`IdempotentEffectRecorder`s + an `apply` closure), applies the sequence **twice**
(the retry), and asserts the second pass adds no new effects (compares
`_snapshotBox()` snapshots). On divergence, `swift-property-based`'s array
shrinker minimizes to the smallest action sequence that breaks effect-idempotence.
Failures record a Testing issue (non-fatal) so they compose with the shrinker.
(No seed persisted — see W6.B; `.fixedSeed` is the replay idiom.) Full
stateful/model-based testing remains SwiftInfer epic #2.

## Interop with SwiftInferProperties

- **Correction (v1.142):** the auto-bridge does **not** emit `#assertIdempotent`
  from a SwiftInfer idempotence counterexample. The two are *different
  properties*: `#assertIdempotent { body }` asserts `body() == body()` —
  **retry** idempotence (a closure called twice yields the same result/effects) —
  whereas SwiftInfer's idempotence template is **algebraic** `f(f(x)) == f(x)`.
  `#assertIdempotent { f(x) }` would pass for a pure `f` and miss an algebraic
  counterexample. SwiftInfer's auto-bridge therefore emits the generic
  `ConvertCounterexampleEngine` stub (which correctly asserts `f(f(x)) == f(x)`).
  This product (`SwiftIdempotencyPropertyBased`) serves the *retry* notion — its
  own concern — not SwiftInfer's algebraic template.
- Attribute grammar is unchanged: SwiftEffectInference's `EffectAnnotationParser`
  keeps matching `@Idempotent` / `@NonIdempotent` / `@Observational` /
  `@ExternallyIdempotent(by:)` by string. No macro renames.

## Non-goals

- No change to the core fixed-input `#assertIdempotent` semantics or its deps.
- No production-runtime instrumentation (already out of scope).
- No auto-injected mocks / DI; adopters still own test isolation.
- Full stateful/model-based generation beyond W6.C's minimal seed.

## Dependency / sequencing

Depends on SwiftPropertyLaws `v2.6` (shrinking) and SwiftInfer v1.143 (corpus schema /
`Seed`/`Environment` reuse). Can ship in parallel with SwiftInfer v1.142–v1.144.
Semver: target **v0.4.0** (no milestone/calibration convention in this repo;
releases tagged post-hoc per feature, as with 0.2.0 Fluent / 0.3.0 effect recorders).

## Tests

`SwiftIdempotencyPropertyBasedTests` (Swift Testing): generated-input pass/fail;
shrinker reports minimal counterexample (metamorphic: still fails, ≤ input,
terminates); corpus round-trip (persist → replay reproduces same counterexample);
`Environment` mismatch skips rather than fails; `@IdempotencyTests(inputs:)`
expansion via `SwiftSyntaxMacrosTestSupport`.
