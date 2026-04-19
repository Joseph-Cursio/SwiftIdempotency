# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at `4c8623f`
  (PR #17 tip). Seven slices merged (`11-17`); two open PRs this
  session:
  - **PR #18** — `composableArchitecture` framework whitelist;
    bare-name override lets `send` in a TCA effect closure classify
    idempotent instead of hitting the bare-name non-idempotent
    list. Closes TCA cluster 3 (6-of-6 `send` fires in both
    `replayable` and `strict_replayable` runs).
  - **PR #19** — closure-typed stored properties become effect
    declarations. `EffectSymbolTable.merge(source:)` now walks
    `VariableDeclSyntax` with function-typed annotations and feeds
    them through the same record path as `FunctionDeclSyntax`.
    Unblocks user annotations on `@DependencyClient` structs.
    Closes TCA cluster 4 (3-of-3 `search` / `forecast` / `fetch`
    fires) **conditional on the adopter annotating the client**.
- **Macros** (this repo): shipped; unchanged this past session.
  `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`, `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.
- **Adopter road-tests**: four rounds completed — `todos-fluent/`,
  `pointfreeco/`, `swift-nio/`, `swift-composable-architecture/`.
  The TCA round closed two of the three cluster-level gaps it
  surfaced (send-on-closure-parameter, dependency-client
  declarations). One remains open: the property-wrapper receiver
  resolver (see §3 below), deferred because the existing
  name+labels lookup suffices on today's corpus.
- **Macro-form end-to-end validation**: ticked on `todos-fluent`
  via the attribute-form A/B supplement. Three macros still
  un-exercised on adopter code: `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.

## Immediate candidates (small, concrete)

### 1. Post-PR-#18/#19 TCA docs hygiene

Two small docs commits hanging off the two open PRs:

- **trial-tca annotations.** The `trial-tca` branch of
  `swift-composable-architecture` should be rolled forward to add
  `/// @lint.effect idempotent` on the three `@DependencyClient`
  closure properties (`WeatherClient.search`,
  `WeatherClient.forecast`, `FactClient.fetch`). Proves out the
  PR #19 prediction and gives the corpus a realistic post-slice
  reading for future rounds.
- **trial-transcripts.** The post-PR-#18 `replayable` and
  `strict_replayable` transcripts were captured at
  `/tmp/tca-rerun-post-pr18/` during validation but not committed.
  Rolling both into
  `docs/swift-composable-architecture/trial-transcripts/` with a
  short retrospective addendum closes the PR-#18 / PR-#19
  measurement story.

Cheap; tie-up work, not design.

### 2. `.init(...)` member-access form gap

Long-running known gap. Firing at ~1/10 rate on todos-fluent,
~1/10 on pointfreeco. Current type-constructor whitelist matches
bare-identifier calls only (`JSONDecoder()`, `HTTPError(.notFound)`).
Extending to `Type.init(...)` member-access form would close one
diagnostic per framework-response-builder call site.

Low priority in isolation (1 catch per adopter) but the sum
across rounds is creeping up. Slice when the firing rate exceeds
~2/round consistently.

## Deferred slices (open but paused)

### 3. Property-wrapper-aware receiver-type resolution

Originally framed as TCA cluster 4's fix; PR #19 delivered the
3-of-3 drop via a simpler route (closure-property declarations).
The receiver-type work is **still open** and relevant when the
trial corpora eventually exhibit a same-name method collision.

Current state: `EffectSymbolTable` keys on `name + argumentLabels`
(receiver-agnostic). Two distinct `search(query:)` declarations
with different effects collide and both withdraw. On today's
corpora the collision policy hasn't bitten, but the risk grows
linearly with the number of annotated dependency clients.

Fix direction when it's needed:
- Teach `FunctionDeclCollector` / `ClosurePropertyDeclCollector`
  to capture each decl's enclosing type.
- Re-key `EffectSymbolTable` on `(typeName, signature)` when
  a type is known; keep bare-signature lookup as fallback.
- Teach `ReceiverTypeResolver` to look through property wrappers
  — `@Dependency(\.foo) var foo` (no type annotation), `@Environment`,
  `@EnvironmentObject`, `@State` — and return `.named(WrappedType)`.
  The generic wrapper-aware path is preferable to a TCA-specific
  whitelist because SwiftUI coverage comes along.
- Visitor update: `analyzeCall` consults the type-qualified entry
  when the receiver resolves, falls back to bare-signature otherwise.

Trigger: the first annotated-corpus round where two different
types each declare a signature with the same `name(labels:)` and
different tiers. Watch for this on swift-nio-scale corpora or on
large TCA apps with multiple dependency clients sharing method
names (`fetch`, `search`, `save` are the likely collision points).

### 4. Escape-wrapper recognition slice

`fireAndForget` (pointfreeco), `detach` / `runInBackground`
(AWS Lambda / Hummingbird-shape). A per-framework whitelist of
known "trusted observational wrappers" would reduce strict-mode
noise.

**Hold until a second adopter surfaces the same pattern** — the
current evidence is pointfreeco-specific. An AWS Lambda adopter
round would be the natural cross-adopter data point. Shape would
mirror PR #14's `idempotentReceiverMethodsByFramework`.

## Deeper work (bigger slices)

### 5. Real perf fix on the inference loop

PR #16 is a safety net (wall-clock budget, default 30s). The
underlying cause — `EffectSymbolTable.runInferencePass` scales
worse than linear in some dimension of swift-nio's wide per-file
call graphs — isn't fixed. Impact: multi-hop inference on huge
corpora is incomplete even with the budget.

Requires profiling + algorithm work. Probably 1-2 sessions.
Unlocks full correctness on swift-nio-scale codebases.

### 6. Macro-form validation for `IdempotencyKey` + `@ExternallyIdempotent(by:)`

Ties into pointfreeco finding #7 below: Stripe's `paymentIntent.id`
is the canonical idempotency-key carrier. Two paths:

- **Purpose-built sample**: tiny SPM package that consumes
  `SwiftIdempotency`, defines a webhook handler signature with
  `idempotencyKey: IdempotencyKey`, verifies the type system
  rejects raw `UUID()` construction. Cheap, demonstrates the
  type safety.
- **Annotate a real webhook adopter**: add `IdempotencyKey` to
  pointfreeco's `handlePaymentIntent` (or similar). Refactor-heavy;
  requires running the code to confirm; crosses from measurement
  into production changes.

Start with the sample; the adopter integration is its own project.

## Follow-ups on what we found

### 7. Verify the pointfreeco findings

The road-test surfaced 4 static patterns matching "Stripe retry →
duplicate email" in pointfreeco's webhook handlers. Unknown
whether runtime mitigations (Stripe event-ID dedup, `gift.delivered`
guards, DB-level constraints) prevent them from firing in
production. Three possible next moves:

- Read `pointfreeco`'s runtime path carefully for dedup guards
  outside the webhook handlers (database models, job queue layer).
- Open an issue on pointfreeco with the static findings — let
  the maintainers confirm or explain.
- Leave it. The round's value was validating the linter's
  precision; pursuing adopter bugs is a different project.

### 8. Remeasure swift-nio with annotations under the new budget

Now that full-corpus scans complete (~3 min post PR #16), a
proper full-corpus measurement with real annotations on NIO
handlers is cheap. Probably confirms the null-result conclusion
from the scoped scan. Worth doing once to close the loop on the
swift-nio round with a cleaner dataset.

## Memory note

The Claude-Code memory at
`/Users/joecursio/.claude/projects/-Users-joecursio-xcode-projects-swiftIdempotency/memory/`
has one entry — the direct-to-main workflow preference for both
`SwiftIdempotency` and `SwiftProjectLint`. Linter rule slices still
follow the PR workflow (PRs #11-19 form the heuristic-evolution
audit trail). Docs and simple tweaks go straight to main.

## Recommended next-session opener

Three options, pick based on appetite:

- **Slot 1: post-PR #18/#19 docs hygiene.** Commit trial-tca
  annotations + transcripts. 15-30 minutes. Closes out the past
  session's two PRs without starting anything new.
- **Slot 8: swift-nio remeasurement.** Small and closes a loop.
  Gives a cleaner null-result dataset for the adopter survey.
  Tests whether PR #16's budget fully unblocks nio-scale inference.
- **Slot 6: `IdempotencyKey` macro sample.** Small SPM sample that
  exercises the last un-validated macro surface. Good candidate
  if appetite is for feature work rather than measurement.

Slot 5 (perf fix) and slot 3 (property-wrapper receiver resolution)
are both real work but have no immediate triggering evidence —
wait for a corpus that exhibits the pathology before committing
a session to either.
