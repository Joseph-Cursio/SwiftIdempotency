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
- **Adopter road-tests**: **thirteen rounds completed** —
  `todos-fluent/`, `pointfreeco/`, `swift-nio/`,
  `swift-composable-architecture/`, `swift-aws-lambda-runtime/`,
  `penny-bot/`, `isowords/`, `spi-server/`, `prospero/`,
  `myfavquotes-api/`, `hummingbird-examples-open-telemetry/`,
  **`luka-vapor/`**, **`hellovapor/`**. The TCA
  round closed **all three** cluster-level gaps it surfaced (return-
  trailing annotation, send-on-closure-parameter, dependency-client
  declarations) across PRs #17 / #18 / #19; current TCA residual on
  tip `bc3c05e` is 1 replayable / 13 strict, all in known cross-adopter
  noise/defensible clusters (`Duration` implicit-member, enum-case /
  `Result { }` constructors, `ContinuousClock.sleep`). The property-
  wrapper receiver resolver (slot 3) is a separate deferred slice,
  still open but no longer blocking TCA cluster 4. The Lambda round
  surfaced a new cluster — response-writer primitives
  (`write` / `finish` on `LambdaResponseWriter` /
  `LambdaResponseStreamWriter`) — scored as slot 10. **The Penny
  round (first production-app target) was the richest yet — 5/5
  handlers fire, 10 correct-catches, 4 distinct real-bug shapes
  (coin double-grant, OAuth error-path duplication, sponsor DM
  duplication, GHHooks error-path duplication). Every real-bug
  shape maps cleanly to `IdempotencyKey` / `@ExternallyIdempotent(by:)`
  — first real-adopter validation of the macro surface. Also
  surfaced a new linter-crash blocker on macOS `/tmp` symlink +
  duplicate file basenames — fixed as slot 12 on SwiftProjectLint
  `6200514`.** See
  [`penny-bot/trial-findings.md`](penny-bot/trial-findings.md).
  **The isowords round (second production-app target) answered the
  Penny-generalisation question: yield is codebase-dependent, not
  linter-dependent.** Post-slot-13 remeasurement (merge tip
  `2fbb171`): **5/5 handlers fire in Run A** (matching Penny),
  with 2 real-bug shapes (`insertSharedGame` + `startDailyChallenge`
  — duplicate-row inserts without `ON CONFLICT`, both caught in Run
  A). Isowords' PostgreSQL schema uses pervasive upsert guards, so
  5/8 Run A diagnostics are defensible-by-design once the SQL is
  read. **Six-for-six**: every real-bug shape across Penny +
  isowords (6 distinct shapes) maps to the `IdempotencyKey` /
  `@ExternallyIdempotent(by:)` surface. Round surfaced one
  adoption-gap slice that landed in-round (slot 13 — prefix-lexicon
  gap for `submit*` / `start*` / `complete*` / `register*`, PR #21
  merged as `2fbb171`) and one framework-whitelist candidate
  accumulating evidence (slot 14 — HttpPipeline `writeStatus`, now
  2-adopter, still deferred). See
  [`isowords/trial-findings.md`](isowords/trial-findings.md).
  **The SPI-Server round (third production-app target — Swift
  Package Index server, Vapor+Fluent+PostgreSQL) produced the
  first "no new slice" plateau.** 7 Run A / 39 Run B; 0 real-bug
  catches, 3 defensible (Fluent `.unique(on:)` Migration dedup +
  FS idempotent ops), 4 noise (all `AppMetrics.push` — Prometheus
  Pushgateway observational shape). **The fresh
  `AsyncCommand.run(using:signature:)` handler shape walked
  cleanly without a framework whitelist entry** — the receiver-
  agnostic symbol table handles it out of the box (quiet win for
  linter generality). Zero new named slices; **Completion
  Criterion #2 now at 1/3 consecutive plateaus.** New evidence-
  accumulating candidate: `AppMetrics.push` as Prometheus-
  Pushgateway observational shape (1-adopter). See
  [`spi-server/trial-findings.md`](spi-server/trial-findings.md).
  **The prospero round (fourth production-app target —
  `samalone/prospero`, first Hummingbird prod app, first phase-2
  / single-contributor target) was the second consecutive
  plateau — Completion Criterion #2 now at 2/3.** Run A 10 /
  Run B 62; **1 real-bug catch** (`ActivityPattern.save` on
  create — Migration lacks unique constraint; maps to
  `@ExternallyIdempotent(by:)`, 7-for-7 cross-adopter shape
  coverage). New evidence-accumulating candidate: slot 16 —
  **Hummingbird Router DSL whitelist** (`router.get/post` etc.
  on `Router` / `RouterGroup` receivers), 9 Run B fires, 1-
  adopter (originally reported as 14; 5 of those fires were
  actually chained-receiver `parameters.get` / `queryParameters.get`
  calls, corrected in the trial-findings post-mortem). Key
  **usability finding**: the enclosing-function
  annotation (`/// @lint.context` on `addXRoutes(to router:)`
  helpers) walks into trailing closures, which means Hummingbird
  adopters aren't blocked by the inline-trailing-closure gap —
  workaround is documented. See
  [`prospero/trial-findings.md`](prospero/trial-findings.md) and
  the updated
  [`ideas/inline-trailing-closure-annotation-gap.md`](ideas/inline-trailing-closure-annotation-gap.md).
  **The myfavquotes-api round (fifth production-app target —
  `kicsipixel/myfavquotes-api`, second Hummingbird adopter,
  second phase-2 / single-contributor target, full
  Postgres+Fluent+Bearer auth) was the third consecutive
  plateau — Completion Criterion #2 closes at 3/3 → SHIP.**
  Run A 5 / Run B 13; **1 real-bug catch**
  (`UsersController.login` token persistence — `Token.generate`
  uses `Int.random` × 8 per call, so retries persist N stale
  tokens with 1h TTL; maps to `IdempotencyKey` /
  `@ExternallyIdempotent(by:)`, **8-for-8 cross-adopter shape
  coverage**). Two policy notes folded into `road_test_plan.md`:
  (a) handler-binding-shape determines annotation target —
  method-reference (`use: self.show`) annotate the func decl,
  inline-trailing-closure annotate the registration helper;
  (b) Fluent `.unique(on:)` migrations are the SQL-ground-truth
  shortcut for create-handler defensibility. Slot 16 stayed at
  1-adopter — myfavquotes-api uses method-reference handler
  binding, not inline closures, so the registration helpers
  weren't on the annotation surface. New 1-adopter candidate
  (Bcrypt-crypto-gap, 1 fire) logged for evidence accumulation
  but not slice-promoted. **All three road-test completion
  criteria are now met (framework coverage ✅, adoption-gap
  stability ✅, macro-form evidence ✅).** See
  [`myfavquotes-api/trial-findings.md`](myfavquotes-api/trial-findings.md).
  **The hummingbird-examples/open-telemetry round (first
  slice-driven round post-criteria-close — targeting slot 16
  promotion) closed slot 16 at 2-adopter ship-eligibility.**
  Run A 1 / Run B 12; zero real-bug catches (no persistence in
  this OTel demo). 1× `router.post` Run A fire + 2× `router.get`
  Run B fire match prospero's two-path cluster shape exactly;
  slot 16 advances from 1-adopter (prospero-only) to 2-adopter
  → **shipped as SwiftProjectLint PR #23 (`29e9069`)** in the
  same session. Four new 1-adopter below-threshold candidates
  surfaced incidentally (`addMiddleware`, `queryParameters.require`
  sibling-pair gap, Swift Distributed Tracing `withSpan`,
  Swift Concurrency `Task.sleep`/`Duration.seconds`); none
  ship-eligible, all parked for next-round observation. See
  [`hummingbird-examples-open-telemetry/trial-findings.md`](hummingbird-examples-open-telemetry/trial-findings.md).
- **Road-test workflow**: reworked to be fork-authoritative (commit
  `bb69729`), first dogfooded end-to-end on the Lambda round
  this session. Trial branches live on `<upstream>-idempotency-trial`
  forks under the user's GitHub, not on ephemeral `/tmp` clones.
  Seven forks provisioned so far:
  - `swift-composable-architecture-idempotency-trial` — **active**;
    carries `trial-tca` (setup + `@DependencyClient` annotations
    + banner), default-branch switched.
  - `swift-aws-lambda-runtime-idempotency-trial` — **active**;
    carries `trial-lambda` (6 handler annotations, banner),
    default-branch switched. Tip: `349725b`.
  - `penny-bot-idempotency-trial` — **active**; carries
    `trial-penny-bot` with `49db411` (Run A state, replayable)
    and `c309bcb` (Run B tip, strict_replayable). Default-branch
    switched. Fork hardened per recipe.
  - `isowords-idempotency-trial` — **active**; carries
    `trial-isowords` with `a71c993` (Run A state, replayable)
    and `4e3cc83` (Run B tip, strict_replayable). Default-branch
    switched. Fork hardened per recipe.
  - `SwiftPackageIndex-Server-idempotency-trial` — **active**;
    carries `trial-spi-server` with `57f11d727` (Run A state,
    replayable) and `c57b424b8` (Run B tip, strict_replayable).
    Default-branch switched. Fork hardened per recipe.
  - **`prospero-idempotency-trial` — active**; carries
    `trial-prospero` with `353753f` (Run A state, replayable) and
    `56d676f` (Run B tip, strict_replayable). Default-branch
    switched. Fork hardened per recipe.
  - **`myfavquotes-api-idempotency-trial` — active**; carries
    `trial-myfavquotes` with `8ae0c78` (Run A state, replayable)
    and `579c1a4` (Run B tip, strict_replayable). Default-branch
    switched. Fork hardened per recipe.
  - **`hummingbird-examples-idempotency-trial` — active**; carries
    `trial-open-telemetry` with `9a7edb8` (Run A state, replayable)
    and `674935a` (Run B tip, strict_replayable). Banner at
    `9b5a662`. First slice-driven round; targeted slot 16
    promotion on the `open-telemetry/` subdirectory.
  - `pointfreeco-idempotency-trial`
  - `swift-nio-idempotency-trial`
  The latter two are pre-provisioned (hardened: issues/wiki/projects
  disabled, sandbox description) but have no trial branch yet.
  Banner + default-branch switch apply per-round when a
  `trial-<slug>` branch lands. See `road_test_plan.md` for the
  full pre-flight recipe (now validated end-to-end — two gaps
  surfaced so far, both captured as housekeeping items below).
- **Macro-form end-to-end validation**: complete. Ticked on
  `todos-fluent` (attribute-form A/B supplement), on the
  webhook-handler sample (`IdempotencyKey`), on the
  idempotency-tests sample (`@IdempotencyTests` extension-role
  expansion compiles + runs green under Swift Testing in a
  downstream package), and on the assert-idempotent sample
  (`#assertIdempotent` overload resolution + effect propagation
  verified at consumer call sites).

## Immediate candidates (small, concrete)

### 2. `.init(...)` member-access form gap — **done (PR #20)**

Landed as commit `bc3c05e` on SwiftProjectLint. `HeuristicEffectInferrer.
callParts` now normalises `Type.init(...)` → `(TypeName, nil)` via a
new `typeIdentifierName(of:)` helper that peels nested types and
generic specialisations. Purely additive — every downstream consumer
(whitelist lookup, inference reason, upward inferrer) benefits
automatically. +10 tests → 2270/275 green.

TCA post-#19 re-run confirms no regression: the Duration constructors
on the TCA corpus are implicit-member-access (`.milliseconds(100)`),
not `Type.init(...)`, so PR #20 doesn't affect them either way. Effect
on adopter corpora to be confirmed on the next round that scans a
codebase using the `.init(...)` spelling on whitelisted types.

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

### 6. Macro-form validation: remaining surfaces — **done**

All three consumer-surface gaps closed in one session:

- **`IdempotencyKey`** — `examples/webhook-handler-sample/`
  (commit `359db69`).
- **`@IdempotencyTests`** — `examples/idempotency-tests-sample/`.
  `@Suite @IdempotencyTests` on a three-member type; the
  extension-role expansion produces three generated `@Test` methods
  (sync, sync-value-return, async) that Swift Testing picks up as
  ordinary test declarations. All five tests (3 generated + 2
  hand-written direct) pass under `swift test`.
- **`#assertIdempotent`** — `examples/assert-idempotent-sample/`.
  Four call sites, one per row of the sync/async × throwing/pure
  effect matrix, all green. **One doc-drift finding**: the
  freestanding macro's runtime helpers (`__idempotencyAssertRunTwice`,
  `__idempotencyAssertRunTwiceAsync`) actually live in the public
  `SwiftIdempotency` target, not in `SwiftIdempotencyTestSupport` as
  the original slot description implied — consumers only need a
  single `import SwiftIdempotency`. `SwiftIdempotencyTestSupport`
  is currently a placeholder; confirmed by the sample's
  `Package.swift` (no dependency on that product).

The adopter-integration sub-path (annotating a real webhook adopter
with `IdempotencyKey`) remains a distinct, refactor-heavy move that
crosses from measurement into production changes. Parked alongside
slot 7 below; pursue as an adopter-engagement activity, not a
macro-coverage task.

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

### 12. Linter crash on duplicate file basenames — **done (SwiftProjectLint `6200514`)**

Surfaced in the Penny round on the first scan attempt:
`Fatal error: Duplicate values for key: 'Errors.swift'`.
`ProjectLinter.makeProjectFile` computed `relativePath` via
`filePath.hasPrefix(projectRoot + "/")`. On macOS, passing
`/tmp/penny-scan` as `projectRoot` failed the `hasPrefix` check
because filesystem enumeration returns
`/private/tmp/penny-scan/…` (the `/tmp` symlink resolves to
`/private/tmp`). The fallback was
`(filePath as NSString).lastPathComponent` — a bare filename.
Downstream, `applyInlineSuppression` built
`Dictionary(uniqueKeysWithValues: …)` keyed by that bare
filename; any adopter with duplicate filenames across targets
crashed. Penny has 11 such collisions (`Errors.swift`×3,
`Constants.swift`×4, `+String.swift`×3, etc.).

**Fix landed as SwiftProjectLint commit `6200514`:**

- Canonicalise both `projectRoot` and `filePath` via
  `URL.resolvingSymlinksInPath()` before the `hasPrefix`
  comparison (root cause).
- Fall back to the full resolved path (not `lastPathComponent`)
  when `hasPrefix` fails (uniqueness preservation).
- Make `applyInlineSuppression`'s `Dictionary` init use
  `uniquingKeysWith: { first, _ in first }` as a defensive
  belt-and-suspenders against any future collision.
- +2 tests in
  `Tests/CoreTests/Suppression/SymlinkAndDuplicateBasenameTests.swift`
  covering the non-canonical `/tmp/…` root path (macOS-gated)
  and the canonical-root defensive-dedup path. Full suite 2272 / 276.

Unblocks any multi-target macOS scan with duplicate file basenames
(Penny, vapor core, hummingbird full, NIO full). No further action
required on this slot.

### 13. Prefix-lexicon gap for server-app verbs — **done (SwiftProjectLint `2fbb171`)**

Shipped as branch `slot13-prefix-lexicon` → **PR #21** → merge
commit **`2fbb171`** (2026-04-21). `submit`, `start`, `complete`,
`register` added to `HeuristicEffectInferrer.nonIdempotentNames`
(+docstring update). `send` was already there. Bare-name +
camelCase-gated prefix-match, identical treatment to the existing
`create|insert|update|delete` entries. Linter test suite:
2272 → 2286 (+14 new).

**Measured deltas at merge tip `2fbb171`:**

- **Isowords Run A**: 5 → 8 diagnostics; 4/5 → **5/5 handlers
  fire**. Predicted outcome reproduced exactly:
  - +1 correct catch: `startDailyChallenge` at
    `DailyChallengeMiddleware.swift:117` (the Run A real-bug miss
    recovered — **100% recall at merge tip**).
  - +2 defensible: `submitLeaderboardScore` at `:112`,
    `completeDailyChallenge` at `:149` (both upsert-backed;
    adopter annotation closes).
  See
  [`isowords/trial-findings.md`](isowords/trial-findings.md)
  §"Run A — replayable context" for the updated 8-row audit.
- **Isowords Run B**: 162 → 162 total (unchanged); rule
  distribution reshuffles from 157/5 (`[Unannotated]`/`[Non-Idempotent]`)
  to 154/8 as the 3 prefix additions reclassify across tiers.
  No regression.
- **TCA regression check**: 13 strict → 13 strict (per-example:
  Todos 5 / Search 4 / CaseStudies 4 — all unchanged). No TCA
  handler's transitive call graph contains a `submit*` /
  `start*` / `complete*` / `register*` method. No update needed
  to `swift-composable-architecture/trial-findings.md`.

The `IdempotencyKey` / `@ExternallyIdempotent(by:)` macro-surface
cross-adopter tally is now **6/6 real-bug shapes** across Penny
(4) + isowords (2), with isowords' Run A handler coverage
matching Penny's at 5/5.

### 14. `HttpPipeline` framework whitelist — **done (SwiftProjectLint `698081e`)**

Shipped as branch `slot14-httppipeline-whitelist` → **PR #22** →
merge commit **`698081e`**. `writeStatus` and `respond` added to
`idempotentMethodsByFramework` gated on `import HttpPipeline`.
Different table than originally predicted — these are
**freestanding curried functions** in `pointfreeco/swift-web`
called via `|>` / `>=>` pipe-forward composition, not receiver-
method calls — so the bare-name `idempotentMethodsByFramework`
table was the right home, not `idempotentReceiverMethodsByFramework`.

Also introduced a per-framework reason-phrasing hook
(`idempotentMethodPhrasingByFramework`) with `"framework primitive"`
default. FluentKit phrasing (`"query-builder read"`) preserved
exactly so the existing reason-string assertion at
`FrameworkWhitelistGatingTests.swift:366` stays green.

**Measured deltas at slice tip `698081e`:**

- **Isowords Run B**: 162 → **152 (−10)**. Exactly matches the
  10 `writeStatus` diagnostics that were firing.
- **pointfreeco www Run B**: 38 → **23 (−15)**. 9 direct (5
  `writeStatus` + 4 `respond`) plus a **6-diagnostic multiplier**
  from transitive inference — `stripeHookFailure` ×3,
  `validateStripeSignature` ×2, `fetchGift` ×1 resolve to
  idempotent once their bodies' `writeStatus`/`respond` calls
  classify cleanly. Slot 14 is the first slice to surface a
  measurable transitive-multiplier effect from a framework
  whitelist; the same pattern likely applies to slot 10
  (Lambda response-writer) on a richer Lambda corpus.

Linter test suite: 2286 → **2295 (+9 new)**. Same shape as slot 10
(Lambda response-writer) and `040f186` (Hummingbird primitives) —
no inferrer-core changes needed. See per-adopter pre/post
comparison sections in
[`isowords/trial-findings.md`](isowords/trial-findings.md) and
[`pointfreeco/trial-findings.md`](pointfreeco/trial-findings.md).

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

### 15. Housekeeping from isowords retrospective — **done**

Both template-fold items from
[`isowords/trial-retrospective.md`](isowords/trial-retrospective.md)
§"Policy notes" landed in `road_test_plan.md`:

- **SQL ground-truth audit pass** — new subsection under "Audit"
  titled "SQL ground-truth pass (DB-heavy adopters)". Enumerates
  the four SQL shapes that flip a "correct catch" to
  "defensible by design" (`ON CONFLICT DO UPDATE`,
  `ON CONFLICT DO NOTHING`, `WHERE col IS NULL` guard,
  unique-indexed `INSERT ... RETURNING *`). Cites the isowords
  Run A scoring-correction evidence and notes Penny-style
  DynamoDB-bare-writes as the contrast case.
- **git-lfs pre-flight note** — added to the "Pre-flight" section
  with the `git -c filter.lfs.*=` bypass clone command, explicit
  note that LFS-tracked assets are binary (never Swift sources)
  so the linter doesn't need them, and guidance on when to
  actually install `git-lfs` vs. use the bypass.

Ready for the next DB-heavy / LFS-using adopter round without
re-discovering either gap from scratch.

## Follow-ups on what we found

### 7. Verify the pointfreeco findings — **done (runtime-path read)**

Completed in one session. Artifact:
[`pointfreeco/slot7-runtime-verification.md`](pointfreeco/slot7-runtime-verification.md).

Headline: **the linter is catching real bugs.** None of the three
defang hypotheses (Stripe event-ID dedup, `gift.delivered` guard,
DB-level constraints on the UPDATE path) hold for the email-send
patterns — no `processed_events` table exists, `handlePaymentIntent`
gates on `gift.deliverAt` (a configuration field, not the
`delivered` mutation flag), and `sendGiftEmail` has no internal
dedup. The two `update*` DB diagnostics *are* defanged by
overwrite-idempotent UPDATE semantics; that's an adopter-side
annotation matter, not a business-logic concern.

Per-site verdicts in the artifact. Finding #1 (`sendGiftEmail` in
`handlePaymentIntent`) is the clearest user-visible bug with a
one-line fix (`&& !gift.delivered`). Findings #2–#4 are correct
flags but low-impact (admin alert noise, or Stripe-retry email
policy that's pointfreeco's call to make).

Follow-on — **parked in ideas/**: opening a narrowly-scoped triage
issue on pointfreeco for finding #1 only is a publicly-visible
action gated on user approval; moved to
[`ideas/pointfreeco-triage-issue.md`](ideas/pointfreeco-triage-issue.md)
with a promotion trigger.

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

Seven production-app rounds complete (Penny, isowords, SPI-Server,
prospero, myfavquotes-api, **luka-vapor**, **hellovapor**). **All
three road-test completion criteria are met since myfavquotes-api;
rounds since are slice-driven.**

1. ✅ **Framework coverage** — Vapor (todos-fluent + SPI-Server +
   pointfreeco), Hummingbird (prospero + myfavquotes-api),
   SwiftNIO (swift-nio), Point-Free (pointfreeco + TCA).
2. ✅ **Adoption-gap stability — 3/3 consecutive plateaus**
   (spi-server + prospero + myfavquotes-api closed at this round).
3. ✅ **Macro-form evidence** — three consumer samples in
   `examples/` exercise `IdempotencyKey` / `@IdempotencyTests` /
   `#assertIdempotent` end-to-end; root tests cover the four
   attribute macros.

Per `road_test_plan.md` §"Completion criteria": *"Continue the
template even after completion criteria are met — future linter
slices still get validated the same way. The plan stays alive;
it just stops blocking on new targets."* So future rounds become
**slice-driven** (validate a specific linter change) rather than
**criterion-driven** (close a ship gate). Options, in
value-per-effort order:

- **Slot 16 (Hummingbird Router DSL whitelist) — shipped
  (SwiftProjectLint `29e9069`, PR #23).** Five receiver-method
  pairs `(router, get|post|put|patch|delete) → Hummingbird`
  added to `idempotentReceiverMethodsByFramework`. Re-scans at
  slot-16 tip vs. slot-14 tip: prospero Run B **−9**, open-telemetry
  Run B **−3**, open-telemetry Run A **−1** — deltas match DSL
  call counts exactly. +11 tests; suite 2295 → 2306 green.
  Trial tips pinned: prospero `56d676f`, open-telemetry `674935a`.
  Prospero's 5-fire `(parameters|queryParameters, get)` cluster
  (surfaced during the slot-16 re-attribution; see the prospero
  trial-findings correction post-mortem) is logged as a new
  1-adopter candidate for a sibling-pair extension but does not
  ship with slot 16.
- **Cross-adopter triage filing** — eight real-bug shapes have
  been documented across five adopters. Penny's four shapes are
  parked in [`ideas/penny-bot-triage-issues.md`](ideas/penny-bot-triage-issues.md);
  isowords' two, prospero's one, and **myfavquotes-api's one
  (`UsersController.login` token-persistence)** could be similarly
  parked. Filing publicly is user-gated (not auto-promoted);
  surfacing them as a batch is one option for adopter engagement.
- **`AppMetrics.push` / Prometheus Pushgateway shape — closed
  (SPI-Server-specific).** Penny re-scan at slot 14 tip
  (`698081e`) returned **0 `push` fires, 0 AppMetrics references**.
  Penny Run B unchanged at 71 issues (no slot 14 regression).
  Penny uses CloudWatch via Lambda runtime + swift-log, not
  Prometheus. Shape stays at 1-adopter; won't promote without a
  third Vapor+Prometheus adopter (unlikely soon).
- **Bcrypt-crypto-gap** (1-adopter, 1 fire from myfavquotes-api).
  Single-fire shape — only matters if a future Hummingbird/Vapor
  adopter with auth flows fires the same shape and pushes to
  2-adopter slice volume. No action until then.
- **Slot 17 (Vapor routing DSL whitelist) — shipped
  (SwiftProjectLint `e38df30`, PR #24 merged 2026-04-22).** Five receiver-
  method pairs `(app, get|post|put|patch|delete) → Vapor` added
  to `idempotentReceiverMethodsByFramework` with `FrameworkWhitelist.vapor`
  constant. Re-scans at slot-17 tip:
  - **luka-vapor Run A** 4 → **2** (−2 `app.post`), **Run B**
    52 → **49** (−3: 2 `app.post` carried + 1 `app.get` strict).
  - **hellovapor Run A** 5 → **4** (−1 `app.post`), **Run B**
    25 → **19** (−6: 1 `app.post` carried + 5 `app.get` strict).
  - Combined: 9 fires silenced across 2 adopters, matching the
    predicted 2-adopter delta exactly.
  +11 tests; suite 2306 → **2317 green**. Trial tips pinned:
  luka-vapor `f2e5d09`, hellovapor `4b2bea2`. Scope corrected
  mid-round from 4 verbs to 5 after hellovapor's strict-mode
  evidence (5× `app.get` Run B fires) confirmed the `app.get`
  strict-only asymmetry — see
  [`docs/luka-vapor/trial-findings.md`](luka-vapor/trial-findings.md)
  §"Run B correction" and
  [`docs/hellovapor/trial-findings.md`](hellovapor/trial-findings.md)
  §"Slot-17 2-adopter evidence summary".
  - **Two new 1-adopter candidates surfaced in the slot-17 round:**
    - **`(app, register) → Vapor`** — hellovapor's 4 `register(collection:)`
      fires in Run A. Structural sibling to slot 17. Needs a
      second Vapor adopter using `register(collection:)` before
      promoting; luka-vapor has zero.
    - **`(Route, description) → Vapor`** — hellovapor's 5 Vapor
      `.description("...")` OpenAPI-metadata chain calls in Run B.
      Observational shape (metadata attachment). Needs a second
      adopter.

- **Slot 18 (parameters.get / queryParameters.get whitelist) —
  shipped (SwiftProjectLint `db4d576`, PR #25 merged 2026-04-22).**
  Two sibling whitelist entries for URL-parameter retrieval by name:
  - **`(parameters, get) → {Hummingbird, Vapor}`** — cross-framework
    entry in a new second table `idempotentReceiverMethodsMultiFramework`
    (`[String: [String: Set<String>]]`) consulted after the existing
    single-framework table. Qualifies when ANY candidate framework
    is active. Receiver identifier is common convention across both
    frameworks; import gate remains the precision mechanism.
  - **`(queryParameters, get) → Hummingbird`** — additive entry on
    the existing single-framework table, Hummingbird-scoped
    (`queryParameters` isn't a Vapor idiom — Vapor uses `req.query`).
  - Re-scans at slot-18 tip vs. slot-17 tip (strict_replayable):
    - **prospero Run B** 53 → **48** (−5: 4× `context.parameters.get`
      + 1× `request.uri.queryParameters.get`).
    - **hellovapor Run B** 19 → **18** (−1: 1× `req.parameters.get("name")`).
    - Combined: **6 fires silenced across 2 adopters, cross-
      framework coverage.**
  +11 tests; suite 2317 → **2328 green**. Trial tips unchanged from
  slot 17 (prospero `56d676f`, hellovapor `4b2bea2`).
  **Design note:** the new multi-framework table is the first
  cross-framework data-structure in the inferrer; leaves the existing
  `[String: [String: String]]` untouched. Open for future entries if
  other receivers turn out to be shared-convention (e.g. `request.body`,
  `content.decode`) across multiple web frameworks.

- **Cross-adopter triage filing** — ten real-bug shapes documented
  across six adopters. **Two filed this session:**
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

- **`AppMetrics.push` / Prometheus Pushgateway shape — closed
  (SPI-Server-specific).** Penny re-scan at slot 14 tip
  (`698081e`) returned 0 `push` fires. Shape stays at 1-adopter;
  won't promote without a third Vapor+Prometheus adopter.

- **Bcrypt-crypto-gap** (1-adopter, 1 fire from myfavquotes-api).
  Single-fire shape — only matters if a future Hummingbird/Vapor
  adopter with auth flows fires the same shape. No action until
  then.

- **Axiom `emit` observability pattern** (1-adopter from
  luka-vapor, mirrors SPI-Server's `AppMetrics.push` shape).
  Same verdict as Prometheus Pushgateway — each observability
  library is its own receiver; defer until 2-adopter evidence.

- **Package release prep (v0.1.0 → SPI submission) — in flight.**
  Apache-2.0 license landed (SwiftIdempotency `13b1a24`); README
  pre-release review prompted a new
  [`package_adoption_test_plan.md`](package_adoption_test_plan.md)
  workstream distinct from the linter road-tests. Progress:
  - **luka-vapor package trial** (`d9e8c1e`) — first adopter-
    integration validation. Migrated `start-live-activity` handler;
    5/5 tests pass; confirmed Option C pathology on `HTTPStatus.ok`
    returns as P0 finding; build-time delta within noise. README
    updated (`34cd52f`) with Option C pathology section, inline-
    closure migration guide, and `SwiftIdempotencyTestSupport`
    stale-ref fix. See
    [`luka-vapor-package-trial/`](luka-vapor-package-trial/).
  - **hellovapor package trial** (`ca29198`) — second adopter-
    integration, Fluent-Model counter-case. Migrated `createAcronym`
    handler; 5/5 tests pass; surfaced **four new findings** — two
    P0 on `IdempotencyKey(fromEntity:)` constraints (Fluent `Model`
    not `Identifiable`, `CustomStringConvertible` rejecting Optional
    IDs), one P1 linter gate mismatch (see slot 19 below), one P3
    filename collision. Option C working set characterised across
    both trials: sharp on synthesised-`Equatable` struct returns;
    blind on trivial returns (`HTTPStatus.ok`, `Void`) and on non-
    Equatable class returns without adopter workarounds. See
    [`hellovapor-package-trial/`](hellovapor-package-trial/).
  - **README "Using with Fluent ORM" section** (`0477b2f`) —
    v0.1.0 documentation blocker cleared. Three-pattern section:
    header-sourced `init(fromAuditedString:)` as the idiomatic
    path (with the create-handler bootstrap-problem rationale),
    `IdentifiableAcronym`-style adapter struct for post-save
    handlers (bridges the `Identifiable` + Optional-`UUID?` gaps
    in one), and tuple-return workaround for `#assertIdempotent`
    on non-Equatable Model references. Patterns drawn from the
    hellovapor trial (5/5 tests passing); links to both trial
    artifacts at the section foot.
  - **Third trial — synthetic SwiftData** (2026-04-23). AmpFin
    real-adopter attempt pivoted mid-baseline after ~30 min of
    Swift-6.3 `@Model`-toolchain-drift friction unrelated to the
    API question; pivoted to a fresh synthetic at
    [`examples/swiftdata-sample/`](../examples/swiftdata-sample/)
    per the test plan's option #3. Trial artifacts:
    [`docs/synthetic-swiftdata-package-trial/`](synthetic-swiftdata-package-trial/)
    and the AmpFin attempt at
    [`docs/ampfin-package-trial/`](ampfin-package-trial/). 8/8
    tests green. Deciding question answered: `IdempotencyKey(fromEntity:)`
    **reaches SwiftData `@Model` with user-declared `var id:
    String` cleanly** and reaches plain reference-type
    `Identifiable` with `let id: String` trivially. The Optional-ID
    pattern from Fluent is **Fluent-specific**, not recurring.
    API decision: **add a Fluent-shaped constructor post-v0.1.0,
    do NOT relax the global `CustomStringConvertible` constraint**.
    One P0 doc finding: the hellovapor-trial-documented tuple-
    wrapping workaround for `#assertIdempotent` on non-Equatable
    `@Model` returns doesn't compile (tuples don't conform to the
    `Equatable` *protocol*, only have synthesised `==`). **README
    §"Using with Fluent ORM" fixed in the same session** — the
    §"`#assertIdempotent` on Model returns" subsection now
    recommends a dedicated Equatable `struct` projection with
    the exact compile-error excerpt adopters would see if they
    try the old tuple pattern. Hellovapor trial-findings.md
    annotated in-place with a post-publication correction note.
    Completion criteria per the test plan: **three adopter
    integrations complete (luka-vapor + hellovapor + synthetic)**,
    **no new P0 API-change requirements** (only a doc fix, not
    an API shape change), **linter parity confirmed** on
    luka-vapor/hellovapor — package-adoption-test-plan bar **met
    for v0.1.0**.
  - **Pending post-v0.1.0:** dedicated Fluent-shaped constructor
    on `IdempotencyKey` (e.g. `init(fromFluentModel:)` or
    `init(fromFluentID:)` — design TBD). Must route through
    `FluentKit` as a conditional dep and not break existing
    `fromEntity:` callers. Requires a FluentKit real-adopter
    validation (hellovapor re-run) before merging. See
    [`synthetic-swiftdata-package-trial/trial-retrospective.md`](synthetic-swiftdata-package-trial/trial-retrospective.md)
    §"P2 — design `init(fromFluentID:)`" for design
    considerations.
  - **Pending post-v0.1.0:** current-toolchain SwiftData
    real-adopter trial. TeymiaHabit (pushed 2026-04-19),
    vreader (2026-04-04), or similar fresh-toolchain SwiftData
    adopter. Requires xcodebuild+simulator methodology (no
    candidate has a top-level `Package.swift`). Not release-
    blocking — the synthetic closed the API question; this
    trial fills the external-adoption-signal gap. Fold a
    `pushedAt > 2026-02-01` candidate-freshness filter into the
    test plan first.
  - **Pending post-v0.1.0:** Option B (dep-injected mock effects)
    promotion from deferred. Would catch the non-idempotency shapes
    Option C is blind to — the characterisation above gives concrete
    design constraints for what Option B would need to verify.

- **Slot 19 (FluentKit `import Fluent` alias) — shipped
  (SwiftProjectLint `70f2d61`, PR #26 merged 2026-04-22).**
  Single alias entry (`fluent: ["Fluent"]`) in a new
  `frameworkImportAliases` table, consulted from the single-site
  `FrameworkContext.isFrameworkActive` gate. Canonical framework
  name remains the single identity — reason strings still say
  `FluentKit`, `enabledFrameworks` config still gates by canonical
  name, all nested whitelist tables still key on canonical; the
  alias is purely an import-gate convenience. Surfaced by the
  hellovapor package trial — `save(on:)` under `import Fluent` was
  going silent until the gate was aliased.
  - **hellovapor Run A** 4 → **5** (+1 correct-catch: `save(on:
    req.db)` at `routes.swift:34` — the Acronym-uniqueness bug
    already filed as `sinduke/HelloVapor#1`; previously silent
    under `import Fluent` because the FluentKit gate didn't match
    the import spelling).
  - **hellovapor Run B** 18 → **18** (same line reclassifies from
    `[Unannotated In Strict Replayable Context]` fallback to the
    typed `[Non-Idempotent In Retry Context]` via FluentKit ORM
    verb — precision uplift, count unchanged).
  - **Non-regression verified** on luka-vapor / myfavquotes-api /
    prospero trial clones via `import Fluent` grep: zero files
    (all three use `import FluentKit` directly, which the existing
    gate already handled).
  +10 tests; suite 2328 → **2338 green**. Trial tip unchanged
  (hellovapor `4b2bea2`). Shape: same data-table addition as slots
  13–18; lowest-cost slice shipped so far.

Deferred — no urgent triggering evidence:

- Slot 5 (perf fix) — no corpus has stressed the wall-clock
  budget. luka-vapor + hellovapor both scanned instantly.
- Slot 3 (property-wrapper receiver resolution) — no adopter
  round has surfaced a same-name method collision with
  differing tiers.

**Ten real-bug shapes across Penny + isowords + prospero +
myfavquotes-api + luka-vapor + hellovapor** all map to
`IdempotencyKey` / `@ExternallyIdempotent(by:)`. **10-for-10
macro-surface coverage across six production adopters.**

Slots 2, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 are
closed out. **No named linter slice is queued** — next candidates
are all still 1-adopter and awaiting second-adopter evidence
(Vapor `register(collection:)`, Vapor `Route.description`,
Hummingbird `addMiddleware`, Hummingbird `queryParameters.require`
sibling-pair, Swift Distributed Tracing `withSpan`, Swift
Concurrency `Task.sleep` / `Duration.seconds`, Bcrypt-crypto-gap,
`AppMetrics.push` Prometheus-Pushgateway, Axiom `emit`). Package-
side v0.1.0 release prep is the next queued SwiftIdempotency
workstream — see the "Package release prep" bullet above for the
full slice list. Slot 7's publicly-visible follow-on is parked in
[`ideas/pointfreeco-triage-issue.md`](ideas/pointfreeco-triage-issue.md).
