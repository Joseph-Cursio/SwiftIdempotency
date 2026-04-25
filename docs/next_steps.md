# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at `2fbb171`
  (post-PR #21 merge tip). Recent PRs:
  - **PR #21 (merged, 2026-04-21)** — commit `2fbb171`: prefix
    lexicon expanded (`submit`, `start`, `complete`, `register`
    added to `HeuristicEffectInferrer.nonIdempotentNames`). Closes
    slot 13. Isowords Run A remeasured at merge tip: 5 → 8 fires,
    4/5 → 5/5 handler coverage, missed-bug `startDailyChallenge`
    recovered. +14 tests → 2286/276 green.
  - **PR #20 (merged)** — commit `bc3c05e`: `Type.init(...)` member-
    access form normalised to the bare-ctor whitelist path. Closes
    slot 2 from prior `next_steps.md`; eliminates one stray diagnostic
    per framework-response-builder call site that uses the
    `Foo.init(...)` spelling. Structural, no YAML / no new whitelist
    entries; +10 tests → 2270/275 green.
  - **PR #19 (merged)** — commit `0be2d36`: closure-typed stored
    properties become effect declarations. `EffectSymbolTable.merge`
    now walks `VariableDeclSyntax` with function-typed annotations
    (plus `AttributedTypeSyntax`-peel for `@Sendable` / `@MainActor`).
    Unblocks user annotations on `@DependencyClient` structs.
    **Closed TCA cluster 4** (3 of 3 `search` / `forecast` / `fetch`
    fires eliminated in the post-#19 re-run — see
    [`swift-composable-architecture/trial-findings.md`](swift-composable-architecture/trial-findings.md)).
  - **PR #18 (merged)** — commit `5698683`: TCA send-closure-parameter
    whitelist. Post-Lambda-round evidence: the PR #18 bare-name
    override shape is TCA-specific. The earlier `idempotentReceiverMethodsByFramework`
    infrastructure (commit `040f186`, Hummingbird) is what
    generalises across frameworks — see slot 10.
- **Macros** (this repo): shipped; three consumer samples under
  `examples/` exercise the full user-facing surface end-to-end in
  downstream SPM packages:
  - `examples/webhook-handler-sample/` (commit `359db69`) —
    `IdempotencyKey` type safety.
  - `examples/idempotency-tests-sample/` — `@IdempotencyTests`
    extension-role expansion on a `@Suite` type (3 generated tests
    + 2 direct tests, green).
  - `examples/assert-idempotent-sample/` — `#assertIdempotent` at
    call-site covering every row of the sync/async × throwing/pure
    effect matrix (6 tests, green).
  `@Idempotent` / `@NonIdempotent` / `@Observational` /
  `@ExternallyIdempotent(by:)` are exercised by the root test target
  and by every adopter road-test. **Slot 6 — consumer-context
  validation — is fully closed.**
- **Adopter road-tests**: **fourteen rounds completed** —
  `todos-fluent/`, `pointfreeco/`, `swift-nio/`,
  `swift-composable-architecture/`, `swift-aws-lambda-runtime/`,
  `penny-bot/`, `isowords/`, `spi-server/`, `prospero/`,
  `myfavquotes-api/`, `hummingbird-examples-open-telemetry/`,
  `luka-vapor/`, `hellovapor/`, **`grpc-swift-2/`**. The TCA
  round closed **all three** cluster-level gaps it surfaced (return-
  trailing annotation, send-on-closure-parameter, dependency-client
  declarations) across PRs #17 / #18 / #19; current TCA residual on
  tip `bc3c05e` is 1 replayable / 13 strict, all in known cross-adopter
  noise/defensible clusters (`Duration` implicit-member, enum-case /
  `Result { }` constructors, `ContinuousClock.sleep`). The property-
  wrapper receiver resolver (slot 3) is a separate deferred slice,
  still open but no longer blocking TCA cluster 4.
- **Road-test workflow**: reworked to be fork-authoritative (commit
  `bb69729`). Trial branches live on `<upstream>-idempotency-trial`
  forks under the user's GitHub, not on ephemeral `/tmp` clones.
  See `road_test_plan.md` for the full pre-flight recipe.
- **Macro-form end-to-end validation**: complete. Ticked on
  `todos-fluent` (attribute-form A/B supplement), on the
  webhook-handler sample (`IdempotencyKey`), on the
  idempotency-tests sample (`@IdempotencyTests` extension-role
  expansion compiles + runs green under Swift Testing in a
  downstream package), and on the assert-idempotent sample
  (`#assertIdempotent` overload resolution + effect propagation
  verified at consumer call sites).

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

### PropertyBased — non-fatal `#assertIdempotent` failure mode

`swift-property-based` adopted 2026-04-24 into both repos as a
test-target dependency; see
[`property-based/trial-findings.md`](property-based/trial-findings.md)
for the full writeup. Nine property tests live across the two repos
(7 lattice-law tests on `SwiftProjectLint`'s
`UpwardEffectInferrer.leastUpperBound`, 2 wrap-pattern demonstrations
on `#assertIdempotent`).

One backlog item surfaced: `#assertIdempotent` fails via
`precondition`, which terminates the test process. On a failing
`propertyCheck` iteration the process dies before PropertyBased's
shrinker can minimise the counter-example. Property-based users get
the raw random input rather than a shrunk one.

Fix direction when triggered:
- `Sources/SwiftIdempotency/AssertIdempotent.swift` — add a
  `failureMode` parameter to `__idempotencyAssertRunTwice` + async
  variant, routing to `Issue.record` on `.issueRecord`. Shape mirrors
  the existing `assertIdempotentEffects` surface in
  `SwiftIdempotencyTestSupport`.
- `Sources/SwiftIdempotencyMacros/AssertIdempotentMacro.swift` —
  forward the parameter through the macro expansion.
- `Tests/SwiftIdempotencyTests/AssertIdempotentMacroTests.swift` —
  cover the new surface.
  `Tests/SwiftIdempotencyTests/PropertyBasedAssertIdempotentTests.swift`
  — switch to `.issueRecord` and prove shrinking with a deliberately-
  failing property.

Trigger: first use of the PBT wrap pattern that surfaces a failing
property where the raw random input isn't immediately diagnostic.
Zero-priority until then — the green-path demo is stable as-is.

## Deeper work (bigger slices)

### 5. Real perf fix on the inference loop

PR #16 is a safety net (wall-clock budget, default 30s). The
underlying cause — `EffectSymbolTable.runInferencePass` scales
worse than linear in some dimension of swift-nio's wide per-file
call graphs — isn't fixed. Impact: multi-hop inference on huge
corpora is incomplete even with the budget.

Requires profiling + algorithm work. Probably 1-2 sessions.
Unlocks full correctness on swift-nio-scale codebases.

## Memory note

The Claude-Code memory at
`/Users/joecursio/.claude/projects/-Users-joecursio-xcode-projects-swiftIdempotency/memory/`
has four entries:

- `workflow_direct_to_main.md` — direct-to-main on solo repos
  for `SwiftIdempotency` + `SwiftProjectLint`. Linter rule
  slices keep the PR convention; docs and simple tweaks go
  straight to main.
- `project_validation_phase2.md` — **updated 2026-04-24.**
  Original single-contributor / low-star heuristic **retired
  by user** after three consecutive zero-friction rounds
  (Vernissage, plc-handle-tracker, HomeAutomation). Adopter
  selection now optimises for *domain / shape novelty*, not
  project obscurity. Larger / multi-contributor projects are
  in-scope.
- `project_trial_fork_naming.md` — adopter trial branches live
  on `<upstream>-idempotency-trial` forks (naming convention
  codified in `road_test_plan.md`).
- `project_phase3_non_fatal_assert_idempotent.md` — backlog
  item from the 2026-04-24 PropertyBased adoption trial.
  `#assertIdempotent`'s `precondition` failure mode blocks
  PropertyBased's shrinker; fix is a `failureMode` enum
  mirroring `assertIdempotentEffects`.

## Recommended next-session opener

**State snapshot (2026-04-25).** Two parallel workstreams are in
stable state:

1. **Linter road-tests** — seven production-app rounds + seven
   framework/demo rounds complete (added grpc-swift-2 2026-04-25,
   first gRPC target — domain/shape novelty round under the
   post-2026-04-24 selection rule). All three completion criteria
   met since myfavquotes-api; rounds since have been slice-driven.
   Slots 2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
   20, 21, 22 all closed.
2. **Package-integration (Option B) trials** — v0.3.1 shipped; nine
   production adopters validated end-to-end (Penny, isowords,
   prospero, myfavquotes-api, luka-vapor, hellovapor,
   VernissageServer, plc-handle-tracker, HomeAutomation). **Three
   consecutive zero-friction fresh-signal rounds** (Vernissage,
   plc-handle-tracker, HomeAutomation) mirror the 3/3-plateau bar
   from the linter road-tests → Option B surface is effectively
   stable.

Linter completion criteria (met):

1. ✅ **Framework coverage** — Vapor (todos-fluent + SPI-Server +
   pointfreeco + **HomeAutomation**), Hummingbird (prospero +
   myfavquotes-api), SwiftNIO (swift-nio), Point-Free
   (pointfreeco + TCA).
2. ✅ **Adoption-gap stability — 3/3 consecutive plateaus**
   (spi-server + prospero + myfavquotes-api).
3. ✅ **Macro-form evidence** — six consumer samples in
   `examples/` exercise `IdempotencyKey` / `@IdempotencyTests` /
   `#assertIdempotent` / `IdempotentEffectRecorder` / Option B /
   Fluent constructor end-to-end.

Package-integration (Option B) completion criteria (met):

1. ✅ **Cross-adopter coverage** — nine production adopters across
   AWS Lambda / PointFree HttpPipeline / Hummingbird / Vapor /
   Vapor + vapor/queues / Vapor + APNSwift + MySQL Fluent.
2. ✅ **Fresh-signal stability — 3/3 consecutive zero-friction
   rounds** (Vernissage → plc-handle-tracker → HomeAutomation).
3. ✅ **Pre-existing-protocol adoption evidence** —
   HomeAutomation's `NotificationSender` was already an extracted
   `Sendable` protocol with `id` documented as the stable
   external key; no extraction refactor needed for the trial.

Per `road_test_plan.md` §"Completion criteria": *"Continue the
template even after completion criteria are met — future linter
slices still get validated the same way. The plan stays alive;
it just stops blocking on new targets."* Both workstreams are
in this post-criteria mode. Options, in value-per-effort order:

- **Cross-adopter triage filing** — ten real-bug shapes documented
  across six adopters. **Two filed:**
  - **HelloVapor PR #1** (2026-04-22) — Acronym missing unique constraint.
    [`sinduke/HelloVapor#1`](https://github.com/sinduke/HelloVapor/pull/1).
  - **prospero PR #8** (2026-04-22) — ActivityPattern missing composite
    `(user_id, name)` unique constraint.
    [`samalone/prospero#8`](https://github.com/samalone/prospero/pull/8).
  Both await maintainer response. The remaining 8 shapes (Penny × 4,
  isowords × 2, myfavquotes-api × 1, luka-vapor × 1) stay parked —
  Penny's four in [`ideas/penny-bot-triage-issues.md`](ideas/penny-bot-triage-issues.md),
  others not yet scoped. Filing policy: keep it narrow, one finding
  per PR, use the draft pattern established in
  [`ideas/pointfreeco-triage-issue.md`](ideas/pointfreeco-triage-issue.md).

- **Bcrypt-crypto-gap** (1-adopter, 1 fire from myfavquotes-api).
  Single-fire shape — only matters if a future Hummingbird/Vapor
  adopter with auth flows fires the same shape and pushes to
  2-adopter slice volume. No action until then.

- **Axiom `emit` observability pattern** (1-adopter from
  luka-vapor, mirrors SPI-Server's `AppMetrics.push` shape).
  Same verdict as Prometheus Pushgateway — each observability
  library is its own receiver; defer until 2-adopter evidence.

- **Remaining 1-adopter candidates still awaiting second-adopter
  evidence:** Vapor `Route.description`, Hummingbird `addMiddleware`,
  Hummingbird `queryParameters.require` sibling-pair, Swift Distributed
  Tracing `withSpan`, `AppMetrics.push` Prometheus-Pushgateway,
  Uitsmijter's `Prometheus.main.<metric>?.inc(...)` pattern
  (distinct from SPI-Server's `AppMetrics.push` shape),
  **SwiftProtobuf `<Type>.with(_:)` builder + bare-init
  message constructors** (5 fires across 2 example packages
  on grpc-swift-2 round, 2026-04-25 — first measurement of
  protobuf-message construction surface; fix direction is a
  `protobuf` namespace in the existing `idempotentReceiverMethodsByFramework`
  infrastructure, commit `040f186`).

- **gRPC `RPCWriter.write` (2 fires from grpc-swift-2)** —
  framework-side stream-emit primitive. Same verdict pattern
  as Hummingbird `addMiddleware` and SPI-Server `AppMetrics.push`:
  observability/streaming framework primitives that fire under
  strict but are the framework's correct mechanism, not the
  user's bug. gRPC-specific; no 2-adopter trigger.

Deferred — no urgent triggering evidence:

- Slot 5 (perf fix) — no corpus has stressed the wall-clock
  budget. luka-vapor + hellovapor both scanned instantly.
- Slot 3 (property-wrapper receiver resolution) — no adopter
  round has surfaced a same-name method collision with
  differing tiers.

**Ten real-bug shapes** caught by the linter across Penny +
isowords + prospero + myfavquotes-api + luka-vapor + hellovapor
all map to `IdempotencyKey` / `@ExternallyIdempotent(by:)`.
**Nine production adopters** have the Option B surface validated
end-to-end. Twenty-seven green Option B tests across
package-integration trials (Penny 8 + Vernissage 9 + plc 3 +
HomeAutomation 3 + Uitsmijter 4).

A session-level retrospective synthesising the full arc (10
adopters, 22 shipped slices, Option B R1/R2/R3 evolution, sweep
methodology lessons) is at
[`retrospective-2026-04-24.md`](retrospective-2026-04-24.md).
**SwiftIdempotency is at v0.3.1** (ship history: v0.1.0 →
v0.2.0 SwiftIdempotencyFluent → v0.3.0 Option B → v0.3.1
swift-syntax pin relax). Slot 7's publicly-visible follow-on
is parked in
[`ideas/pointfreeco-triage-issue.md`](ideas/pointfreeco-triage-issue.md).
