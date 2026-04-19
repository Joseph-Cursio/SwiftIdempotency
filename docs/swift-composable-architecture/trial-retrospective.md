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
- `docs/swift-composable-architecture/trial-findings.md` — **rewritten
  post-fix** with the remeasurement numbers; pre-fix version lives in
  git history at commit `065a90c`
- `docs/swift-composable-architecture/trial-retrospective.md` — this document
- `docs/swift-composable-architecture/trial-transcripts/replayable.txt` — **overwritten with post-fix output**
- `docs/swift-composable-architecture/trial-transcripts/strict-replayable.txt` — **overwritten with post-fix output**

Adopter-side edits remain on the `trial-tca` branch of a
shallow TCA clone at `/tmp/swift-composable-architecture`,
local-only.

## Post-fix remeasurement (2026-04-19)

PR #17 on SwiftProjectLint landed as commit `4c8623f` (squash-merge
from `slice-return-trailing-annotation`). Post-merge clean build
of the release CLI, same six annotation sites on TCA, same scan
commands:

- **Replayable**: 7 diagnostics (1 positive control + 6 annotated
  `.run { }` closures now fire on their inner `send` calls).
- **Strict**: 22 diagnostics (7 carried + 15 strict-only unannotated-
  callee fires on stdlib/TCA surface).

Every annotation site is now visible to the visitor. The round's
primary research question — "does the trailing-closure annotation
mechanism fire correctly on TCA effects?" — now answers **yes**.

The remeasurement also opened two new adoption-gap candidates that
were previously hidden behind the visibility gap:

1. **`send`-on-closure-parameter** — 6 defensible fires. Receiver-
   type resolution on closure parameters, or a framework whitelist
   entry gated on `import ComposableArchitecture`.
2. **Dependency-client method dispatch** — 3 adoption-gap fires on
   `weatherClient.search`, `weatherClient.forecast`,
   `factClient.fetch`. Calls via `@Dependency(\.foo)` property
   wrappers are syntactically unclassifiable today; a generic
   property-wrapper-aware receiver resolver would unlock
   TCA-shape and SwiftUI `@Environment`-shape alike.

See [`trial-findings.md`](trial-findings.md) for the full
per-diagnostic verdict table and decomposition into slice clusters.

The slice's own correctness-closure is confirmed: TCA adopters
using the `return .run { ... }` idiom now see diagnostics they
previously missed. The remaining `send` and dependency-client
noise is real work, but it's precision-engineering on top of a
now-functional baseline rather than a blocking visibility gap.

## Post-PR-#18 session measurement (2026-04-19)

SwiftProjectLint PR #18 (composableArchitecture framework whitelist
with bare-name `send` override) and PR #19 (closure-typed stored
properties become effect declarations) were both developed against
this round's findings. PR #18's effect is verified directly; PR #19's
effect is set up but pending verification until merge.

Measurement was run against the PR #18 branch of SwiftProjectLint,
same scan roots as the post-PR-#17 remeasurement:

- **Replayable**: 7 → **1 diagnostic**. Transcript:
  [`trial-transcripts/replayable-post-pr18.txt`](trial-transcripts/replayable-post-pr18.txt).
  The 6-of-6 `send`-on-closure-parameter cluster (cluster 1 in
  `trial-findings.md`) is fully silenced. Only the positive
  control (`trialSendNotification` via `trialHandleMoveEffect`)
  remains — which is the expected ground-truth fire.
- **Strict**: 22 → **16 diagnostics**. Transcript:
  [`trial-transcripts/strict-replayable-post-pr18.txt`](trial-transcripts/strict-replayable-post-pr18.txt).
  Same 6 `send` fires dropped; the 15 strict-only unannotated-callee
  fires and the positive control survive unchanged. Breakdown:
  `sleep` (3), `Duration` constructors (3), enum case / `Result`
  constructors (6), `weatherClient.search` / `weatherClient.forecast` /
  `factClient.fetch` (3), positive control (1).

**Cluster status after PR #18:**

- Cluster 1 (`send`-on-closure-parameter) — **closed**. Framework
  whitelist + bare-name override handles every instance.
- Cluster 4 (dependency-client method dispatch) — **closed
  conditional on adopter annotating**. PR #19 provides the
  mechanism (closure-typed stored properties become effect
  declarations via `EffectSymbolTable.merge(source:)`). The
  annotation work is now in place: `trial-tca` branch of
  `/tmp/swift-composable-architecture` carries
  `/// @lint.effect idempotent` on `WeatherClient.forecast`,
  `WeatherClient.search`, and `FactClient.fetch` (commits
  `d326f80` + `02ba3e0` on top of `7517cc3`). When PR #19 lands,
  re-running the strict scan against annotated trial-tca should
  drop the 3 dependency-client fires, yielding **13 diagnostics**.
- Clusters 2, 3, 5 (enum case constructors, `Duration` constructors,
  `ContinuousClock.sleep`) — unchanged. Still tracked as
  independent slice candidates in `next_steps.md`.

**Findings.md not rewritten.** Per the PR #17 precedent, the
canonical `trial-findings.md` is rewritten when the upstream PR
merges to SwiftProjectLint `main`. PR #18 and PR #19 are still
open; this section records the measurement but leaves the
per-diagnostic verdict table in its post-PR-#17 form. Follow-up
work on the PR-#18/#19 merge should:

1. Re-run the scan against merged `main` + annotated `trial-tca`.
2. Confirm replayable = 1 and strict = 13.
3. Rewrite `trial-findings.md` with the new numbers (old version
   preserved in git history at this commit).
4. Consolidate the `-post-pr18` transcripts into the canonical
   `replayable.txt` / `strict-replayable.txt` names.

**Trial branch durability caveat.** The `trial-tca` branch lives
on a `/tmp` clone and is not pushed to any remote. Macs don't
wipe `/tmp` on every reboot, but they can. If the verification
run above is blocked by a lost branch, the annotations are
trivially replayable from the instructions in this addendum.
