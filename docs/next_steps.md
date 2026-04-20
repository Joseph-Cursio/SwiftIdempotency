# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at `5698683`
  (post-PR #18 merge tip). PR status:
  - **PR #19 (open)** — closure-typed stored properties become effect
    declarations. `EffectSymbolTable.merge(source:)` now walks
    `VariableDeclSyntax` with function-typed annotations and feeds
    them through the same record path as `FunctionDeclSyntax`.
    Unblocks user annotations on `@DependencyClient` structs.
    Closes TCA cluster 4 (3-of-3 `search` / `forecast` / `fetch`
    fires) **conditional on the adopter annotating the client**.
    Annotations are in place on the trial-tca branch — re-run is
    cheap once PR #19 merges.
  - **PR #18 (merged)** — commit `5698683`: TCA send-closure-parameter
    whitelist. Post-Lambda-round evidence: the PR #18 bare-name
    override shape is TCA-specific. The earlier `idempotentReceiverMethodsByFramework`
    infrastructure (commit `040f186`, Hummingbird) is what
    generalises across frameworks — see slot 10.
- **Macros** (this repo): shipped; plus a new consumer sample at
  `examples/webhook-handler-sample/` (commit `359db69`) exercising
  `IdempotencyKey` end-to-end in a downstream SPM package. The
  `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`, `@IdempotencyTests`,
  `#assertIdempotent`, and `IdempotencyKey` surfaces ship; only
  `@IdempotencyTests` and `#assertIdempotent` remain un-exercised
  in a consumer context (see slot 6).
- **Adopter road-tests**: five rounds completed — `todos-fluent/`,
  `pointfreeco/`, `swift-nio/`, `swift-composable-architecture/`,
  `swift-aws-lambda-runtime/`. The TCA round closed two of the
  three cluster-level gaps it surfaced (send-on-closure-parameter,
  dependency-client declarations); the property-wrapper receiver
  resolver remains open (see §3 below). The Lambda round surfaced
  a new cluster — response-writer primitives (`write` / `finish`
  on `LambdaResponseWriter` / `LambdaResponseStreamWriter`) —
  scored as slot 10.
- **Road-test workflow**: reworked to be fork-authoritative (commit
  `bb69729`), first dogfooded end-to-end on the Lambda round
  this session. Trial branches live on `<upstream>-idempotency-trial`
  forks under the user's GitHub, not on ephemeral `/tmp` clones.
  Five forks provisioned so far:
  - `swift-composable-architecture-idempotency-trial` — **active**;
    carries `trial-tca` (setup + `@DependencyClient` annotations
    + banner), default-branch switched.
  - `swift-aws-lambda-runtime-idempotency-trial` — **active**;
    carries `trial-lambda` (6 handler annotations, banner),
    default-branch switched. Tip: `349725b`.
  - `hummingbird-examples-idempotency-trial`
  - `pointfreeco-idempotency-trial`
  - `swift-nio-idempotency-trial`
  The latter three are pre-provisioned (hardened: issues/wiki/projects
  disabled, sandbox description) but have no trial branch yet.
  Banner + default-branch switch apply per-round when a
  `trial-<slug>` branch lands. See `road_test_plan.md` for the
  full pre-flight recipe (now validated end-to-end — one gap
  surfaced, captured as a housekeeping item below).
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

### 4. Escape-wrapper recognition slice — **closed (pointfreeco-specific)**

`fireAndForget` (pointfreeco), `detach` / `runInBackground`
(AWS Lambda / Hummingbird-shape). The original hypothesis was
that these wrappers recurred across frameworks and deserved a
shared "trusted observational wrapper" whitelist.

**Negative result from slot 9.** The Lambda example corpus
contains zero escape-wrapper calls — `BackgroundTasks` uses
structured concurrency (inline post-`outputWriter.write(...)`
background work), not `Task { }` / `detach` / any wrapper. So
**`fireAndForget` is pointfreeco-specific, not a cross-framework
pattern.**

Downgrade to "don't generalise." The separate shape Lambda
surfaced — response-writer primitives — has its own receiver-method
whitelist path (see slot 10). If a future adopter genuinely does
surface `detach`/`runInBackground`, reopen and score; until then
this slot is closed.

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

### 9. AWS Lambda adopter road-test — **done**

Completed in one session. Artifacts:
[`swift-aws-lambda-runtime/trial-scope.md`](swift-aws-lambda-runtime/trial-scope.md),
[`trial-findings.md`](swift-aws-lambda-runtime/trial-findings.md),
[`trial-retrospective.md`](swift-aws-lambda-runtime/trial-retrospective.md),
[`trial-transcripts/`](swift-aws-lambda-runtime/trial-transcripts/).

Headlines: Run A 0 / 6, Run B 16 / 6 (all `Unannotated In Strict
Replayable Context`). One new cluster surfaced
(lambda-response-writer-gap — slot 10); slot 4 closed out as
pointfreeco-specific; protocol-method placement confirmed; one
template gap found and captured as housekeeping.

Target path drift: `apple/swift-aws-lambda-runtime` → `awslabs/…`
(captured as housekeeping).

### 10. Lambda response-writer framework whitelist — **done**

Landed on SwiftProjectLint main as `6c611c7`. Three entries added
to `idempotentReceiverMethodsByFramework` gated on
`import AWSLambdaRuntime`:

- `("outputWriter", "write")` — `LambdaResponseWriter<Output>` in
  `LambdaWithBackgroundProcessingHandler.handle` (BackgroundTasks).
- `("responseWriter", "write")` — `LambdaResponseStreamWriter` in
  `StreamingLambdaHandler.handle` (MultiSourceAPI, streaming).
- `("responseWriter", "finish")` — streaming stream-close on the
  same writer.

Identical shape to commit `040f186` (Hummingbird) — no inferrer
code changes needed. 11 new tests in `FrameworkWhitelistGatingTests`;
total suite 2246 / 275 green.

Follow-up **done in the same session**. Rerun against linter tip
`6c611c7` confirmed the expected 5 drop exactly: headline moved
from 16 / 6 (yield 2.67) to **11 / 6 (yield 1.83)**, with
`MultiSourceAPI` going fully silent under strict (0 / 1 silent
— the branch-join stress test from the scope doc resolving
cleanly). No other diagnostic changed, confirming the slice is
scoped exactly to the intended pair surface. Remaining 11 are
stdlib-gap (6), type-ctor-gap (5), correct-catch (2) — see
`swift-aws-lambda-runtime/trial-findings.md` §"Comparison to
pre-slot-10 baseline" for the per-line delta.

### 11. Housekeeping (small docs/config items) — **done**

All three items from slot 9's retrospective addressed in-session:

- **`road_test_plan.md` — per-Example-package scan. ✅**
  "Multi-package corpora" sub-bullet added under "Scan twice"
  with a shell recipe matching the `=== path ===` header
  convention.
- **`CLAUDE.md` — validation target update. ✅** Upstream path
  corrected (apple → swift-server → `awslabs/swift-aws-lambda-runtime`),
  v2.x corpus caveat recorded (no SQS/SNS examples; S3EventNotifier
  substitutes), and the "awslabs demos are an infrastructure
  smoke test, not an FP-rate corpus" distinction called out.
- **Claude Code hook scoping. ✅** The global PreToolUse
  `git commit` hook (`~/.claude/settings.json`) is now scoped to
  `$HOME/xcode_projects/*` so sandbox-fork commits in `/tmp` skip
  the session-start clean+test+lint. Environment fix; captured
  here as a breadcrumb if the hook ever gets rewritten.

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

### 8. Remeasure swift-nio with annotations under the new budget — **done**

Completed in one session. Artifacts updated in place:
[`swift-nio/trial-scope.md`](swift-nio/trial-scope.md),
[`trial-findings.md`](swift-nio/trial-findings.md),
[`trial-retrospective.md`](swift-nio/trial-retrospective.md),
[`trial-transcripts/`](swift-nio/trial-transcripts/).

Headlines: 4 handlers annotated across 3 example targets (echo /
chat-active / chat-read / HTTP1), corpus 549 files @ tag `2.98.0`.
Full-corpus Run A 0 / 4 and Run B 0 / 4 — **cleanest null in the
round set.** Scoped-per-target sums (2 / 40) reproduce the prior
round's NIOHTTP1Server numbers almost exactly, confirming the
scan completes consistently at both granularities.

One adoption-guidance finding (documentation-only, no slice):
scoped scans diverge from full-corpus results because body
inference resolves framework callees to `idempotent` only when
the module graph is visible. Scoped scans overcount; full-corpus
scans are the correct reference.

Slot 5 (real perf fix) remains deferred — the wall-clock budget
was not exercised at this corpus size (~95s scan).

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

One natural option remains:

- **Slot 6 remaining samples: `@IdempotencyTests` or
  `#assertIdempotent`.** Similar scope to the webhook-handler
  sample that just shipped (~1-2 hours each). Finishes the
  macro-form validation story in consumer context.

Slot 5 (perf fix) and slot 3 (property-wrapper receiver resolution)
still have no immediate triggering evidence — wait for a corpus
that exhibits the pathology before committing a session to either.
Slots 4, 8, 9, 10, and 11 are closed out (§4, §8, §9, §10, §11
above).
