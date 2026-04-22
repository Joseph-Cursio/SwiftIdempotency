# luka-vapor — Trial Scope

First-adopter road-test for **slot 17 (Vapor routing DSL
whitelist)**, the parallel slice to slot 16 on Vapor's `app.get /
post / put / patch / delete` inline-closure shape. Scout round
(2026-04-22 / docs/next_steps.md) sampled five Vapor adopters and
found four use method-reference binding via `RouteCollection.boot`
— the ecosystem convention — and one (`kylebshr/luka-vapor`) uses
inline trailing closures, the shape slot 17 would whitelist.

## Research question

> **On an inline-trailing-closure Vapor adopter, does
> `@lint.context replayable` on the route-registration function
> (`routes(_:)`) fire a bare-name DSL pattern on `app.post` (and
> related verbs) analogous to prospero's `router.get` / `router.post`
> fires under slot 16? If yes, slot 17 has first-adopter evidence
> and a candidate whitelist scope; if the shape diverges (e.g.,
> `app.get` classifies differently than `router.get`), record the
> asymmetry and adjust the slot-17 scope accordingly.**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `29e9069` (post-PR-#23 merge
  tip — slot 16 Hummingbird Router DSL whitelist shipped).
- **Target:** `kylebshr/luka-vapor` @ `8a6fd42` (main, 2026-04-18,
  "Merge pull request #19 from kylebshr/kb/fly-app-name").
- **Trial fork:**
  [`Joseph-Cursio/luka-vapor-idempotency-trial`](https://github.com/Joseph-Cursio/luka-vapor-idempotency-trial)
  (hardened; issues/wiki/projects disabled, sandbox description,
  default-branch switched).
- **Trial branch:** `trial-luka-vapor` on the fork.
  - **Run A tip:** `d2c9e21` (`routes(_:)` @ `@lint.context replayable`).
  - **Run B tip:** `f2e5d09` (same function flipped to `@lint.context strict_replayable`).
- **Scan corpus:** whole project — single SPM package, 15 Swift
  files, ~1200 LOC. Single target: `LukaVapor` (executable).
- **Toolchain:** swift-tools-version 6.2.
- **Stack:** Vapor 4.115 + Redis 4.14 + Queues + APNSwift (branch
  main, revision `e73454a`) + Dexcom (branch main, revision
  `370a0b6`) + Axiom observability.
- **Package.resolved already pins branch-deps** — no
  additional source edits needed to lock revisions.

## Annotation plan

**One function, one annotation.** `routes(_ app:)` at
`Sources/LukaVapor/routes.swift:4` is the enclosing function for
three inline trailing closures:

| Closure site | Line | DSL call | Handler shape |
|---|---|---|---|
| 1 | 5 | `app.get { }` | pure read — App Store link literal |
| 2 | 9 | `app.post("end-live-activity")` | Redis hget/hset/zrem/delete + APNS end-push via `LiveActivityScheduler.sendEndEvent` + axiom.emit observability |
| 3 | 53 | `app.post("start-live-activity")` | Redis hget/hset/zadd + session CAS |

Structural analogue to prospero's `addPatternRoutes(router:)` and
open-telemetry's `buildRouter()` — route registration + inline
handler closures inside a single enclosing function. 3 closures vs.
prospero's 9 vs. open-telemetry's 3.

- **Run A — replayable:** `routes(_:)` carries `/// @lint.context
  replayable`. Expected: 2–3 slot-17-candidate fires at the
  `app.get / post / post` registration sites, plus any handler-body
  catches from Redis writes / APNS pushes / axiom emits.
- **Run B — strict_replayable:** same function, tier flipped.
  Expected: Run A's catches carried, plus a cluster of
  `UnannotatedInStrictReplayableContext` fires on Redis primitives,
  Vapor `Abort`, JSON codec constructors, NIO `EventLoopFuture.get()`.

## Scope commitment

- **Measurement-only.** No linter changes this round.
- **Source-edit ceiling**: ≤ 2 files — one doc-comment line on
  `routes(_:)` (+1 for tier flip between runs), plus README fork
  banner.
- **Audit cap**: 30 diagnostics. Run B may exceed; if so, decompose
  by cluster per road-test-plan policy.
- **Single sub-package.** Not multi-package — one annotation in
  `Sources/LukaVapor/routes.swift`, scanned at project root.

## Pre-committed questions

1. **Slot-17 fire shape.** Do `app.post` registration calls fire
   under replayable context? If yes, what receiver is resolved
   (`Application` / unresolved) and what heuristic path produces
   the diagnostic (bare-name `post` lexicon match vs. receiver-
   qualified)? Answer determines the shape of the slot-17
   whitelist entry.
2. **`app.get` symmetry.** Does `app.get` fire under the same
   shape as `app.post`, or does the existing prefix lexicon
   (`get` is idempotent-by-convention) already silence it? Answer
   determines whether slot 17's scope is `(app, get|post|put|patch|delete)`
   like slot 16, or a narrower `(app, post|put|patch|delete)` pair.
3. **Handler-body real-bug catches.** Do the APNS push
   (`sendEndEvent`) and Redis CAS pattern (hget→mutate→hset)
   produce `IdempotencyKey` / `@ExternallyIdempotent(by:)` shape
   evidence? Answer contributes to the cross-adopter real-bug
   tally (currently 8-for-8 across five adopters).
4. **NIO `EventLoopFuture.get()` cluster.** Does Run B fire on
   `.get()` chained on Redis/Vapor futures (the "await the
   future" pattern)? If yes, is that a new 1-adopter candidate
   for a future `(EventLoopFuture, get)` observational whitelist
   entry? Likely cross-adopter across every pre-async-await
   Vapor codebase.

## Predicted outcome

- **Run A:** 2–3 slot-17 fires (2× `app.post`, possibly 1× `app.get`
  depending on prefix-lexicon resolution), plus 0–2 handler-body
  catches on Redis writes / APNS push.
- **Run B:** Run A's carried + 20–40 strict-only fires across
  stdlib, Redis, Vapor primitives, NIO futures. No new *slice-
  eligible* clusters expected (all candidates should map to either
  existing whitelists or known 1-adopter-below-threshold patterns).
