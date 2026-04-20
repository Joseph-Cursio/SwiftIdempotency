# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at `4c8623f`
  (PR #17 tip). Two open PRs carry over from the previous session:
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
    Annotations are in place on the trial-tca branch — re-run is
    cheap once PR #19 merges.
- **Macros** (this repo): shipped; plus a new consumer sample at
  `examples/webhook-handler-sample/` (commit `359db69`) exercising
  `IdempotencyKey` end-to-end in a downstream SPM package. The
  `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`, `@IdempotencyTests`,
  `#assertIdempotent`, and `IdempotencyKey` surfaces ship; only
  `@IdempotencyTests` and `#assertIdempotent` remain un-exercised
  in a consumer context (see slot 6).
- **Adopter road-tests**: four rounds completed — `todos-fluent/`,
  `pointfreeco/`, `swift-nio/`, `swift-composable-architecture/`.
  The TCA round closed two of the three cluster-level gaps it
  surfaced (send-on-closure-parameter, dependency-client
  declarations). One remains open: the property-wrapper receiver
  resolver (see §3 below), deferred because the existing
  name+labels lookup suffices on today's corpus.
- **Road-test workflow**: reworked to be fork-authoritative (commit
  `bb69729`). Trial branches now live on `<upstream>-idempotency-trial`
  forks under the user's GitHub, not on ephemeral `/tmp` clones.
  Four forks provisioned so far:
  - `swift-composable-architecture-idempotency-trial` — **active**;
    carries the `trial-tca` branch (setup + `@DependencyClient`
    annotations + sandbox README banner) and has default-branch
    switched to `trial-tca`.
  - `hummingbird-examples-idempotency-trial`
  - `pointfreeco-idempotency-trial`
  - `swift-nio-idempotency-trial`
  The latter three are pre-provisioned (hardened: issues/wiki/projects
  disabled, sandbox description) but have no trial branch yet.
  Banner + default-branch switch apply per-round when a
  `trial-<slug>` branch lands. See `road_test_plan.md` for the
  full pre-flight recipe.
- **Macro-form end-to-end validation**: ticked on `todos-fluent`
  (attribute-form A/B supplement) and now on the webhook-handler
  sample (`IdempotencyKey` in a real consumer SPM). Two macros
  still un-exercised in consumer context:
  `@IdempotencyTests`, `#assertIdempotent` (see slot 6).

## Immediate candidates (small, concrete)

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
current evidence is pointfreeco-specific. Slot 9 (AWS Lambda
round) is the natural cross-adopter data point. Shape would
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

### 6. Macro-form validation: remaining surfaces

`IdempotencyKey` is now ticked by the webhook-handler sample
(`examples/webhook-handler-sample/`, commit `359db69`). Two
consumer-surface gaps remain:

- **`@IdempotencyTests` sample**: extension macro on a test type.
  Would need a small test-target example that applies
  `@IdempotencyTests` and asserts the generated tests compile
  and run. Natural home: a new sample under
  `examples/idempotency-tests-sample/` following the same
  shape as the webhook-handler sample.
- **`#assertIdempotent` sample**: freestanding expression macro
  that expands against `SwiftIdempotencyTestSupport`. Similar
  sample package would cover it.

Adopter-integration sub-path (carried over from the original slot 6):

- **Annotate a real webhook adopter** — add `IdempotencyKey` to
  pointfreeco's `handlePaymentIntent` (or similar). Refactor-heavy;
  requires running the code to confirm; crosses from measurement
  into production changes. Slot 9 (AWS Lambda) is probably a more
  natural fit since SQS message IDs are the canonical
  `@ExternallyIdempotent(by:)` case.

### 9. AWS Lambda adopter road-test

Fifth adopter round, targeting `apple/swift-aws-lambda-runtime`.
The original `CLAUDE.md` validation recommendation: every SQS/SNS
handler is objectively `@lint.context replayable`, so annotation
correctness is unambiguous — no judgement calls about what the
context should be.

**Pre-flight**: the `swift-aws-lambda-runtime-idempotency-trial`
fork does not exist yet — creating it (same recipe as the four
existing forks) is step 0 per `road_test_plan.md`'s fork-authoritative
workflow.

Value per session:

- **Cross-adopter evidence for slot 4.** If Lambda's
  `detach` / `runInBackground`-shape escape wrappers surface the
  same pattern pointfreeco's `fireAndForget` did, slot 4 lights up
  with two independent data points and can ship.
- **Cross-framework validation of PR #18.** Does the
  `@lint.framework` whitelist infrastructure generalize cleanly to
  a second framework, or does it need shape changes first?
- **Natural adopter for `IdempotencyKey` integration.** SQS message
  IDs are the canonical `@ExternallyIdempotent(by:)` case and tie
  slot 6's macro sample to a real adopter target down the line.
- **First dogfood of the fork-authoritative road-test workflow.**
  The procedure was rewritten in `road_test_plan.md` this session
  but has only been walked through on TCA retroactively; running
  a fresh round end-to-end exposes any rough edges in the
  documented recipe.

Produces: transcripts + retrospective under
`docs/swift-aws-lambda-runtime/`. Session-cost: 1-2 sessions,
similar to the TCA round.

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
swift-nio round with a cleaner dataset. The
`swift-nio-idempotency-trial` fork is already provisioned, so
the scan can run against a fresh clone of that fork per the new
road-test plan.

## Memory note

The Claude-Code memory at
`/Users/joecursio/.claude/projects/-Users-joecursio-xcode-projects-swiftIdempotency/memory/`
has three entries:

- `workflow_direct_to_main.md` — direct-to-main on solo repos
  for `SwiftIdempotency` + `SwiftProjectLint`. Linter rule
  slices keep the PR convention; docs and simple tweaks go
  straight to main.
- `project_validation_phase2.md` — after the false-positive
  rate settles on battle-tested projects, shift validation
  target to obscure single-contributor projects where latent
  idempotency issues are more likely to survive collective
  review.
- `project_trial_fork_naming.md` — adopter trial branches live
  on `<upstream>-idempotency-trial` forks (naming convention
  codified in `road_test_plan.md`).

## Recommended next-session opener

Three options, pick based on appetite:

- **Slot 9: AWS Lambda adopter road-test.** First real exercise
  of the fork-authoritative workflow. Requires creating the
  `swift-aws-lambda-runtime-idempotency-trial` fork as step 0
  (same recipe as the existing four). Produces cross-adopter
  evidence for slot 4 and cross-framework validation of PR #18.
  1-2 sessions.
- **Slot 8: swift-nio remeasurement.** Small and closes a loop.
  The fork is pre-provisioned, so the run is cheap. Expected
  null result; low info-value per unit of work, but ticks the
  box.
- **Slot 6 remaining samples: `@IdempotencyTests` or
  `#assertIdempotent`.** Similar scope to the webhook-handler
  sample that just shipped (~1-2 hours each). Finishes the
  macro-form validation story in consumer context.

Slot 5 (perf fix) and slot 3 (property-wrapper receiver resolution)
still have no immediate triggering evidence — wait for a corpus
that exhibits the pathology before committing a session to either.
