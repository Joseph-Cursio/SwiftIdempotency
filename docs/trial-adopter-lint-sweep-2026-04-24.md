# Trial-Adopter Linter Sweep — 2026-04-24

**Motivation.** Four production adopters had been package-integration
trialled but never linter-scanned: VernissageServer, plc-handle-tracker,
HomeAutomation, Uitsmijter. Running the linter (SwiftProjectLint at
slot-20 tip `69979a4`) across them would either:

- Surface structural rule fires (slot 20 tuple-equality
  baseline extension from 13 to 17 adopters), and/or
- Surface 2-adopter evidence on any of the nine parked
  1-adopter slice candidates, promoting them to ship-eligibility.

**Scope.** Bare-scan only — no annotation surgery, no two-run
replayable/strict-replayable sweep. The narrow scope catches
structural findings + any 1-adopter candidate whose receiver-method
shape is detectable via simple grep.

## Structural-scan results

Command: `swift run CLI <adopter-clone> --categories idempotency
--threshold info`.

| Adopter | Result | Corpus position |
|---|---|---|
| plc-handle-tracker | No issues found | 14/17 adopters zero-structural |
| HomeAutomation | No issues found | 15/17 |
| Uitsmijter | No issues found | 16/17 |
| VernissageServer | No issues found | 17/17 |

**Slot-20 `tuple-equality-with-unstable-components` baseline extended
from 13 to 17 adopters.** All four new adopters continue the
zero-fire-corpus-wide pattern. The rule remains structurally silent
across a broader cross-section of production Swift-server code.
Pattern-match on the rule's "zero findings on a corpus is the
expected outcome" prediction holds.

## 2-adopter promotion candidates (the real find)

Grep-based cross-reference of the nine parked 1-adopter candidates
against the four fresh adopters surfaced **two strong promotions**:

### Promotion #1 — Vapor `app.register(collection:)` → **3-adopter**

Prior 1-adopter evidence: hellovapor (slot-17-adjacent, filed as
slot-16-follow-on candidate).

New evidence:

- **Uitsmijter** — `Sources/Uitsmijter-AuthServer/routes.swift:27-42`
  registers 10 `RouteCollection` controllers via
  `app.register(collection: ...)`:
  `HealthController`, `VersionsController`, `MetricsController`,
  `LoginController`, `LogoutController`, `InterceptorController`,
  `WellKnownController`, `AuthorizeController`, `TokenController`,
  `RevokeController`.
- **plc-handle-tracker** — `Sources/registerRoutes.swift:19-20`
  registers 2 controllers via `app.register(collection: ...)`:
  `DidController`, `HandleController`.

Total call sites: hellovapor (prior) + Uitsmijter (10) + plc-handle-tracker (2) = **3 adopters, 12+ call sites**.

Shape: method `register(collection:)` on receiver `Application`
(Vapor). Fixture is a `RouteCollection` conformer. Consistent with
the slot-17 `FrameworkWhitelist.vapor` table — single receiver
method, single framework gate.

**Promotion recommendation:** Add `(app, register) → Vapor` to
`idempotentReceiverMethodsByFramework` in SwiftProjectLint.
Structurally identical shape to slots 16-18. Estimated +11 tests,
~30-LOC slice. Ship-eligible.

### Promotion #2 — Swift Concurrency `Task.sleep` → **4-adopter**

Prior 1-adopter evidence: hummingbird-examples (slot-16-adjacent,
filed as SwiftConcurrency family candidate).

New evidence:

- **Uitsmijter** — 5 sites: `Logger/LogWriter.swift:428`,
  `JWT/KeyStorage+RedisImpl.swift:321`,
  `ScriptingProvider/JavaScriptProvider.swift:228`,
  `Entities/ResourceLoader/EntityCRDLoader.swift:162`,
  `:267`.
  Both `Task.sleep(nanoseconds:)` and backoff-retry-loop patterns.
- **HomeAutomation** — 5 sites: `SharedDistributedCluster/CustomActorSystem.swift:133,219`,
  `Server/entrypoint.swift:44` (commented), `Shared/Timer.swift:23`,
  `HAImplementations/Automations/WindowOpen.swift:57`.
  Uses modern `Task.sleep(for: .seconds(N))` spelling.
- **Vernissage** — 5+ sites:
  `Services/ClearAttachmentsService.swift:129,147,251,269`,
  `Services/PurgeStatusesService.swift:85`.
  All in backoff-retry-loop shape within async service methods.
- **plc-handle-tracker** — 0 sites.

Total: hummingbird-examples (prior) + Uitsmijter (5) + HomeAutomation (5) + Vernissage (5+) = **4 adopters, 15+ call sites**.

Shape: method `sleep` on receiver `Task` (Swift Concurrency
stdlib — not framework-gated). Called forms include
`Task.sleep(nanoseconds:)`, `Task.sleep(for:.seconds(N))`, and
`try? await Task.sleep(...)` exception-swallow variants.

**Promotion recommendation:** Add `(Task, sleep) → SwiftConcurrency`
to a new `frameworkImportAliases`-equivalent gate (stdlib, not a
framework module). Alternative: structural recognition in the
heuristic effect inferrer without a framework gate at all, since
`Task` is the Swift stdlib type (not a user-declared type).

### Adjacent finding — `.seconds(N)` Duration constructor

The `Task.sleep(for:)` spellings all pass `.seconds(N)` —
implicit-member `Duration.seconds(_:)`. This is a variant of the
"implicit member from static method" shape that the TCA round
documented. Not new evidence on its own, but worth noting that
**the Swift Concurrency slice would need to handle both the
deprecated `sleep(nanoseconds:)` and the modern `sleep(for:)
Duration` shapes**. Separate sub-concerns.

## 1-adopter candidates that stayed 1-adopter

- **Vapor `Route.description`** (hellovapor) — no matches in the
  four new adopters.
- **Hummingbird `addMiddleware`** (hummingbird-examples) — only
  Uitsmijter uses middleware, and via `app.middleware.use(...)`
  (Vapor idiom), not Hummingbird's `addMiddleware`.
- **Hummingbird `queryParameters.require`** (prospero /
  myfavquotes-api) — no Hummingbird adopters in this sweep.
- **Swift Distributed Tracing `withSpan`** (hummingbird-examples)
  — no matches. HomeAutomation uses distributed-actors but not
  swift-distributed-tracing.
- **Bcrypt-crypto-gap** (myfavquotes-api) — no matches. Uitsmijter
  uses JWT + swift-crypto + CryptoSwift, not Bcrypt specifically.
- **`AppMetrics.push` Prometheus-Pushgateway** (SPI-Server) — no
  match on the exact `AppMetrics.push` shape. But see below for a
  related finding.
- **Axiom `emit`** (luka-vapor) — no matches.

## New 1-adopter candidate surfaced

**`Prometheus.main.<metricName>?.inc(N, ...)`** — Uitsmijter uses
pervasive Prometheus-metric counter-increments via a chained
optional on a global facade singleton (`Prometheus.main`). 15+
call sites across `AuthCodeStorage`, `Controllers/Activate`,
`Controllers/Authorize`, `Controllers/Device`, `Controllers/Interceptor`,
`Controllers/Revoke`, `Events/AuthEventActor`,
`Http/RequestClientMiddleware`.

Shape: `Counter?.inc(Int, [labels])` on a chained Optional
receiver. Structurally DIFFERENT from SPI-Server's
`AppMetrics.push` (method name, receiver). Both are observability
counter-increments on metrics facades — the family is common, the
specific shape is not.

**Not ship-eligible** — 1-adopter for this specific shape. Logged
for future rounds. A cross-framework "metrics family" whitelist
(combining `(AppMetrics, push)`, `(Prometheus.main.<metric>, inc)`,
others) would need a structural abstraction; deferred.

## What this round decided

**Two linter slices graduated from parked-1-adopter to ship-eligible
on the strength of this sweep**, without requiring annotation
round-trips:

- **Slot 21 candidate** (tentative name): `app.register(collection:)`
  Vapor whitelist — 3-adopter.
- **Slot 22 candidate** (tentative name): `Task.sleep`
  Swift Concurrency whitelist — 4-adopter.

Plus one deferred 1-adopter observation (Uitsmijter Prometheus
counter shape).

Plus one structural-baseline extension (slot 20 zero-fire-corpus
→ 17 adopters).

## Process note

**Bare-scan + grep was sufficient to surface these promotions.**
Annotation round-trips weren't required — the candidate shapes
were receiver-method patterns detectable structurally. This
suggests a **low-cost sweep cadence** for future rounds:

1. Scan new trial adopters with slot-tip CLI (bare, no
   annotations).
2. Grep adopter source for each parked 1-adopter candidate's
   receiver-method pattern.
3. Any 2+ adopter match → promote to slice candidate.

Estimated ~30 minutes per new adopter post-trial to extract this
signal. Significantly cheaper than a full road-test
(annotation + two-scan transcript capture) when the only goal is
candidate promotion.

## Recommended next action

**User-gated:** The two promoted slices are SwiftProjectLint repo
work, not SwiftIdempotency. Shipping them requires the linter-side
PR cycle per `workflow_direct_to_main.md` memory. Tagging here
for the next session:

- PR-sized: `(app, register) → Vapor` whitelist entry.
- PR-sized: `(Task, sleep) → SwiftConcurrency` whitelist entry
  (may need framework-name invention since stdlib doesn't have
  a framework gate).

## Context

- **SwiftProjectLint tip:** `69979a4` (slot 20 + all prior closed).
- **Adopters scanned:** plc-handle-tracker-idempotency-trial,
  HomeAutomation-idempotency-trial, Uitsmijter-idempotency-trial,
  VernissageServer-idempotency-trial — all at their
  `package-integration-trial` branch tips.
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Total sweep wall-clock:** ~15 minutes (four parallel scans,
  largest two driven by compile cost of debug CLI against adopter
  build artifacts).
