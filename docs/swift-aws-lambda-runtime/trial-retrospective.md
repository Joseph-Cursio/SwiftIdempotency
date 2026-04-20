# swift-aws-lambda-runtime — Trial Retrospective

Post-round notes for the fifth adopter road-test. Measurement
output lives in [`trial-findings.md`](trial-findings.md); scope in
[`trial-scope.md`](trial-scope.md).

## Did the scope hold?

Largely. Three deviations:

- **Target path drift**, caught pre-flight. The scope doc had to
  correct `apple/swift-aws-lambda-runtime` → `awslabs/swift-aws-lambda-runtime`
  because `CLAUDE.md`'s recommendation was out of date (apple →
  swift-server → awslabs). Folded into policy notes below.
- **Sample shape substitution**, called out in the scope doc. The
  `CLAUDE.md` recommendation was SQS/SNS handlers specifically;
  the v2.x example corpus has none. S3EventNotifier substituted
  for the "objectively replayable" positive-control role (S3
  event delivery is at-least-once by construction).
- **Per-Example-package scan**, not pre-committed in the scope
  doc. The first top-level scan returned "No issues found";
  cross-referencing the TCA transcript revealed that multi-Example
  corpora are scanned per-package. Re-ran correctly. See
  question 4 below.

Source-edit ceiling: held. Only the six doc-comment annotations +
the README banner + Run B's annotation-tier flip. No logic edits,
no new types. Audit cap: held (16 strict-mode diagnostics, 14
under the cap). Measurement-only: held.

## Pre-committed questions

### 1. Does PR #18's whitelist infrastructure generalise cleanly to a second framework?

**Qualified yes.** Two distinct whitelist shapes exist in
`SwiftProjectLint` and they serve different call patterns:

- **Framework bare-name override** (PR #18, `FrameworkWhitelist` +
  `HeuristicEffectInferrer` path). Overrides the bare-name
  non-idempotent list for specific framework-provided calls —
  the `send` case: `send` is globally on the "non-idempotent"
  bare-name list, but inside a TCA effect closure it's a framework
  primitive and should classify as idempotent.
- **Framework receiver-method whitelist** (`idempotentReceiverMethodsByFramework`,
  commit `040f186` for Hummingbird's `request` / `parameters`).
  Declares receiver-method calls on specific framework types as
  idempotent without requiring a bare-name override.

Lambda's strict-mode misses — `write` / `finish` on
`outputWriter` / `responseWriter` — are **receiver-method** shape,
not bare-name. They fit the earlier whitelist, not PR #18's.

**So: it's the PR `040f186` infrastructure that generalises
cleanly, not PR #18's.** The cross-framework question was real
and has a good answer. Adding a Lambda entry next to the
Hummingbird one is a config extension, not a shape change.

PR #18 is still load-bearing for TCA; it just doesn't help here.

### 2. Slot 4 cross-adopter data point — detach / runInBackground / fireAndForget

**No — Lambda's example corpus has zero escape-wrapper calls.**
The `BackgroundTasks` example, which the scope doc flagged as
the most likely candidate, does **not** use a `detach` / `Task { }`
/ wrapper pattern — it relies on structured concurrency, running
post-response work inline after `outputWriter.write(...)` within
the same `handle` call. The runtime enforces the background-work
convention at the invocation boundary, not via a wrapper.

This produces a clean negative answer for slot 4: the
`fireAndForget` shape is **pointfreeco-specific**, not a
cross-framework pattern. Slot 4 downgrades from "waiting on a
second data point" to "confirmed pointfreeco-specific — don't
generalise."

What Lambda surfaces instead — the `write` / `finish`
response-writer pattern — is a **different shape**, already
addressable via the `040f186` receiver-method whitelist (see
question 1). Not a slot 4 data point; a separate, smaller slice.

### 3. Protocol-method handler shape coverage

**Confirmed — protocol-method handlers fire correctly under
`@lint.context` placement on the `func` declaration.** Three of
the six strict-mode-diagnostic-producing handlers are protocol
methods:

- `BackgroundTasks.BackgroundProcessingHandler.handle` (conforms
  to `LambdaWithBackgroundProcessingHandler`)
- `MultiSourceAPI.MultiSourceHandler.handle` (conforms to
  `StreamingLambdaHandler`)
- `Testing.MyHandler.handler` (struct method, not protocol, but
  same placement shape)

All three surface diagnostics pointing back to the annotated
method. The annotation-placement heuristic is not closure-biased;
no gap to score.

Evidence against a hidden gap: if protocol-method placement
wasn't wired, these three files would have returned zero strict
diagnostics too (as the `.init` + stdlib shapes would land in a
body the visitor never enters). They returned 4 + 4 + 3 = 11 of
the 16 total.

### 4. Fork-authoritative workflow rough edges

The documented `road_test_plan.md` recipe held up on all the
fork-ops steps — fork creation, hardening, branch creation,
annotation-commit, push, default-branch switch, re-clone — and
the fork-authoritative scan source of truth was enforced
(the scan ran against the fresh clone, not the ambient edit
working tree).

**One gap found.** `road_test_plan.md` assumes single-package
corpora. Multi-Example corpora like `swift-aws-lambda-runtime`
(and `swift-composable-architecture`) need **per-Example-package
scans**; the linter doesn't recurse into nested
`Examples/*/Package.swift` subpackages from a top-level invocation.
First scan I ran returned "No issues found" because it scanned
only the root package.

Discovered by cross-referencing the TCA transcript, which is
structured as `=== /tmp/swift-composable-architecture/Examples/Todos ===`
etc. The pattern was there; the template just didn't call it out.

**Policy note for the template** (fold into `road_test_plan.md`'s
"Scan twice" section): when the target is a multi-Example SPM
corpus, iterate the scan over each annotated `Examples/<X>/`
subdirectory and concatenate the output. Top-level scans silently
underreport.

**One environmental gap** (not a template issue): the global
Claude Code PreToolUse `git commit` hook ran
`swift package clean && swift test && swiftlint` on every commit,
including commits in the adopter fork's working tree — which
caused it to fail on upstream + dependency lint that has nothing
to do with the annotation change. Resolved mid-round by scoping
the hook to `~/xcode_projects/*`. Logged as a config change, not
a road-test template change.

## Counterfactuals

Three things that would have changed the outcome:

1. **A less pristine Lambda example corpus.** The examples are
   demo code: logging + echo + base64 decode + one AWS SDK read.
   A real adopter application would have webhook-style side
   effects, database writes, third-party API calls — all of
   which would surface Run A catches. The 0 / 6 Run A yield is
   a function of the example surface, not of the linter's
   correctness on Lambda. The complementary measurement — annotate
   handlers in a real production Lambda app — is where bare-name
   non-idempotent catches would reappear.
2. **Running Lambda Examples at the top level.** If the linter
   had recursed into nested SPM packages, strict-mode diagnostics
   would have shown up on the first pass. Related to the
   road-test-plan gap in question 4; the linter's scan-scope
   behaviour on multi-package corpora is a separate design
   question worth scoping.
3. **Including `HummingbirdLambda/Sources/main.swift:23`.** The
   scope doc explicitly excluded it as redundant with the
   Hummingbird whitelist (commit `040f186`). Including it would
   have been a belt-and-braces confirmation that the whitelist
   remains load-bearing on this adopter too, but wouldn't have
   produced new evidence.

## Cost summary

| | Estimated | Actual |
|---|---|---|
| Sessions | 1-2 | 1 |
| Target discovery (fork URL, SHA pin) | 5 min | 15 min — upstream-path drift + corpus-shape substitution consumed the extra |
| Fork creation + hardening | 5 min | 5 min |
| Handler selection | 10 min | 15 min — needed to inspect every Example dir to pick six |
| Annotation + commit + push | 10 min | 30 min — PreToolUse hook blocked the first commit, mid-round config fix |
| Scan × 2 | 10 min | 25 min — top-level scan returned zero, had to re-scope to per-Example |
| Audit + findings writeup | 30 min | 30 min |
| Retrospective | 15 min | 15 min |

**Net**: ran to ~2h15m vs ~1h30m estimated. Two of the three
overruns were environmental (hook, scan scope); the third
(corpus substitution) was scoped in the scope doc, not a surprise.

## Policy notes

Three candidates for the template / upstream docs:

- **`road_test_plan.md` — Scan twice.** Add a "Multi-package
  corpora" sub-bullet: scan each annotated Example/<X> directory
  separately and concatenate output. TCA and Lambda both have
  this shape; probably most Swift-server adopters do too
  (vapor, hummingbird-examples, etc.). Worth documenting so
  the next round doesn't rediscover it.
- **`CLAUDE.md` — Validation Target section.** Update
  `apple/swift-aws-lambda-runtime` → `awslabs/swift-aws-lambda-runtime`,
  and add a note that the v2.x example corpus has no SQS/SNS
  examples; S3EventNotifier substitutes for the "objectively
  replayable" role. Related: reconsider whether the "first
  validation target" recommendation should still be Lambda
  given the thin example corpus — a production Lambda app
  would be a better target for FP-rate measurement; Lambda's
  official examples are better as a "does the infrastructure
  even apply?" smoke test.
- **`next_steps.md` slot 4.** Downgrade from "waiting on a
  second data point" to "confirmed pointfreeco-specific, don't
  generalise." Add a new slot for the Lambda-response-writer
  whitelist extension (small — mirrors PR `040f186`).

## Data committed

- `trial-scope.md` — research question + pinned context + scope
- `trial-findings.md` — Run A / Run B tables, cluster breakdown
- `trial-retrospective.md` — this document
- `trial-transcripts/replayable.txt` — Run A raw output (18 lines)
- `trial-transcripts/strict-replayable.txt` — Run B raw output
  (50 lines)

Fork: https://github.com/Joseph-Cursio/swift-aws-lambda-runtime-idempotency-trial
Trial branch: `trial-lambda` (default)
Tip commit: `349725b`
