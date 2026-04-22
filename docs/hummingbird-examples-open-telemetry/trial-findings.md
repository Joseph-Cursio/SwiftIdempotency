# hummingbird-examples / open-telemetry — Trial Findings

Slot 16 corroboration round on the second inline-trailing-closure
Hummingbird adopter. Linter at `SwiftProjectLint` main `698081e`
(post-PR-#22 slot 14 HttpPipeline whitelist merge tip). Target
`hummingbird-examples` at `0d0f9bd`, on local `trial-open-telemetry`
branch with one `@lint.context` annotation on `buildRouter()` in
`open-telemetry/Sources/App/Application+build.swift`.

## Run A — replayable context

**1 diagnostic** (plus 1 pre-existing info — `Could Be Private` on
`AppRequestContext` — unrelated to idempotency).
Transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| Enclosing fn | Line | Callee | Rule | Source of classification |
|---|---|---|---|---|
| `buildRouter` | 94 | `post` | nonIdempotentInRetryContext | inferred — bare-name non-idempotent HTTP verb on `router.post("/wait")` route-registration DSL |

**Slot 16 fires (Run A): 1** — the `router.post("/wait")` DSL call.

The two `router.get` calls (at lines 85 and 89) are silent in
replayable mode. This matches prospero's Run A shape, where `get`
was below the bare-name non-idempotent threshold (GET is
idempotent by HTTP convention) and only surfaced under strict
mode. Run B below confirms the symmetry.

No handler-body catches. Unlike prospero — whose `addPatternRoutes`
handler closures contained adopter-level calls (`pattern.save`,
`recomputeHues`, `fetchHourlyForecast`) that produced catches
independent of slot 16 — open-telemetry's three inline closures
are in-memory reads (literal `"Hello!"`, param echo) and one
traced sleep. Correct silence.

## Run B — strict_replayable context

**12 error diagnostics + 1 info.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (1 diagnostic): `post` at :94.

**Strict-only** (11 diagnostics) — decomposed by cluster:

| Cluster | Count | Callees | Evidence category |
|---|---|---|---|
| **Slot 16 — Hummingbird Router DSL (continuation)** | **2** | `get` (line 85), `get` (line 89) | Same rule path as prospero's 6× `router.get` Run B cluster. 2-adopter corroboration. |
| Hummingbird Router primitive | 1 | `addMiddleware` (line 76) | New single-adopter candidate — `router.addMiddleware { ... }` registration-time call. Below cross-adopter threshold. |
| Hummingbird primitive (different receiver) | 1 | `require` (line 95) | `request.uri.queryParameters.require(...)` — the immediate receiver is `queryParameters`, not `parameters`, so the existing `(parameters, require) → Hummingbird` whitelist correctly doesn't match. Record as a candidate for a sibling `(queryParameters, require) → Hummingbird` pair. |
| Type-constructor `.init(...)` gap | 4 | `Router` (line 74), `MetricsMiddleware` (line 78), `TracingMiddleware` (line 80), `LogRequestsMiddleware(.debug)` (line 82) | Same long-running `.init(...)` member-access gap documented in todos-fluent findings (1/6 there). 4/12 here — this corpus raises the cross-adopter fire count noticeably. |
| Swift Distributed Tracing | 1 | `withSpan` (line 97) | New candidate — `withSpan("sleep") { ... }` scoping primitive, structurally analogous to `Task { ... }` / `.task { ... }`. Candidate for Observational whitelist. Below cross-adopter threshold. |
| Swift Concurrency (stdlib) | 2 | `sleep` (line 99), `seconds` (line 99) | `try await Task.sleep(for: .seconds(time))`. `sleep` is the async suspend primitive, `seconds` is the `Duration.seconds(_:)` factory. Both below cross-adopter threshold; `Task.sleep` specifically is a plausible candidate for Observational. |

Exceeds zero-new-slice bar by count (4 candidate clusters at
1-adopter evidence each), but **none reaches cross-adopter
threshold.** All four are recorded here for next-round observation,
not ship-eligible this round.

### Slot 16 — 2-adopter corroboration summary

| Rule path | Prospero | open-telemetry | Corroborated? |
|---|---|---|---|
| `nonIdempotentInRetryContext` on `router.post` (bare-name verb) | 3 fires | 1 fire | ✅ same rule path, same shape |
| `unannotatedInStrictReplayableContext` on `router.get` (unwhitelisted DSL) | 6 fires | 2 fires | ✅ same rule path, same shape |

**Both paths fire identically across both adopters.** Slot 16
promotes from 1-adopter to **2-adopter ship-eligibility.** The
Hummingbird Router DSL whitelist is the next actionable slice
for a linter PR.

## Real-bug catches

**Zero** — as predicted. open-telemetry has no persistence layer
(no Fluent, no DynamoDB, no file writes). The one retry-sensitive
operation (`Task.sleep` inside a `withSpan`) is observably
idempotent at the semantic level: re-running a retried request
produces an identical sleep + span emission. Correct silence.

SQL ground-truth pass not applicable (no migrations, no database).

## Silence accounting — what didn't fire (and shouldn't have)

In Run A, the two `router.get` calls were silent. Correct:
- `get` is a bare-name idempotent HTTP verb; no rule should fire
  on it in replayable mode.
- The handler closures (pure-read/traced-sleep) contain no
  non-idempotent bare-name verbs, no ORM verbs, no declared
  `@NonIdempotent` attributes. Correct per existing rule shape.

## Next-slice candidates on this corpus (recap)

All four below the 2-adopter ship-eligibility bar. **Named for
tracking, not for immediate linter work.**

1. **Hummingbird Router registration primitives** (`addMiddleware`,
   possibly others like `group`, `add`) — 1-adopter evidence
   (open-telemetry). Single-adopter; defer.
2. **`queryParameters.require` sibling pair** — the existing
   `(parameters, require) → Hummingbird` whitelist matches the
   `context.parameters.require(...)` shape correctly (via the
   chained-receiver `callParts` immediate-parent rule), but the
   sibling `request.uri.queryParameters.require(...)` shape used
   for query-string access has `queryParameters` as its immediate
   receiver and isn't whitelisted. 1-adopter evidence. Defer
   pending corroboration.
3. **Swift Distributed Tracing `withSpan`** — Observational
   primitive candidate. 1-adopter evidence. Strong a-priori case
   (distributed tracing is universally observational by design)
   but linter work needs cross-adopter evidence.
4. **Swift Concurrency `Task.sleep` / `Duration.seconds`** —
   stdlib primitives. 1-adopter evidence. `Task.sleep` is a
   plausible Observational; `Duration.seconds` is a pure factory
   (inferred pure-idempotent once a call-body inferrer is applied
   to Duration's lib source, but it's Foundation-owned so
   adopter-annotation is off the table).

None of the above contest slot 16's promotion — they are new
candidate slices surfaced incidentally by this scan.

## Completion-criterion status

Per [`road_test_plan.md`](../road_test_plan.md) Criterion #2
(adoption-gap stability requires three consecutive rounds with
zero new named adoption-gap slices), the prior round on
`myfavquotes-api` closed Criterion #2 at 3/3. This round raises
a new question for the framework: **does slot 16's 2-adopter
promotion count as a same-slice extension (no change to Criterion
#2 count) or as a named new slice (resets)?** The slot was
already named in the prospero round; this round supplies
corroboration evidence on the same slice, not a new slice. Read
as same-slice extension → Criterion #2 remains at 3/3 closed.

The 4 candidate clusters surfaced in Run B above are explicitly
recorded as **below-threshold observations**, not named slices.
Naming a new slice requires at least cross-adopter evidence (per
prior-round convention); none of the four has it yet.
