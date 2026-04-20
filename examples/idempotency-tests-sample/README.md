# IdempotencyTestsSample

A minimal end-to-end example of consuming `SwiftIdempotency`'s
`@IdempotencyTests` extension macro from downstream code.

The sample lives at `examples/idempotency-tests-sample/` and depends on
the root `SwiftIdempotency` package via a local path dependency, so
running it exercises the real macro expansion — not a stub.

## What this sample demonstrates

`@IdempotencyTests` is attached to a `@Suite` type. The macro scans the
type's members for `@Idempotent`-marked zero-argument functions and emits
one `@Test` method per match in a generated extension. Each emitted test
calls the wrapped function twice and `#expect`s the two return values
are equal.

None of the generated test methods are written by hand. They are produced
by the extension-role macro on compilation, and Swift Testing picks them
up as ordinary `@Test` declarations in a generated extension.

Core files:

- `Sources/IdempotencyTestsSample/PricingCalculator.swift` — a tiny
  pure-function library the test suite exercises.
- `Tests/IdempotencyTestsSampleTests/IdempotencyContractTests.swift` —
  the `@Suite @IdempotencyTests` type with three `@Idempotent` members
  covering the sync, async, and throwing-return effect-matrix branches.

## What the macro generates

For an annotated suite of three `@Idempotent` members, the macro emits
an extension containing three generated `@Test` methods, one per
member — in this sample:

- `testIdempotencyOfSystemStatusIsHealthy()` — sync target.
- `testIdempotencyOfPricingForFiveKilos()` — sync target with a value
  return.
- `testIdempotencyOfAsyncStatusProbe()` — async target, exercising the
  effect-matrix branch that emits `await` on both the outer helper call
  and the inner invocation.

Running `swift test` produces 5 passing tests total: 3 macro-generated
tests plus 2 hand-written sanity checks.

## What the macro skips

The test file's trailing comment block shows two patterns the macro
deliberately ignores — parameterised members and un-marked members.
Uncommenting that block doesn't add new generated tests; it just
confirms the filter does what it says.

## Running

```bash
cd examples/idempotency-tests-sample
swift test
```

The package uses a path dependency on `../..`, so the tests reflect
the current state of the root `SwiftIdempotency` package you're sitting
on — no version pin to drift.

## Scope

This sample covers `@IdempotencyTests` end-to-end in a consumer context.
A companion `examples/assert-idempotent-sample/` covers the freestanding
`#assertIdempotent` expression macro. The attribute macros
(`@Idempotent` / `@NonIdempotent` / `@Observational` /
`@ExternallyIdempotent`) and `IdempotencyKey` are exercised by the root
package's own test target, the adopter road-tests under `docs/<slug>/`,
and the sibling `examples/webhook-handler-sample/`.

## Relationship to the linter

`SwiftProjectLint`'s idempotency rules recognise `@Idempotent` as
equivalent to `/// @lint.effect idempotent`. A member that carries
`@Idempotent` declares its effect for both the macro (test generation)
and the linter (call-site verification). Same token, two consumers.
