# swift-composable-architecture — Trial Retrospective

## Did the scope hold?

**Mostly yes, with one mid-round adjustment.**

- The initial scan strategy was "point the CLI at the TCA root"
  — and produced zero diagnostics on the full repo (including
  the positive control). The root `Package.swift` does not
  register `Examples/*` as SPM targets; the Examples are
  separate xcodeprojects. Rescoped to per-example CLI
  invocations. Scope doc was updated in-round to reflect this.
- Added a positive-control pair (`trialSendNotification` +
  `trialHandleMoveEffect`) mid-round when all six `.run { }`
  annotations produced zero diagnostics. The control exists
  specifically to distinguish "visitor isn't running" from
  "visitor is running but the six sites are invisible." This
  diagnosis step wasn't in the scope doc but is consistent
  with the round's research question.
- No other source edits. No logic changes. Throwaway branch
  not pushed. Audit stayed well under the 30-diagnostic cap
  (1 diagnostic across both runs).

## Answers to the four pre-committed questions

### (a) Does trailing-closure annotation fire on `.run { send in ... }`?

**No — and this is the round's primary finding.** The existing
trailing-closure annotation recognition was designed against the
server-framework idiom `app.post("orders") { req in ... }` where
the annotated call is a bare expression statement. TCA's
canonical reducer pattern is `return .run { send in ... }`, where
the call is wrapped in a `ReturnStmtSyntax`. SwiftSyntax attaches
the doc comment to the `return` keyword, not to the `.run(...)`
call expression, so the visitor never sees an annotated analysis
site.

**This is a correctness gap, not a precision or recall gap.**
Adopters would see "no issues" and assume their annotations are
working.

### (b) Does body-based upward inference reach through `@Dependency` calls?

**Unknown from this round.** Because the six `.run { }`
annotations never create analysis sites, upward inference through
`self.factClient.fetch`, `self.weatherClient.search`,
`self.weatherClient.forecast` is not exercised. This question
can only be answered after the `return-trailing-annotation`
gap is fixed.

A speculative answer: `@Dependency(\.foo) var foo` declares
`foo` via property-wrapper projection, and inference should
resolve `self.foo.method()` the same as any member call on a
typed receiver. But the `@Dependency` keypath declaration may
not carry enough type information for ReceiverTypeResolver to
classify calls — this is a plausible future adoption gap once
the structural gap is closed.

### (c) New cross-adopter slice candidates?

**One: `return-trailing-annotation`.** See
[`trial-findings.md`](trial-findings.md) §"Adoption gap" for the
shape, fix direction, and prevalence assessment. The gap is
TCA-prevalent (100% of this round's sites affected) but
structurally applies to any adopter that wraps annotated calls
in a prefixed statement (`return`, `try`, `await`, `let x =`,
etc.).

Not collapse-able into the open "escape-wrapper recognition"
slice — that one is about **which callees** are treated as
transparent; this is about **which call sites** are recognised
as analysis anchors.

### (d) Realistic macro-form annotation story for TCA?

TCA adopters can't attribute-annotate closures directly —
closures aren't declarations. Three options surfaced:

1. **Attribute on `var body: some Reducer<State, Action>`.**
   Classifies the entire reducer. Too coarse: a single reducer
   mixes pure state mutations and effectful closures, and the
   effect tier of `body` is the join of all branches. Useful
   only if the annotation is "this reducer must contain no
   retry-context violations in any branch."
2. **Attribute on the `Reduce { state, action in ... }` trailing
   closure.** Needs the same `return-trailing-annotation` fix —
   `Reduce` is a call, its trailing closure is a body. If the
   visitor walks ExpressionStmtSyntax-wrapped calls
   structurally (which it mostly does already), this annotation
   site is already reachable. Worth exploring once the gap is
   fixed.
3. **A hypothetical `@Replayable` macro on `.run`'s argument.**
   Requires changes in the SwiftIdempotency macros package and
   likely TCA itself (the `.run(operation:)` closure signature
   would need to accept an attributed closure). More invasive
   than this round can justify.

The simplest path: close `return-trailing-annotation`, then
re-visit this adopter. The doc-comment annotation form
(`/// @lint.context replayable` above `return .run`) would then
work, and the macro-form discussion can be deferred to a future
round where we actually need it.

## What would have changed the outcome

- **An earlier ground-truth positive control.** Dropping the
  `trialSendNotification` + `trialHandleMoveEffect` pair into
  the file from the start of the round would have caught the
  "visitor isn't seeing the annotations" state in the first
  scan, not the second. Policy note: **future rounds should
  include a positive-control pair when annotating a closure
  shape the linter hasn't been validated against**.
- **Reading the visitor source before choosing annotation
  sites.** Confirming how leading trivia binds to
  `FunctionCallExprSyntax` vs `ReturnStmtSyntax` before
  annotating would have predicted the gap. Cheap investigation
  to do up-front; expensive to discover via full round.

## Cost summary

- **Estimated:** ~30-45 minutes (standard round).
- **Actual:** ~40 minutes. Round-mechanic overhead was modest;
  the scan-routing confusion (Package.swift scope) added
  ~5 minutes of diagnosis.

## Policy notes

- **Positive-control pairs belong in annotation plans.** For any
  round where the annotation surface is a closure shape not
  covered by existing tests, include a pair of declarations
  with known-expected behaviour in the annotation plan. When
  the real sites produce zero diagnostics, the control shows
  whether the round is finding nothing (valid result) or the
  visitor isn't running (methodological failure). Worth folding
  back into [`../road_test_plan.md`](../road_test_plan.md).
- **Scan-root specificity matters for multi-package adopters.**
  TCA, Vapor, and `hummingbird-examples` all have multi-package
  layouts. Future plan updates should note that the scan root
  must contain a single `Package.swift` or each sub-package
  must be scanned independently.
- **"Correctness gaps" are distinct from precision/recall gaps.**
  This round found a gap in the visitor's ability to recognise
  an annotation at all, not in its ability to classify a call
  once recognised. The findings document coins
  "correctness slice" to distinguish these — worth adopting
  for future slice classifications if the pattern recurs.

## Toward completion criteria

Per [`../road_test_plan.md`](../road_test_plan.md):

- **Framework coverage** (criterion #1) — this round **completes
  the Point-Free ecosystem tier**. All four listed framework
  tiers (Vapor, Hummingbird, SwiftNIO, Point-Free) have now
  been road-tested on at least one adopter. Criterion #1 is
  now met.
- **Adoption-gap stability** (criterion #2) — this round
  produced **one new slice candidate**
  (`return-trailing-annotation`). The three-round zero-slice
  plateau clock has **not** reached three consecutive rounds.
  Current state: 0 consecutive zero-slice rounds. Count should
  resume after the slice lands and a follow-up round confirms
  no new gaps.
- **Macro-form evidence** (criterion #3) — already ticked on
  `todos-fluent`; not exercised here. Attribute-form
  annotations on TCA closure sites are not cleanly expressible,
  per question (d) above.

## Data committed

- `docs/swift-composable-architecture/trial-scope.md`
- `docs/swift-composable-architecture/trial-findings.md`
- `docs/swift-composable-architecture/trial-retrospective.md` — this document
- `docs/swift-composable-architecture/trial-transcripts/replayable.txt`
- `docs/swift-composable-architecture/trial-transcripts/strict-replayable.txt`

Adopter-side edits remain on the `trial-tca` branch of a
shallow TCA clone at `/tmp/swift-composable-architecture`,
local-only.
