# swift-composable-architecture — Trial Findings

## Run A — replayable mode

Source transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**One diagnostic, on the positive control.**

| # | File:line | Rule | Verdict |
|---|---|---|---|
| 1 | `Examples/Todos/Todos/Todos.swift:15` | `nonIdempotentInRetryContext` | positive control — fires correctly |

The six real `.run { send in ... }` annotations in Todos (×2),
EffectsBasics (×2), and SearchView (×2) produce **zero
diagnostics**. Not because there are no non-idempotent calls
inside — `await send(.sortCompletedTodos)` for example invokes
`send`, which is on the heuristic's bare non-idempotent-prefix
list. Rather, the annotation isn't being recognised as attaching
to the `.run(...)` call at all.

**Yield**: 1 catch / 7 annotated sites (1 positive control + 6
`.run` sites) = **0.14 including silent**; **1 catch / 1
non-silent = 1.00 excluding silent**. Interpreted honestly: the
real-adopter yield is **0 catches across 6 annotated sites**.

## Run B — strict_replayable mode

Source transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Same result.** One diagnostic, the same positive control (now
reporting as `strict_replayable` instead of `replayable`). Zero
`UnannotatedInStrictReplayableContext` diagnostics on any of the
six `.run { }` closures.

Strict mode should, if the annotations were recognised, fire on
every unclassified call inside the annotated closures — at
minimum `clock.sleep`, `factClient.fetch`, `weatherClient.search`,
`weatherClient.forecast`, `send`, and `Result { try await ... }`.
The fact that it fires on **none of them** confirms the six
annotation sites are invisible to the visitor.

## Root cause

SwiftSyntax attaches leading trivia to the **first token of the
node it precedes**. The annotation pattern under test is:

```swift
/// @lint.context replayable
return .run { send in ... }
```

The doc comment is leading trivia of the `return` keyword, which
is part of a `ReturnStmtSyntax`. It is **not** leading trivia of
the `FunctionCallExprSyntax` for `.run(...)`. The current visitor
checks `node.leadingTrivia` where `node` is the call — by the
time the walker reaches the call, only the whitespace between
`return` and `.run` is the call's leading trivia.

The existing trailing-closure recognition (tested against
server-framework handlers like `app.post("orders") { req in ... }`)
works because those call sites are **expression statements** with
no preceding keyword: the doc comment IS leading trivia of the
call's first token.

This is the mechanical gap: the annotation recognition covers
`ExpressionStmtSyntax`-wrapped calls, but not `ReturnStmtSyntax`-
wrapped or otherwise keyword-prefixed calls.

## Adoption gap — `return-trailing-annotation`

**New cross-adopter slice candidate.** Does not collapse into any
existing open slice (escape-wrapper recognition,
`.init(...)` member-access form, etc.).

**Shape.** The visitor's trailing-closure recognition fires when
the annotated call is written as a bare statement:

```swift
/// @lint.context replayable   // ← attaches to the call ✓
app.post("orders") { req in ... }
```

but not when the same call is the return value of an enclosing
statement:

```swift
/// @lint.context replayable   // ← attaches to `return`, not `.run`
return .run { send in ... }
```

Other forms with the same problem:

```swift
/// @lint.context replayable   // ← attaches to `try`/`await`/`let`
try await foo { ... }
let effect = foo { ... }
```

**Fix direction.** In `NonIdempotentInRetryContextVisitor` and
`UnannotatedInStrictReplayableContextVisitor`, when examining a
`FunctionCallExprSyntax`, walk up the syntax tree to find the
enclosing statement (`ReturnStmtSyntax`, `ExpressionStmtSyntax`,
`VariableDeclSyntax` with a call initializer, etc.) and also
consult that node's leading trivia for the annotation.

Scope: likely a ~30-line change in the trivia-lookup helper;
gated by a new test fixture covering `return`, `try`, `await`,
and assignment-based prefixes. No new annotation grammar —
the rule is: "the annotation above the statement that contains
the call attaches to the call."

**Prevalence.**

- **TCA (this round):** 6 of 6 annotation sites affected (100%).
- **pointfreeco/pointfreeco:** 0 sites affected — Stripe webhook
  handlers are all top-level `func` declarations, not
  switch-returned expressions.
- **hummingbird-examples/todos-fluent:** 0 sites affected — all
  handlers are top-level `func`s or `app.post(...) { req in }`
  expression statements.
- **swift-nio:** n/a — null-result round.

The gap is Point-Free-ecosystem-specific *in the sample so far*,
but the pattern "return an effect from a switch arm" isn't
TCA-unique — anywhere a framework uses sum-type effect returns
(Combine publishers, RxSwift observables written in the same
style, custom DSLs that return `some Effect`), the same trivia
problem would apply.

## Comparison to prior rounds

| Round | Annotated sites | Replayable catches | Strict-only residual | New slice candidates |
|---|---|---|---|---|
| todos-fluent | 3 | 3 | 6 | 1 (Fluent save/delete → PR #11) |
| pointfreeco | 4 | 6 | 38 | 2 (non-Fluent `update` → PR #15; escape-wrapper — open) |
| swift-nio | 1 (narrowed) | 2 | ~24 | 1 (perf → PR #16) |
| **tca (this round)** | **6** | **0** | **0** | **1 (`return-trailing-annotation` — open)** |

Unique profile: this is the first round where the **annotations
are structurally invisible** rather than firing-or-not-firing
for semantic reasons. The prior rounds demonstrated
measurement-and-verdict flow; this round demonstrates a pre-
measurement failure mode.

## Handler yield, re-framed

The headline "0 catches / 6 annotated sites" is not a precision
or recall measurement of the heuristic — the heuristic never
got the chance to run. Adopters in the TCA-shape idiom would
silently see "no issues" and conclude their code passes, which
is worse than noise.

This makes `return-trailing-annotation` a **correctness slice**
in the same vein as PR #16 (wall-clock budget): a defect in the
visitor's ability to even attempt analysis on a valid annotation
shape.
