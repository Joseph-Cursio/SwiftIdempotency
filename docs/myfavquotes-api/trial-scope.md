# myfavquotes-api — Trial Scope

## Research question

> **Does a second Hummingbird production-shaped adopter (with full
> Fluent + Postgres + Bearer auth surface) plateau the named-slice
> count, push slot 16 (Hummingbird Router DSL whitelist) to
> 2-adopter ship-eligibility, and confirm Completion Criterion #2
> at 3/3?**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `2fbb171` (post-PR-#21 merge
  tip; `swift test` green at 2286/276).
- **Target:** `kicsipixel/myfavquotes-api` @ `4da58c9` (main,
  2025-01-17, README-update tip) → forked to
  [`Joseph-Cursio/myfavquotes-api-idempotency-trial`](https://github.com/Joseph-Cursio/myfavquotes-api-idempotency-trial)
  @ `trial-myfavquotes`.
  - **Run A tip:** `8ae0c78` (6 handler annotations at `replayable`).
  - **Run B tip:** `579c1a4` (same handlers flipped to `strict_replayable`).
- **Scan corpus:** Multi-package corpus — five sibling SPM
  subpackages (`BasicAPI`, `BasicAuth`, `BearerAuth`,
  `BearerAuthPersist`, `BearerAuthSecureToken`) under repo root.
  77 Swift files total. **This round scans only `BearerAuthPersist`
  (17 files)** — the only subpackage with the full Fluent +
  Postgres + Bearer auth + Persist surface.
- **Toolchain:** swift-tools-version 6.0 (BearerAuthPersist),
  macOS 14 / iOS 17 / tvOS 17 minimum.
- **Stack:** Hummingbird 2.6.0 + HummingbirdFluent 2.0 +
  fluent-postgres-driver 2.10 + HummingbirdAuth 2.0.2 +
  HummingbirdBcrypt + HummingbirdBasicAuth.

## Annotation plan

Six `@Sendable func` handlers across two controllers — covering
the full CRUD + auth-flow shape matrix. Each is a named declaration
so doc-comment annotations attach directly (no enclosing-function
workaround needed, in contrast to prospero).

| Handler | File | Shape | Tier |
|---|---|---|---|
| `QuotesController.index` | `Sources/App/Controllers/QuotesController.swift:34` | read (list) | replayable / strict_replayable |
| `QuotesController.create` | `Sources/App/Controllers/QuotesController.swift:51` | insert (with unique quote_text) | replayable / strict_replayable |
| `QuotesController.update` | `Sources/App/Controllers/QuotesController.swift:62` | update (overwrite-idempotent) | replayable / strict_replayable |
| `QuotesController.delete` | `Sources/App/Controllers/QuotesController.swift:88` | delete (idempotent) | replayable / strict_replayable |
| `UsersController.create` | `Sources/App/Controllers/UsersController.swift:36` | insert (with unique email) | replayable / strict_replayable |
| `UsersController.login` | `Sources/App/Controllers/UsersController.swift:46` | token-generate + persist (interesting case) | replayable / strict_replayable |

`UsersController.login` is the most interesting handler — `Token.generate`
returns a fresh random token on every call, so the *response* differs
across retries even though the side effect (persist a token entry with
TTL) is observationally similar. This is the closest thing in the
corpus to a `@ExternallyIdempotent(by:)` candidate without an
existing `IdempotencyKey` parameter.

## RouterGroup shape (slot-16 evidence path)

Both controllers register handlers via:

```swift
func addRoutes(to group: RouterGroup<QuotesAuthRequestContext>) {
    group
        .get(use: self.index)
        .get(":id", use: self.show)
        ...
}
```

This is the **same enclosing-function pattern as prospero's
`addXRoutes(to router:)`**, but with one structural difference:
myfavquotes-api uses `RouterGroup` (chained from `router.group("api/v1/quotes")`)
where prospero uses `RouterGroup` directly. The slot 16 candidate
fires on `router.get/post` etc. — this round tests whether
`RouterGroup.get/post` (post-`.group(...)` chain) fires the same
way.

Critically, **handlers are passed as method references (`use: self.index`)
not inline trailing closures.** This is a different shape from
prospero's inline closures and may interact differently with the
Router DSL whitelist.

## Scope commitment

- **Measurement-only**: no logic edits. Only annotation comments
  + README fork banner (already landed).
- **Source-edit ceiling**: ≤ 4 files (README + QuotesController +
  UsersController + maybe one Migration if SQL ground-truth requires).
- **Audit cap**: 30 diagnostics. If Run B exceeds, decompose by
  cluster.

## Pre-committed questions

1. **Does `RouterGroup.get/post` (the `.group(...)`-derived form)
   fire the same slot 16 shape as prospero's `Router.get/post`?**
   If yes → 2-adopter evidence, slot 16 ship-eligible. If no →
   slot 16 stays at 1-adopter or surfaces a new sub-shape.
2. **Does method-reference handler binding (`use: self.create`) walk
   into the function body, or does the linter miss handler-side
   diagnostics because the annotation is on the method, not the
   call site?** Prospero's inline trailing closures resolved
   cleanly via the enclosing-function workaround; this is a
   different binding shape.
3. **Is there a real-bug catch?** Both `Quote` and `User` migrations
   declare `unique(on:)` constraints on `quote_text` and `email`
   respectively — so create-on-retry hits a DB-level reject. SQL
   ground-truth pass should flip both `create` shapes to
   defensible-by-design. The interesting case is
   `UsersController.login`: `Token.generate` returns a new random
   token per call — observably non-idempotent response. Does the
   linter catch the `Token.generate` + `persist.create` path?
4. **Plateau round?** Prospero was 2/3. Does myfavquotes-api advance
   to **3/3** (closing Completion Criterion #2)? Plateau requires
   zero new named adoption-gap slices — slot 16 evidence
   accumulation does not count as a new slice.

## Predicted outcome

Phase-2-shaped target with a tutorial-API surface (auth + CRUD on
quotes). Smaller and tighter than prospero (17 files vs 29).
Prediction: **1 real-bug catch** (login token generation), 6-12
Run A fires, 30-50 Run B fires (mostly slot 16 RouterGroup shape).
**No new framework slice expected** — the worst case is slot 16
extending to cover `RouterGroup.{get,post,put,delete}` as a
sub-shape of the existing 1-adopter evidence, which is a same-slice
extension, not a new slice.

If `RouterGroup` fires structurally identically to prospero's
`Router`, this is the cleanest possible plateau round. If
method-reference bindings (`use: self.create`) suppress
handler-body diagnostics that prospero's inline closures surfaced,
that's a real adoption gap and would block the plateau.
