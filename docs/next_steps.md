# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at PR #17 tip
  (`4c8623f`). Seven slices shipped: Fluent save/update/delete
  (PR #11), drop nil-imports backcompat (#12), Fluent query-builder
  reads (#13), Hummingbird primitives (#14), move `update` to bare
  prefix (#15), wall-clock budget on the fixed-point loop (#16),
  walk CodeBlockItem trivia for prefix-statement annotations (#17).
- **Macros** (this repo): shipped; unchanged this past session.
  `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`, `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.
- **Adopter road-tests**: four rounds completed — `todos-fluent/`,
  `pointfreeco/`, `swift-nio/`, `swift-composable-architecture/`.
  Framework-coverage criterion (Vapor / Hummingbird / SwiftNIO /
  Point-Free) is now met. pointfreeco round surfaced 4 probable
  Stripe-retry duplicate-email shapes in production code. TCA round
  surfaced `return-trailing-annotation` (closed as PR #17); the
  post-fix remeasurement is now committed and surfaced **two new
  adoption-gap candidates**: `send`-on-closure-parameter (6 fires)
  and dependency-client method dispatch via `@Dependency` property
  wrappers (3 fires on `weatherClient.search/forecast`,
  `factClient.fetch`).
- **Macro-form end-to-end validation**: ticked on `todos-fluent`
  via the attribute-form A/B supplement. Three macros still
  un-exercised on adopter code: `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.

## Immediate candidates (small, concrete)

### 1. `send`-on-closure-parameter false-positive

Surfaced by the TCA post-fix re-run. `await send(.action)` inside
TCA effects dispatches an action via the `Send<Action>` closure
parameter; the heuristic sees bare `send` and infers
`non_idempotent`. Structurally safe (calling `send` is
state-transition dispatching, not an effectful side effect), but
the heuristic can't distinguish `send` as a closure parameter
from `send` as a mail-sending receiver method.

Fix directions (not mutually exclusive):

- **Receiver-type awareness on closure parameters.** The linter
  already has ReceiverTypeResolver; teach it to recognise a
  `send` that resolves to a closure parameter (via the enclosing
  closure's signature) and exempt it from the bare-name rule.
- **TCA framework whitelist entry.** Add `send` under a `tca` or
  `composableArchitecture` framework name in
  `idempotentReceiverMethodsByFramework`, gated on
  `import ComposableArchitecture`. Parallels PR #14's
  Hummingbird/Fluent approach. Cheaper than receiver-type work
  but specific to TCA.

Prevalence: 6 of 6 TCA effect closures fire on `send`. Natural
next adopter-driven slice.

### 2. Dependency-client receiver resolution via property wrappers

New from the TCA post-fix remeasurement. 3 strict-mode fires on
`weatherClient.search`, `weatherClient.forecast`, `factClient.fetch`
— calls via `@Dependency(\.foo)` property wrappers. Linter reads
`self.weatherClient.search(query:)` but cannot classify the
receiver because property-wrapper projection hides the real type
from syntactic analysis.

Generalises beyond TCA: SwiftUI `@Environment(\.foo)`,
`@EnvironmentObject`, `@State` all have the same shape. A
property-wrapper-aware receiver resolver would unlock classification
for the whole class of DI-style access patterns.

Fix direction: teach `ReceiverTypeResolver` to look up
`@propertyWrapper var foo: Wrapper<T>` declarations in scope and
resolve `self.foo.method()` through the wrapper's
`wrappedValue` type. Scope may need either a targeted TCA/`Dependency`
whitelist or a generic wrapper-aware path; start with the generic
approach since it delivers SwiftUI coverage too.

See
[`swift-composable-architecture/trial-findings.md`](swift-composable-architecture/trial-findings.md)
§"Decomposition into named slice clusters" cluster 4 for the
full scope.

### 3. Escape-wrapper recognition slice

Only open deferred slice candidate. `fireAndForget` (pointfreeco),
`detach` / `runInBackground` (AWS Lambda / Hummingbird-shape).
A per-framework whitelist of known "trusted observational wrappers"
would reduce strict-mode noise.

**Hold until a second adopter surfaces the same pattern** — the
current evidence is pointfreeco-specific. An AWS Lambda adopter
round would be the natural cross-adopter data point. Shape would
mirror PR #14's `idempotentReceiverMethodsByFramework`.

### 4. `.init(...)` member-access form gap

Long-running known gap. Firing at ~1/10 rate on todos-fluent,
~1/10 on pointfreeco. Current type-constructor whitelist matches
bare-identifier calls only (`JSONDecoder()`, `HTTPError(.notFound)`).
Extending to `Type.init(...)` member-access form would close one
diagnostic per framework-response-builder call site.

Low priority in isolation (1 catch per adopter) but the sum
across rounds is creeping up. Slice when it firing rate exceeds
~2/round consistently.

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
follow the PR workflow (PRs #11-17 form the heuristic-evolution
audit trail). Docs and simple tweaks go straight to main.

## Recommended next-session opener

Two good options, pick based on appetite:

- **Slot 1: `send`-on-closure-parameter slice.** Small, TCA-specific.
  Either receiver-type resolution on closure parameters, or a
  `composableArchitecture` framework whitelist. Whichever path, the
  slice ships as PR #18.
- **Slot 2: property-wrapper-aware receiver resolution.** Larger,
  generalises across TCA + SwiftUI + any `@propertyWrapper` DSL.
  Probably 1-2 sessions. Doing this first would also catch the
  `@Dependency` case for free on the next adopter round.

The TCA round will likely produce stronger follow-on evidence if
slot 2 lands first (more classifications mean more ground truth
for the heuristic to evaluate). Slot 1 is the lower-risk,
quicker-feedback choice.
