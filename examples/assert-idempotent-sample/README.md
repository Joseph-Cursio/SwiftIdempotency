# AssertIdempotentSample

A minimal end-to-end example of consuming `SwiftIdempotency`'s
freestanding `#assertIdempotent` expression macro from downstream code.

The sample lives at `examples/assert-idempotent-sample/` and depends on
the root `SwiftIdempotency` package via a local path dependency, so
running it exercises the real macro expansion — not a stub.

## What this sample demonstrates

`#assertIdempotent { body }` is the call-site complement to the
function-level `@IdempotencyTests` extension macro. Where
`@IdempotencyTests` generates tests for zero-argument `@Idempotent`
members, `#assertIdempotent` lets a test author freeze a specific
argument binding and check the call under that binding — which is what
most real-world signatures need (they take arguments).

The macro has two overloads, picked by Swift's overload resolution on
the closure body's effects. Each runtime helper is `rethrows`, so the
closure's throwing effect flows through — `try` is present at the call
site only when the closure body can throw:

| Closure shape    | Call-site form                                    |
| ---------------- | ------------------------------------------------- |
| sync, pure       | `let r = #assertIdempotent { ... }`               |
| sync, throwing   | `let r = try #assertIdempotent { try ... }`       |
| async, pure      | `let r = await #assertIdempotent { await ... }`   |
| async, throwing  | `let r = try await #assertIdempotent { try await ... }` |

The runtime helper invokes the closure twice and `precondition`s that
the two return values are equal under `==`. The expression's return
value is the first invocation's result, so assignments read naturally.

Core files:

- `Sources/AssertIdempotentSample/OrderTotaliser.swift` — a pure API
  with sync, async, and throwing forms.
- `Tests/AssertIdempotentSampleTests/AssertIdempotentTests.swift` —
  four `#assertIdempotent` call sites covering every row of the effect
  matrix, plus a **commented-out block** showing what a non-idempotent
  closure looks like.

## What the negative case looks like

The test file's trailing comment block shows a counter-capturing
closure — `var counter = 0; return { counter += 1; counter }` — that
returns `1` on the first invocation and `2` on the second. Uncomment
the block to see the macro's runtime `precondition` fire:

```
#assertIdempotent: closure returned different values on re-invocation — not idempotent
```

This is a **runtime** check, not a compile-time one. Compile-time
enforcement of call-site argument stability is the linter's job
(`SwiftProjectLint`'s `idempotencyViolation` / `missingIdempotencyKey`
rules). The macro handles the dynamic half — observing the actual
return values during a test run.

## Type constraint

The macro is generic over `Result: Equatable`. A closure returning a
non-`Equatable` type won't type-check — that's a standard Swift
overload-resolution error, not a macro diagnostic. Adapt by returning
a derived `Equatable` witness (e.g. a hash, a serialised form, or a
`String` description) from the closure.

## Running

```bash
cd examples/assert-idempotent-sample
swift test
```

The package uses a path dependency on `../..`, so the tests reflect
the current state of the root `SwiftIdempotency` package you're sitting
on — no version pin to drift.

## Scope

This sample covers `#assertIdempotent` end-to-end in a consumer
context. A companion `examples/idempotency-tests-sample/` covers
`@IdempotencyTests`, and `examples/webhook-handler-sample/` covers the
`IdempotencyKey` strong type. The attribute macros (`@Idempotent` /
`@NonIdempotent` / `@Observational` / `@ExternallyIdempotent`) are
exercised by the root package's own test target and by the adopter
road-tests under `docs/<slug>/`.

## Relationship to `@IdempotencyTests`

Same underlying contract — re-invoke + compare. Different ergonomics:

- `@IdempotencyTests` is stanza-level. Annotate a `@Suite` type once,
  add zero-arg `@Idempotent` members, and get one generated test per
  member. Lowest-boilerplate path for functions that take no arguments.
- `#assertIdempotent` is call-site. Write an ordinary `@Test`, pick a
  specific argument binding, and assert that call at that binding is
  idempotent. The form real-world code usually needs.

The two can coexist in the same test suite — pick whichever matches
the shape of the code under test.
