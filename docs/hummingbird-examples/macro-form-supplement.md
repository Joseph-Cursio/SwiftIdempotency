# hummingbird-examples / todos-fluent — Macro-Form Supplement

Macro-form variant of the primary round (see [`trial-scope.md`](trial-scope.md)).
Exercises the `SwiftIdempotency` package's attribute-form annotations
end-to-end on the same adopter and answers completion criterion #3
from [`../road_test_plan.md`](../road_test_plan.md): "at least one
adopter has exercised the attribute-form annotations end-to-end and
produced identical linter output to the doc-comment form."

## What this supplement adds

1. **Adopter dependency.** `SwiftIdempotency` added as a local-path
   dependency to `todos-fluent/Package.swift` + `SwiftIdempotency`
   product listed in the `App` target's dependencies.
2. **Attribute-form annotation.** `TodoController` gains a
   `private func recordAuditEvent(_:)` helper marked `@NonIdempotent`
   (attribute form). The `create` handler (still declared
   `@lint.context replayable` by doc-comment — context annotations
   have no macro equivalent in the current package) calls the helper
   after persisting the todo.
3. **Two scans.** One with `@NonIdempotent` attribute, one with the
   equivalent `/// @lint.effect non_idempotent` doc-comment. Outputs
   diffed.

## Build validation

`swift build` on todos-fluent with the new dependency completes
cleanly (~103s cold, including `SwiftIdempotency` and its `swift-syntax
602.0.0` transitive dep). The macros plugin loads; attribute
expansion succeeds; `App` module links. Proves the macros package is
consumable via SPM in a realistic adopter graph (Hummingbird 2 +
Fluent + SQLite + swift-argument-parser).

## Linter scan comparison

Both scans produce **4 diagnostics** (3 Fluent catches carried from
the primary round + 1 new catch on `recordAuditEvent`). Transcripts:

- [`trial-transcripts/macro-form-attribute.txt`](trial-transcripts/macro-form-attribute.txt) — `@NonIdempotent` attribute form
- [`trial-transcripts/macro-form-doccomment.txt`](trial-transcripts/macro-form-doccomment.txt) — `/// @lint.effect non_idempotent` doc-comment form

Diffing the two transcripts reveals **line numbers only** — the
doc-comment form has fewer surrounding lines of helper scaffolding
so subsequent call sites shift up by 4 lines. Every rule name,
callee name, diagnostic message, and suggestion is byte-identical
after normalising line numbers.

The diagnostic prose for the `recordAuditEvent` catch is:

> `'create' is declared \`@lint.context replayable\` but calls
> 'recordAuditEvent', which is declared \`@lint.effect non_idempotent\`.`

The "declared `@lint.effect non_idempotent`" phrasing is identical
across both forms — the linter normalises the attribute token to
its doc-comment equivalent in the prose. Adopters can switch between
forms freely; linter output does not reveal which was used.

## What this does not cover

Three macros in the package are **not** exercised by this supplement
and remain road-tested only by `SwiftIdempotency`'s own unit tests:

1. `@IdempotencyTests` — the extension macro that auto-generates
   `@Test` methods for zero-arg `@Idempotent`-marked members. Not
   applicable here because `TodoController`'s methods all take
   `Request` / `Context` arguments. A handler-layer adopter is the
   wrong shape for this macro.
2. `#assertIdempotent { ... }` — the freestanding expression macro
   for test sites. Useful but requires writing non-trivial test
   fixtures (synthetic Hummingbird requests, decoding responses
   into Equatable types) that are out of scope for a measurement
   round. Defer to a purpose-built integration sample or a
   subsequent round with an adopter whose test suite already exists
   at the right granularity.
3. `IdempotencyKey` — the compile-time strong type. Would need an
   adopter method taking an `idempotencyKey: IdempotencyKey`
   parameter to exercise. Not a natural fit for this adopter;
   `@ExternallyIdempotent(by:)` + `IdempotencyKey` are best validated
   together on a payment/webhook adopter, not a todos CRUD app.

These three are named follow-ons. None are adoption-blocking for
the four-framework coverage goal — the linter-recognition path
(this supplement) is the one that validates the macros package
actually interops with the rule suite.

## Net

Completion criterion #3 from the road-test plan is satisfied:
attribute-form and doc-comment form produce byte-identical linter
diagnostics modulo source line numbers. The macros package
compiles as an adopter dependency and its `@NonIdempotent` attribute
is recognised equivalently to `/// @lint.effect non_idempotent`.
`@Idempotent`, `@Observational`, `@ExternallyIdempotent(by:)` share
the same recognition pathway in the linter (same
`EffectAnnotationParser` — see `SwiftProjectLintVisitors`) and are
assumed to behave equivalently; dedicated supplements for each can
be added if a future finding suggests otherwise.

## Data committed

- `docs/hummingbird-examples/macro-form-supplement.md` — this document
- `docs/hummingbird-examples/trial-transcripts/macro-form-attribute.txt`
- `docs/hummingbird-examples/trial-transcripts/macro-form-doccomment.txt`

Adopter-side edits (`Package.swift` dep + `TodoController` helper)
remain on the local `trial-fluent-verify` branch of
`hummingbird-examples`, not pushed. Revert with
`git checkout main -- .` on that clone.
