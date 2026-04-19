# Round 6 Trial Findings

Cross-project validation of receiver-type gating + camelCase-gated prefix matching on `swift-aws-lambda-runtime` at `2.8.0`. Linter baseline `68ad3bc` — 2049 tests / 267 suites green (unchanged from post-fix verification).

## Diagnostic count per run

| Run | State | Diagnostics | Notes |
|---|---|---|---|
| A | bare 2.8.0, zero annotations | 0 | Inference-without-anchor clean post-prefix-matching |
| B | +9 `@lint.context replayable` across every named-function handler | 0 | **Zero catches, zero noise** — see analysis below |
| C | B + `_TrialInferenceAnti/Sources/main.swift` (9 cases) | 4 | 4/4 positives fire, 5/5 negatives silent |
| D | — | skipped | Rationale in section below |

## Run A — inference-without-anchor cleanliness confirmed

Identical result to R5 Run E (0 diagnostics on bare `swift-aws-lambda-runtime`). The prefix-matching extension widened the match surface but didn't widen the *fire-without-anchor* surface — the retry-context and caller-constraint rules still require a `@lint.context` or `@lint.effect` anchor to emit. Expected result, correctly produced. Nothing to triage.

## Run B — 9 annotations, 0 catches, 0 noise

Every `func handle(...)` and `func handler(...)` across the 9 named-function Lambda examples annotated `/// @lint.context replayable`. Linter produced zero diagnostics.

This splits two ways depending on which question you ask:

**As a precision measurement:** *perfect.* 9 annotations on a corpus the precision fixes were not tuned against produced **zero noise**. The R5 claim ("4/4 correct catches, 0 noise on pointfreeco Run D") generalises in the direction that actually matters for adoption — the rule doesn't fire on un-annotated code that happens to be in a replayable body.

**As a catch-yield measurement:** *nothing to measure.* Lambda example bodies contain the following call shapes:

| Call shape | Status under current inference |
|---|---|
| `context.logger.debug(...)` / `.error(...)` | Two-signal observational — correctly silent in replayable |
| `outputWriter.write(...)` / `responseWriter.write(...)` | `write` deliberately out-of-whitelist (per proposal) — silent |
| `Task.sleep(for: .seconds(N))` | `sleep` not on whitelist — silent |
| `s3.listBuckets()` | `listBuckets` doesn't match any exact or prefix name |
| `tenants.update(id:data:)` | `update` deliberately out-of-whitelist — silent |
| `currentData.addingRequest(...)` | `add` not on whitelist; `adding` doesn't match `append` prefix |
| JSON codec calls, async stream writes, `Task.sleep` | none match |

The handlers in these examples are **pure compute-and-return** — read an event, do business logic against a data store, write a response. The external side-effect that a webhook handler would hit (send email, publish event, insert row) lives in whatever service the business code eventually calls, but these demo examples don't go that deep.

### Per-annotation yield across corpora

| Corpus | Annotations | Catches | Yield |
|---|---|---|---|
| pointfreeco Run D (post-fix) | 5 | 4 | 0.80 catches/annotation |
| swift-aws-lambda-runtime Run B | 9 | 0 | 0.00 catches/annotation |

The yield delta is **not a precision problem.** It's a corpus-structural fact: the current inference whitelist is calibrated to business-app shapes (webhooks, email, event publishing, database writes). Lambda examples demonstrate the runtime mechanism, not the business-logic layer the inference targets. A Lambda application that called `mailgun.sendEmail(...)` or `sns.publishEvent(...)` or `db.insertRow(...)` from a handler would produce pointfreeco-style yields; these demo examples don't, by design.

The right reading: *round 5's precision claim holds; the yield claim is more narrowly scoped than round 5 implied.*

## Run B scope gap — closure-based handlers

Roughly **half the Lambda example surface is out of reach** of the current `/// @lint.context` grammar. Closure-based handlers, passed to `LambdaRuntime(body:)` as trailing closures or stored-property closures, have no function declaration to annotate:

| Example | Handler shape |
|---|---|
| `HelloWorld` | top-level closure passed to `LambdaRuntime { event, context in ... }` |
| `HelloJSON` | same |
| `APIGatewayV1` | closure |
| `APIGatewayV2` | closure |
| `APIGatewayV2+LambdaAuthorizer` | two closures (`simpleAuthorizerHandler`, `policyAuthorizerHandler`) |
| `JSONLogging` | closure |
| `HummingbirdLambda` | closure |
| `CDK` | closure |
| `ServiceLifecycle+Postgres` | closure property routed through `LambdaRuntime(body:)` |
| `_MyFirstFunction` | closure |

All 10 are objectively replayable by Lambda invocation semantics, same as the 9 that were annotated. None carry a function declaration the current grammar can attach to.

This is a **new finding round 5 did not surface.** Pointfreeco's webhook handlers are all `func` declarations, so R5 never met this shape. A real adopter shipping a Lambda app in the modern Swift style would find a non-trivial fraction of their retry-exposed surface unreachable by the lint tool. Fixing this is a grammar extension — teach the annotation parser to read `/// @lint.context replayable` from the `leadingTrivia` of a closure passed to a known Lambda-entry function (or, cleaner, from a `@Sendable` closure property's leading trivia). Out of scope for this round.

## Run C — mechanism fires identically at corpus scale

New file `Examples/_TrialInferenceAnti/Sources/main.swift`. Four positive, five negative.

| # | Shape | Expected | Observed |
|---|---|---|---|
| 1 | `@context replayable` → `sendNotification(to:)` | prefix `send`+`N`, fires | ✅ inference-credited "from the callee-name prefix `send` (in `sendNotification`)" |
| 2 | `@context replayable` → `createResource(spec:)` | prefix `create`+`R`, fires | ✅ "from the callee-name prefix `create`" |
| 3 | `@context replayable` → bare `publishEvent(e)` | prefix `publish`+`E`, fires | ✅ "from the callee-name prefix `publish`" |
| 4 | `@context replayable` → `q.enqueueBatch(items)`, `q: UserQueue` | prefix `enqueue`+`B` on user type, fires | ✅ "from the callee-name prefix `enqueue`" |
| 5 | `@context replayable` → `str.appending("x")`, `str: String` | stdlib exclusion, silent | ✅ silent |
| 6 | `@context replayable` → `arr.filter { ... }`, `arr: [Int]` | not on any list, silent | ✅ silent |
| 7 | `@context replayable` → `publisher(for:)` | prefix `publish`+`e` lowercase, camelCase gate blocks | ✅ silent |
| 8 | `@context replayable` → `postpone("task")` | prefix `post`+`p` lowercase, camelCase gate blocks | ✅ silent |
| 9 | `@context replayable` + `Task { publish(e) }` | escaping-closure boundary | ✅ silent |

**4/4 positive, 5/5 negative.** Identical behaviour to the R5 unit-test suite and the pointfreeco Run C. The mechanism does what it says across corpus boundaries.

## Run D — skipped with explicit reasoning

The plan specified Run D as optional: "if Run B's results suggest the mechanism is working cleanly, widen context annotations beyond `handle(...)` to any internal helper."

With Run B at 0/0, widening context to handler helpers can't produce new signal — the helpers the handlers call are the same category of operations already surveyed above (stdlib mutations, `Task.sleep`, logger calls, `context.*` accesses, S3 API calls with names like `listBuckets` / `getBucketLocation` that don't match any prefix). Annotating them would record another 0-catch data point but not test a different hypothesis.

The honest Run D alternative — pivot to a different corpus with more webhook-style handler code (Vapor, an internal microservice) — is better cast as round 7 with its own trial-scope doc. Conflating it with round 6's scope would muddy the per-run cost estimate.

**Run D status:** intentionally skipped. The Phase 0 scope-commitment section's "explicitly skipping Run D is within scope" clause applies.

## Cross-round comparison

| Round | Corpus | Annotations | Diagnostics | Noise | Yield | Outcome |
|---|---|---|---|---|---|---|
| 5 Run D (R5 linter) | pointfreeco | 5 | 6 | 1 (Array.append) | 1.20 | *too-broad* failure discovered |
| 5 Run D post-fix (stdlib only) | pointfreeco | 5 | 5 | 0 | 1.00 | noise removed; scaffold catches 5 |
| 5 Run D post-fix (stdlib + prefix) | pointfreeco | 5 | 9 | 0 | 1.80 | 4 new real-code catches, all correct |
| **6 Run B** | **swift-aws-lambda-runtime** | **9** | **0** | **0** | **0.00** | **no noise on un-tuned corpus; no catches either** |

The across-corpora picture: **noise rate has held at 0 on both tuned and un-tuned corpora.** Yield tracks corpus type, not linter precision.

## Net output

- **R5 precision claim holds.** Zero false positives across 9 fresh annotations on an un-tuned corpus.
- **R5 yield claim is more narrowly scoped than it read.** The "4 catches from 5 annotations" figure is pointfreeco-shape-specific (webhook handlers doing external side effects). On handlers that don't reach external side-effect surface, the yield is 0 — *correctly*, not noisily.
- **Mechanism transplants cleanly.** Run C's 4/5 scaffold fires exactly on the corpus layout of a different codebase.
- **New finding:** closure-based handler annotation is a grammar gap affecting ~50% of the Lambda example surface. A non-trivial amount of real-world Lambda code is currently un-annotatable. Worth formalising as an open issue.

## Data committed

All run transcripts in `docs/phase2-round-6/trial-transcripts/`:

- `run-A.txt` — bare `2.8.0`
- `run-B.txt` — +9 annotations
- `run-C.txt` — +anti-injection

No rule changes on the linter baseline. `trial-inference-round-6` branch on swift-aws-lambda-runtime holds 10 edits (9 annotations + 1 new scaffold file); not pushed. Test baseline re-confirmed 2049/267 green post-round.
