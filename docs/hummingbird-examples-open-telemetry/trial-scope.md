# hummingbird-examples / open-telemetry — Trial Scope

Follow-up round to promote **slot 16 (Hummingbird Router DSL
whitelist)** from 1-adopter (prospero) toward 2-adopter
ship-eligibility. The first attempt on a second Hummingbird
adopter — `myfavquotes-api` — did not surface slot 16 fires
because its controllers bind handlers via method references
(`group.get(":id", use: self.show)`), not inline trailing
closures. That round plateaued (`Criterion #2` closed at 3/3)
without accumulating slot 16 evidence.

## Research question

> **On a second inline-trailing-closure Hummingbird adopter, does
> `@lint.context replayable` on the route-registration function
> (`buildRouter`) fire the same bare-name `router.get` /
> `router.post` DSL pattern that prospero's `addXRoutes` surfaced?
> If yes, slot 16 advances from 1-adopter to 2-adopter
> ship-eligibility.**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `698081e` (post-PR-#22 merge
  tip — slot 14 HttpPipeline whitelist shipped).
- **Target:** `hummingbird-project/hummingbird-examples` @
  `0d0f9bd` (main, 2026-02-09, `server-sent-events-v6` merge).
- **Trial fork:** `Joseph-Cursio/hummingbird-examples-idempotency-trial`
  (already exists from the prior `todos-fluent` attempt).
- **Trial branch:** `trial-open-telemetry` on
  [`Joseph-Cursio/hummingbird-examples-idempotency-trial`](https://github.com/Joseph-Cursio/hummingbird-examples-idempotency-trial),
  forked from upstream `main` tip `0d0f9bd`.
  - **Run A tip:** `9a7edb8` (`buildRouter` @ `@lint.context replayable`).
  - **Run B tip:** `674935a` (same function flipped to `@lint.context strict_replayable`).
- **Scan corpus:** `open-telemetry/` sub-package — **2 Swift
  files**, ~100 LOC:
  - `open-telemetry/Sources/App/Application+build.swift`
    (contains `buildRouter()` — the annotation target)
  - `open-telemetry/Sources/App/App.swift`
    (CLI entry point; out of annotation scope)
- **Toolchain:** swift-tools-version 6.1.
- **Stack:** Hummingbird + OTel + ServiceLifecycle + Tracing +
  Metrics + NIOCore.

## Annotation plan

**One function, one annotation.** `buildRouter()` at
`Application+build.swift:72` is the enclosing function for three
inline trailing closures:

| Closure site | Line | DSL call | Handler shape |
|---|---|---|---|
| 1 | 84 | `router.get("/")` | pure read — `"Hello!"` literal |
| 2 | 88 | `router.get("/test/{param}")` | pure read — echoes param |
| 3 | 93 | `router.post("/wait")` | traced sleep via `withSpan` |

Same structural shape as prospero's `addPatternRoutes(router:)`:
route registration + inline handler closures inside a single
enclosing function. Smaller surface (3 closures vs. prospero's 9).

- **Run A — replayable:** `buildRouter` carries `/// @lint.context
  replayable`. Expected: **3 slot 16 fires** (`router.get` × 2,
  `router.post` × 1), zero Fluent catches (no ORM), zero real
  bugs (in-memory handlers with no persistence).
- **Run B — strict_replayable:** same function, tier flipped.
  Expected: Run A's 3 catches + `UnannotatedInStrictReplayableContext`
  on handler-body callees (`parameters.require`, `queryParameters.require`,
  `withSpan`, `Task.sleep`, `HTTPResponse.Status`, closure arg to
  `withSpan`). Predicted 8–15 strict-only fires.

## Scope commitment

- **Measurement-only.** No linter changes this round.
- **Source-edit ceiling**: ≤ 2 files — one doc-comment line on
  `buildRouter` (+1 for tier flip between runs), optionally a
  README fork banner if push is authorized in the retrospective.
- **Audit cap**: 30 diagnostics. Expected total well below cap.
- **Single sub-package.** All other hummingbird-examples
  subdirs (hello, sessions, server-sent-events, etc.) remain
  out of scope for this round; open-telemetry was picked for
  highest inline-closure density (3 fires per 30 LOC).

## Pre-committed questions

1. **Slot 16 fire count.** Do all three `router.get`/`router.post`
   DSL calls produce `nonIdempotentInRetryContext` on the
   bare-name rule path? If any are already silenced (e.g., by
   prior whitelist work), that would change the slot-16 evidence
   count and must be recorded.
2. **Handler-body catches in Run A.** Prospero's three inline
   closures surfaced handler-body catches (`pattern.save`,
   `recomputeHues`, `fetchHourlyForecast`) because the closures
   contained adopter-level calls. Open-telemetry's handlers are
   in-memory pure reads and one traced sleep — none are expected
   to fire in Run A. If any fire, that's a new shape worth
   recording.
3. **Strict-mode cluster shape.** Run B's strict-only fires
   should cluster cleanly: Hummingbird primitives
   (`parameters.require`, `queryParameters.require`,
   `HTTPResponse.Status`), Tracing primitives (`withSpan`),
   Swift Concurrency (`Task.sleep`). Any cluster that overlaps
   with an existing whitelist slice is "already-silenced"
   (record); anything new is a candidate slice (record for
   next-round consideration).
4. **Does this count as a distinct adopter for slot 16?**
   Ambiguous. hummingbird-examples is a monorepo; `todos-fluent`
   was the prior trial target and produced zero slot 16 fires
   (different binding style + `buildRouter` not annotated).
   Open-telemetry exercises a different binding style AND a
   different annotation target. Defensible as "distinct adopter
   for this slice." Retrospective records the verdict; conservative
   reading keeps slot 16 at 1-adopter and flags need for a
   non-hummingbird-examples Vapor-DSL analog.

## Predicted outcome

- **Run A:** 3 slot 16 fires. No handler-body catches. No real
  bugs (no persistence in this example).
- **Run B:** 3 carried + 8–15 strict-only. No new slice
  candidates expected — all strict-only fires should map onto
  existing whitelisted primitive clusters or the known
  `.init(...)` member-access gap.

If Run A produces exactly 3 slot 16 fires with no surprises,
this is the cleanest possible 2-adopter corroboration for slot
16 — evidence threshold met. If Run B surfaces a new cluster
(e.g., OTel `withSpan` is not yet whitelisted as observational),
that's bonus evidence toward a separate slot; it does not block
slot 16's promotion since slot 16 is evaluated on Run A fires.
