# Prospero — Trial Scope

## Research question

> **Does yield behaviour generalise to a fourth battle-tested
> production adopter from a different framework family (first
> Hummingbird prod app, first single-contributor / phase-2
> target), and does the plateau signal advance?**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (post-PR-#21 merge
  tip; `swift test` green at 2286/276).
- **Target:** `samalone/prospero` @
  `a1308b3b9b462a3b5b3bc9a0d7a464f71e767d50` (main, 2026-04-21,
  v0.4.2) → forked to
  [`Joseph-Cursio/prospero-idempotency-trial`](https://github.com/Joseph-Cursio/prospero-idempotency-trial)
  @ `trial-prospero`.
  - **Run A tip:** `353753f` (3 route-registration fns `@lint.context replayable`).
  - **Run B tip:** `56d676f` (same 3 fns `@lint.context strict_replayable`).
- **Scan corpus:** 29 Swift files under `Sources/Prospero/` —
  smallest production-app corpus yet. Single top-level
  `Package.swift`.
- **Toolchain:** swift-tools-version 6.2, macOS 15 minimum.
- **Stack:** Hummingbird 2.x + HummingbirdFluent (Fluent +
  PostgreSQL + SQLite) + HummingbirdAuth + PlotHTMX.

## Annotation plan

Three route-registration functions — the only named handler-ish
declarations available. Prospero's primary handler surface is
**anonymous trailing closures** inside `router.get/post { req, ctx in ... }`
registration calls (see "Trailing-closure shape" note below).
Annotating the enclosing `addXRoutes(to router:, ...)` function
attaches the context to the function body, and the linter walks
the trailing closures within it — confirmed in the pre-flight
probe.

| Handler | File | Tier |
|---|---|---|
| `addPatternRoutes` | `Routes/PatternRoutes.swift:11` | replayable (Run A) / strict_replayable (Run B) |
| `addForecastRoutes` | `Routes/ForecastRoutes.swift:8` | replayable / strict_replayable |
| `addCalendarRoutes` | `Routes/CalendarRoutes.swift:27` | replayable / strict_replayable |

This covers **9 concrete HTTP handler closures** inside those
three registration functions: 4 reads + 3 writes in
PatternRoutes, 1 forecast GET, 1 calendar GET.

## Trailing-closure shape (scope-relevant)

Prospero's handlers look like:

```swift
func addPatternRoutes(to router: RouterGroup<AuthedContext>, ...) {
    router.get("/patterns") { request, context -> HTML in ... }
    router.post("/patterns") { request, context -> Response in
        try await pattern.save(on: db)
        ...
    }
}
```

Handler logic lives inside anonymous trailing closures. Doc-
comment annotations (`/// @lint.context replayable`) can only
attach to named declarations, so the closures themselves cannot be
annotated directly. This matches the shape predicted in
[`ideas/inline-trailing-closure-annotation-gap.md`](../ideas/inline-trailing-closure-annotation-gap.md)
— and **disconfirms that idea's "unlikely on non-Lambda corpus"
prediction** (trigger #2 met).

However, the pre-flight probe showed that annotating the
enclosing `addXRoutes` function **does walk into the trailing
closures** — 9 diagnostics from a single annotation. So the gap
is less adoption-blocking than the idea doc implied: the
enclosing-function annotation is a viable workaround. This round
uses that workaround.

## Scope commitment

- **Measurement-only**: no logic edits. Only annotation comments
  + README fork banner.
- **Source-edit ceiling**: ≤ 5 files. Actual: 4 (README + 3
  Routes/).
- **Audit cap**: 30 diagnostics. Run A (10) fits for full audit;
  Run B (62) exceeds cap and is decomposed by cluster.

## Pre-committed questions

1. **Does the Hummingbird `040f186` framework whitelist cover a
   real Hummingbird prod app's call surface?** — 040f186 added
   `(nil, "handle")` / `(nil, "run")` for HBApplication etc.
   Prospero uses `router.get/post` trailing closures, which is a
   different surface. Any unexpected interactions?
2. **Does the `addXRoutes` enclosing-function annotation
   workaround produce useful diagnostics, or does the linter
   silently drop closure bodies?** — Pre-flight probe said it
   works; full scan confirms.
3. **Is there a real-bug shape?** — Prospero uses Fluent with
   `.save(on:)` on models created via form input. If
   `ActivityPattern` lacks a unique constraint, save-on-retry is
   a duplicate-insert bug. SQL ground-truth pass will confirm.
4. **Plateau round?** — SPI-Server was 1/3. Does prospero advance
   to 2/3?

## Predicted outcome

Phase-2 target + smaller codebase → higher chance of finding a
real bug (per the memory: "latent idempotency issues are more
likely to survive collective review" in obscure
single-contributor projects). Prediction: 1-2 real-bug catches,
~10-15 Run A fires, ~50-80 Run B fires. No new framework slice
from Hummingbird router DSL unless `router.get/post` false
positives accumulate to cluster volume.
