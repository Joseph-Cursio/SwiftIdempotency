# Methodology note: annotation-candidate surveys during trial Phase 0

**Status.** Lesson learned, not an idea or a bug. Distilled from a small but real survey miss during round-6 Phase 0 that almost silently distorted the round's "annotatable surface" count. Saved here so future trial rounds have a checklist to consult before writing the grep.

## What went wrong

Round 6's Phase 0 needed to enumerate every user-facing Lambda handler in `swift-aws-lambda-runtime`'s `Examples/` tree so that Run B could annotate them all with `/// @lint.context replayable`. I wrote:

```
grep -rn "^\s*(public |mutating |)func handler\(" Examples/ --include="*.swift"
```

This used a whitelist of modifier keywords (`public`, `mutating`, empty-string-for-no-modifier) and anchored on them. The survey returned 2 results.

Post-round, while validating the closure-handler slice, I noticed `ServiceLifecycle+Postgres/Sources/Lambda.swift` contains:

```swift
/// Function handler. This code is called at each function invocation
/// input event is ignored in this demo.
private func handler(event: APIGatewayV2Request, context: LambdaContext) async throws -> APIGatewayV2Response {
    // ...
}
```

`private` wasn't in the alternation. The grep silently skipped it. The round-6 scope doc recorded 9 annotatable handlers when the true count was 10.

## Why this is worth writing down

- **The error is silent.** The grep produced numeric output that looked reasonable. Nothing warned that the alternation was incomplete.
- **Trial findings quote surface percentages.** R6's retrospective reported "~50% of the Lambda example surface is un-annotatable." With the missed `private func handler`, the real figure was ~47%. Not a huge delta in this instance, but the same mistake on a larger codebase could meaningfully distort the adoption-friction narrative.
- **The survey is the input to the round, not a sanity check after.** A miss at Phase 0 propagates through Run A, B, C, and Phase-7 writeup before it's caught. There's no downstream validator.

## The rule

**Trial-survey greps should match the raw signature and filter exclusions, not whitelist modifier keywords.**

Swift methods and functions have a wide modifier surface: `public`, `private`, `fileprivate`, `internal`, `open`, `package`, `static`, `class`, `final`, `mutating`, `nonmutating`, `override`, `dynamic`, `lazy`, plus attribute stacks (`@inlinable`, `@discardableResult`, `@Sendable`, `@MainActor`, `@available`, `@_spi`, custom attributes) and combinations thereof. A modifier-alternation grep is guaranteed to miss something; the only question is which.

Better shape: match the bare signature and filter out the things you don't want.

```
# Good: match the signature, then filter
grep -rn "func handler\(" Examples/ --include="*.swift" \
  | grep -v "/Tests/" \
  | grep -v "/Benchmarks/"
```

Or, for multi-candidate surveys (e.g. both `handle` and `handler` as entry-point method names):

```
grep -rnE "func (handle|handler|run|perform|process)\(" Examples/ --include="*.swift"
```

## Phase 0 checklist

Before writing the grep:

1. **List candidate identifiers.** For Lambda: `handle`, `handler`. For Vapor: `handle`, `handler`, `respond`. For webhook handlers: `handle<Event>`, `process<Event>`, `on<Event>`. Mining the README or a Finder pass over the repo's `Examples/` / `Sources/` first is cheaper than iterating the grep.
2. **Grep the raw signature.** No modifier alternation in the main pattern. Modifiers appear as a prefix before the `func` keyword; match everything with `func name(` as the anchor and handle modifiers via separate exclusion filters.
3. **Filter exclusions explicitly.** `grep -v /Tests/`, `grep -v /Benchmarks/`, `grep -v Fixtures/`, etc. Make the exclusion list visible in the scope doc.
4. **Cross-check against an independent signal.** Count files in `Examples/` or wherever the survey anchors, and sanity-check that the handler count is in the right ballpark. A zero-handler file is a normal result; a zero-handler directory is a smell.
5. **Identify closure-based shapes separately.** `let name: Type = { ... }`, `let name = { ... }`, `var name = { ... }`, and inline `LambdaRuntime { ... }` are all different annotatable / un-annotatable shapes. A survey that only greps `func` leaves those invisible.

## What goes in the scope doc

The scope doc already records "annotation survey" as part of Phase 0. Add an explicit block:

```markdown
### Annotation-candidate survey

Command used:
```
grep -rnE "func (handle|handler)\(" Examples/ --include="*.swift" \
  | grep -v /Tests/
```

Candidates found: N.

Exclusions applied and why:
- `/Tests/` — test fixtures; not user-facing handlers
- `/Benchmarks/` — not production code paths
```

This makes the survey reproducible and auditable. A reviewer (or a later you) can re-run the exact command and verify the count.

## Candidate tooling

Not a priority, but worth noting as a future convenience:

- A small script under `Scripts/` in the linter repo that takes a corpus path + pattern + exclusion list and returns a canonical survey report. Reproducible, version-controlled, cite-able by scope docs.
- The script could double as the Phase 0 invocation and as a regression check post-trial — re-run and compare against the scope doc's recorded count.

Out of scope until the problem recurs.

## Trigger for tooling work

Promote this from a methodology note to a tooling change when one of:

1. A second round has a survey miss caught post-facto. (R6 was the first; another instance would argue for automation.)
2. A round's scope grows beyond one target corpus and the manual survey becomes too expensive.
3. A regression comparison between rounds becomes useful — e.g. if we want to know whether `swift-aws-lambda-runtime 3.0` added new un-annotatable handlers relative to `2.8.0`, a canonical survey script makes that a one-liner.

Until then: keep the manual grep, but write it using "match-then-filter" form and record the exact command in the scope doc.

## Related

- Round-6 scope doc: [`../phase2-round-6/trial-scope.md`](../phase2-round-6/trial-scope.md) — the survey section from R6 that missed `private func handler`.
- Round-6 retrospective: [`../phase2-round-6/trial-retrospective.md`](../phase2-round-6/trial-retrospective.md) — the "policy notes" section where this methodology lesson will eventually get cited.
- Closure-handler verification doc: [`../phase2-round-6/closure-handler-verification.md`](../phase2-round-6/closure-handler-verification.md) — where the missed candidate was surfaced and the corrected count of 12/19 (~63%) recorded.
