# swift-aws-lambda-runtime — Trial Findings

Measurement output for the fifth adopter road-test. Scope + pinned
context live in [`trial-scope.md`](trial-scope.md). Transcripts:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt),
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

## Headline

| | Count |
|---|---|
| Handlers annotated | 6 |
| Run A (`@lint.context replayable`) diagnostics | **0** |
| Run B (`@lint.context strict_replayable`) diagnostics | **11** |
| Silent handlers (replayable) | 6 of 6 |
| Silent handlers (strict) | 1 of 6 (`MultiSourceAPI`) |
| Audit cap | 30 |
| Cap exceeded | no |

Run A yield: `0 / 6 = 0.00` — no catches in plain replayable mode.
Run B yield: `11 / 6 = 1.83` — one handler (`MultiSourceAPI`) now
silent under strict; the remaining five surface at least one
unannotated-callee diagnostic each.

**Measurement note.** The numbers above are the **post-slot-10**
rerun against linter tip `6c611c7` (commit "Framework whitelist:
AWSLambdaRuntime response-writer primitives"). The original
baseline against tip `5698683` produced `16 / 6 = 2.67` with
`MultiSourceAPI` at 4/0 silent; the slice closed the
`lambda-runtime-writer-gap` cluster of 5 diagnostics (`write`×3 +
`finish`×2 on `outputWriter` / `responseWriter`) exactly as
predicted. See the §Comparison to pre-slot-10 baseline section
below for the raw delta.

## Run A — replayable

Six handlers, `/// @lint.context replayable` applied, fresh clone
of the fork at `f62d123`. Per-Example-package scan:

| # | Example package | Handler | Diagnostics |
|---|---|---|---|
| 1 | `S3EventNotifier` | trailing closure (`LambdaRuntime { (event: S3Event, …) }`) | 0 |
| 2 | `BackgroundTasks` | `BackgroundProcessingHandler.handle` | 0 |
| 3 | `S3_Soto` | top-level `handler(event:context:)` | 0 |
| 4 | `MultiSourceAPI` | `MultiSourceHandler.handle` (streaming) | 0 |
| 5 | `APIGatewayV2` | trailing closure | 0 |
| 6 | `Testing` | `MyHandler.handler` | 0 |

**Reading.** Plain replayable mode flags only calls inferred as
`non_idempotent`. Lambda example code is dominated by framework
primitives (`context.logger.*`, response-writer methods), type
constructors (`APIGatewayV2Response(...)`, `HTTPHeaders()`,
`JSONDecoder()`), and stdlib operations — none of which trip the
bare-name heuristic lists (`send`, `save`, `update`, etc.) that
fired on the TCA corpus. The zero yield is the expected correctness
signal for this shape, not a coverage gap — it says the Lambda
example corpus doesn't contain the non-idempotent patterns the
linter knows about. Run B validates that the annotations are being
read (they would have fired silently in both modes otherwise).

Reference: TCA's Run A yielded 6 / 6 catches on the same tier, all
`Non-Idempotent In Retry Context` on bare-name `send`. The Lambda
example surface is qualitatively different — no single "framework
verb" dominates the call graph.

## Run B — strict_replayable

Same handlers, annotations flipped to `strict_replayable`, fresh
clone at `349725b`, scan against linter tip `6c611c7` (post-slot-10).
**11 diagnostics, all of one class:
`[Unannotated In Strict Replayable Context]`**. None were carried
over from Run A (Run A had zero diagnostics).

### Per-Example breakdown

| Example | Line(s) | Callee | Cluster |
|---|---|---|---|
| `S3EventNotifier` | `main.swift:28` | `replacingOccurrences` | **stdlib-gap** |
| `BackgroundTasks` | `main.swift:44` | `Greeting` (struct init) | **type-ctor-gap** |
| `BackgroundTasks` | `main.swift:48` | `sleep` (`Task.sleep`) | **stdlib-gap** |
| `BackgroundTasks` | `main.swift:48` | `seconds` (`.seconds(10)` Duration) | **type-ctor-gap** |
| `S3_Soto` | `main.swift:31` | `listBuckets` (SotoS3) | **correct-catch** (third-party SDK) |
| `S3_Soto` | `main.swift:32` | `compactMap` | **stdlib-gap** |
| `S3_Soto` | `main.swift:33` | `joined` | **stdlib-gap** |
| `MultiSourceAPI` | — | (silent) | — |
| `APIGatewayV2` | `main.swift:23` | `HTTPHeaders` (NIO type init) | **type-ctor-gap** |
| `Testing` | `main.swift:32` | `HTTPHeaders` | **type-ctor-gap** |
| `Testing` | `main.swift:38` | `String` (`String(data:encoding:)`) | **stdlib-gap** + **type-ctor-gap** |
| `Testing` | `main.swift:42` | `uppercasedFirst` (adopter helper) | **correct-catch** (adopter should annotate) |

### Cluster counts

| Cluster | Count | Verdict |
|---|---|---|
| **stdlib-gap** | 6 (`replacingOccurrences`, `Task.sleep`, `compactMap`, `joined`, `String(data:)`, 1 overlap on `String`) | adoption gap — Foundation/stdlib surface not yet whitelisted |
| **type-ctor-gap** | 5 (`Greeting`, `.seconds`, `HTTPHeaders`×2, `String`) | adoption gap — already known as next_steps.md slot 2 (`.init(...)` form). Evidence here is two shapes: bare-name (`Greeting`, `HTTPHeaders`, `String`) which the existing ctor whitelist should match but doesn't for non-whitelisted types, and member-access (`.seconds(10)`) which is the slot-2 form proper |
| **correct-catch** | 2 (`listBuckets`, `uppercasedFirst`) | genuine — `listBuckets` is a third-party SDK call that should carry `@lint.assume listBuckets is idempotent`; `uppercasedFirst` is an adopter helper that should declare `@lint.effect idempotent` |
| **lambda-runtime-writer-gap** | 0 (was 5 pre-slot-10) | **closed** — whitelist shipped in linter commit `6c611c7`, same shape as Hummingbird `request`/`parameters` in PR `040f186` |

### Comparison to pre-slot-10 baseline

The original Run B against linter tip `5698683` produced 16
diagnostics; this rerun against `6c611c7` produces 11. The 5-drop
matches the `lambda-runtime-writer-gap` cluster exactly:

| Pre-slot-10 line | Callee | Now |
|---|---|---|
| `BackgroundTasks/main.swift:44` | `write` (on `outputWriter`) | silenced |
| `MultiSourceAPI/main.swift:48` | `write` (on `responseWriter`) | silenced |
| `MultiSourceAPI/main.swift:49` | `finish` (on `responseWriter`) | silenced |
| `MultiSourceAPI/main.swift:65` | `write` | silenced |
| `MultiSourceAPI/main.swift:66` | `finish` | silenced |

No other diagnostic changed, confirming the slice is scoped
exactly to the intended pair surface. `MultiSourceAPI` went from
4 / 0 silent to 0 / 1 silent — the full branch-join body is now
inferable end-to-end because both conditional terminators
(`write` + `finish`) land on framework primitives. That's the
branch-join stress test from the scope doc resolving cleanly.

## Pre-committed question answers (preview)

Full treatment with headers per question is in
[`trial-retrospective.md`](trial-retrospective.md). Short version:

1. **Does PR #18's whitelist infrastructure generalise?** Yes,
   with caveats — the `idempotentReceiverMethodsByFramework`
   shape from commit `040f186` (Hummingbird) is the right fit
   for the `write` / `finish` diagnostics. PR #18's bare-name
   override path is TCA-specific and doesn't apply. So it's the
   **earlier** whitelist infrastructure that generalizes, not
   PR #18's specifically.
2. **Slot 4 second data point (escape-wrapper shape).** No —
   Lambda's example corpus contains zero `detach` / `runInBackground`
   / `fireAndForget`-shape calls. Slot 4's original shape is
   not surfaced by this adopter. The `write` / `finish` pattern
   is a different shape with its own whitelist solution.
3. **Protocol-method handler coverage.** Confirmed working —
   three of the six diagnostic-producing handlers are protocol
   methods (`BackgroundTasks`, `MultiSourceAPI`, `Testing`),
   annotation fires correctly when placed on the `func handle`
   declaration.
4. **Fork-authoritative workflow rough edges.** One real one:
   `road_test_plan.md` doesn't call out that multi-Example
   corpora need per-Example scans. The top-level scan returned
   "No issues found" because the linter doesn't recurse into
   nested `Examples/*/Package.swift` SPM projects. Found by
   cross-referencing the TCA transcript mid-round.

## Comparison to TCA (prior round)

| | TCA | Lambda (post-slot-10) |
|---|---|---|
| Handlers annotated | 6 | 6 |
| Run A yield | 6 / 6 | 0 / 6 |
| Run B yield | 6 / 6 carried + ~27 strict-only | 0 carried + 11 strict-only |
| Dominant Run A rule | `Non-Idempotent In Retry Context` on `send` | (no fires) |
| Dominant Run B rule | `Unannotated In Strict Replayable Context` + inherited Run A | `Unannotated In Strict Replayable Context` only |
| Framework whitelist slice landed | PR #18: `send` as closure parameter | `6c611c7`: `write` / `finish` on Lambda writers, same shape as Hummingbird `040f186` |

**Reading.** Two adopters, two different shapes, one shared
whitelist infrastructure. Lambda's whitelist entry lives alongside
Hummingbird's in `idempotentReceiverMethodsByFramework` and did
not require new infrastructure — the cross-framework-generalisation
question from `trial-scope.md` answers **yes** for the receiver/method
pair shape. PR #18's bare-name override path remains TCA-specific.
