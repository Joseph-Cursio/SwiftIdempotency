# Historical record: `EffectAnnotationParser` missed `///` doc comments that appeared after attributes

**Status.** **Resolved.** Retained as historical record of the bug's shape and of the scope-discipline reasoning that kept it out of the Phase-1.1 OI-4 commit. The fix — `combinedDocTrivia(for:)` in `EffectAnnotationParser` — collects doc-comment trivia from the declaration's `leadingTrivia` plus every attribute's leading and trailing trivia plus each modifier's leading trivia plus the `funcKeyword` / `bindingSpecifier`'s leading trivia, and routes the union through the trivia-position-agnostic parser. Every annotation-reading site consumes the combined union, so ordering of `///` relative to attributes and modifiers no longer matters. Proposal-doc status tracked at OI-7.

## Origin

Discovered on 2026-04-17 while verifying the Phase-1.1 OI-4 signature-aware collision fix against the round-2 trial's `MemoryPersistDriver.create(key:value:expires:)` case. The fix compiled, all 1853 fixtures passed, and the synthetic regression test for the protocol-method shape fired correctly — but when I ran the linter against the real Hummingbird trial branch with a `/// @lint.context replayable` on the test handler, it produced zero diagnostics.

Flipping the ordering from `@available` → `///` → `func` to `///` → `@available` → `func` made the diagnostic fire. The bug was not in the collision fix; it was in how the annotation parser reaches doc-comment trivia when attributes are present.

This would have silently invalidated the round-2 Run C.1 verification if I hadn't tried the alternative ordering.

## What's broken

`EffectAnnotationParser.parseEffect(leadingTrivia:)` and `parseContext(leadingTrivia:)` are called by both idempotency visitors with `FunctionDeclSyntax.leadingTrivia` — the trivia attached to the function declaration's first token.

When a Swift function is written as:

```swift
@available(hummingbird 2.0, *)
/// @lint.context replayable
public func trialReplayableProtocolMethodCaller<C: Clock>(…) { … }
```

the `///` line is **not** part of `FunctionDeclSyntax.leadingTrivia`. SwiftSyntax attaches it elsewhere — most likely as leading trivia of the modifier token (`public`) or trailing trivia of the attribute node — so `parseContext` never sees it.

When the same function is written as:

```swift
/// @lint.context replayable
@available(hummingbird 2.0, *)
public func trialReplayableProtocolMethodCaller<C: Clock>(…) { … }
```

the `///` line is the leading trivia of the attribute, which is the first token of the function declaration, so it ends up in `FunctionDeclSyntax.leadingTrivia`. Everything works.

## Why this matters

- **Both orderings are idiomatic Swift.** The standard library and swift-nio use attribute-first for platform availability; much Apple sample code puts `///` first; many teams mix. A linter that silently accepts only one ordering fails on real codebases for reasons users will struggle to debug.
- **The failure is silent.** There's no warning. The annotation is simply ignored, and the rule produces no diagnostic where one was expected. Users debugging "why didn't my annotation fire" will check the annotation text, the callee's effect declaration, the collision policy, and the file-discovery path long before suspecting trivia routing.
- **It can invalidate trial results.** Round-2 Run C.1 originally reported zero diagnostics on the `MemoryPersistDriver.create` annotation, and we attributed that to the bare-name collision policy. That attribution was correct — but only by luck, because the `@available` / `///` ordering was the same shape. If we had used `///` first in round 2, the collision finding might still have produced zero diagnostics (for the collision reason) and we would have written off the attribute-ordering issue as non-existent. The Phase-1.1 fix's verification step happened to exercise the opposite shape and surfaced it.

## Reproduction

On branch `idempotency-trial` at or after `519e60c`, in any target:

```swift
/// @lint.effect non_idempotent
func sink() async throws {}

@available(macOS 13.0, *)
/// @lint.context replayable
func handler() async throws {
    try await sink()
}
```

Run `swift run CLI <path> --categories idempotency`. Observed: zero diagnostics. Expected: one `nonIdempotentInRetryContext`.

Swap the last two lines so `///` comes before `@available`, and the diagnostic fires.

## Proper fix (proposed)

The parser call in both visitors reads only `node.leadingTrivia`. A robust fix walks all trivia positions that could plausibly hold a doc comment belonging to the declaration:

1. `FunctionDeclSyntax.leadingTrivia` — covers the `///` → attribute → func ordering (already works).
2. Each attribute's own leading and trailing trivia (`node.attributes.forEach`) — covers the attribute → `///` → func ordering.
3. Optionally, leading trivia of the first modifier token (`node.modifiers.first?.leadingTrivia`) — covers attribute → modifier → `///` → func (unusual, but legal).

A small helper that concatenates trivia from all these sources into one `Trivia` and passes that to `EffectAnnotationParser` would fix the bug in both visitors simultaneously. The parser itself doesn't need to change — it already walks a `Trivia` looking for `docLineComment` / `docBlockComment` pieces.

Rough sketch:

```swift
// In the visitor, where parseEffect/parseContext is currently called:
let combinedTrivia: Trivia = node.attributes.reduce(node.leadingTrivia) { acc, attribute in
    acc + attribute.leadingTrivia + attribute.trailingTrivia
}
let effect = EffectAnnotationParser.parseEffect(leadingTrivia: combinedTrivia)
let context = EffectAnnotationParser.parseContext(leadingTrivia: combinedTrivia)
```

The same treatment is needed inside `EffectSymbolTable.merge(source:)`, which reads leading trivia of collected `FunctionDeclSyntax` nodes the same way.

## Why it wasn't fixed in the Phase-1.1 commit

The Phase-1.1 commit had a single-purpose charter — OI-4's signature-aware collision policy. The round-2 trial retrospective (`phase1-round-2/trial-retrospective.md`) explicitly praised the "no rule changes on the trial branch" scope-discipline rule. Adding an unrelated bug fix — even a small and clean one — to the same commit would have re-mixed measurement with evolution, which is exactly what the three-round scope commitment worked to avoid.

The fix is small enough to land as its own commit on `idempotency-trial` whenever convenient.

## Fixtures to add

When this is fixed, add at minimum:

- `EffectAnnotationParser` reads `@lint.context replayable` when it follows a single attribute (the observed failure).
- `EffectAnnotationParser` reads the annotation when it appears between two attributes (`@A` → `///` → `@B` → `func`).
- `EffectAnnotationParser` reads the annotation when both `///` BEFORE and `///` AFTER attributes coexist on the same decl (duplicates should not double-register the effect; pick the first found, or warn).
- Negative: a non-doc comment (`//` not `///`) between the attribute and the function must still be ignored — the parser already handles this, but the compound-trivia path should preserve the behavior.

## Open questions

- **Property declarations.** This document is about function declarations because that's what both idempotency visitors inspect. The same trivia-routing quirk almost certainly affects any other visitor that reads doc-comment annotations off `VariableDeclSyntax` or similar. If future tiers annotate properties or initializers, the fix should be lifted into a shared helper rather than copy-pasted.
- **User diagnostic for the silent-skip path.** Even after the parser is fixed, a user who writes `/// @lint.unknown_directive` inside their attribute-and-comment stack will still get silence. That's a grammar-versioning issue (deliberately out of Phase 1 scope per the original proposal), not a trivia-routing issue, but worth noting so the two don't get conflated.

## Relationship to shipped work

- Commit `519e60c` (Phase-1.1 OI-4 signature-aware collision) called out this bug in its message as an adjacent discovery.
- The round-2 trial's Run C.1 result (`docs/phase1-round-2/trial-findings.md`) is **not** invalidated by this bug — the collision policy WAS the dominant factor there, since the ordering used was `@available` → `///` which hits both issues. The Phase-1.1 fix's verification on the same shape was what surfaced the trivia-routing bug, because the collision was no longer suppressing the finding and the missing annotation reading became visible.
- The round-3 trial's Run C result (`docs/phase1-round-3/trial-findings.md`) is also safe — the pointfreeco annotations there were all `///`-first, so the trivia-routing path was never exercised incorrectly. Confirmed by re-reading the edits to `PaymentIntentsWebhook.swift` and `GiftEmail.swift`.

## When to revisit

Whenever someone else hits this, or when the next piece of Phase-1.1 / Phase-2 work touches either `EffectSymbolTable.merge(source:)` or the visitors' annotation-reading calls. The fix is small, isolated, and test-backable. Not a blocker for any feature currently in motion; would be a blocker for a real-world adoption campaign that doesn't happen to use the `///`-first convention.
