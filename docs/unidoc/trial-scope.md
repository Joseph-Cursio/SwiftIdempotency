# Unidoc — Trial Scope

Eighteenth adopter road-test. **Designed specifically to test the
slot 23 (switch-dispatch deep-chain inference) hypothesis** — the
1-adopter slice candidate surfaced on the tinyfaces round (round
17, 2026-04-26) where `StripeWebhookController.index` went silent
under `@lint.context replayable` despite dispatching to
non-idempotent sub-handlers via `switch (event.type, event.data?.object)`.

Unidoc's `WebhookOperation.load(with:)` exhibits the exact same
structural pattern: a method-bound webhook entry that dispatches
via `switch self.event` to private sub-handlers, each of which
makes MongoDB writes. If `load(with:)` is silent under replayable,
that's **2-adopter evidence** on the slot — sufficient to ship the
linter slice with proper cross-adopter motivation.

This round also gives the **first MongoDB-backed adopter** datapoint
— a separate domain-novelty axis that validates whether the
linter's Postgres / DynamoDB / MySQL-tuned heuristics generalise
to Mongo.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "Does the deep-chain inference walk through `switch self.event`
> case bodies on a method-bound webhook entry annotated
> `@lint.context replayable`? Specifically: does
> `WebhookOperation.load(with:)` fire under replayable when its
> body is a 3-arm switch dispatching to private `handle(...)`
> sub-handlers that make MongoDB writes? If silent, this is the
> 2-adopter slot-23 trigger — promote the linter slice from
> 1-adopter speculative to 2-adopter slice-ready."

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at
  `eb35175` (post-PRs #30/#31/#32/#33/#34 merge tip; 2407 / 294
  tests green on a clean `.build/`).
- **Upstream target:** `rarestype/unidoc` @ `500663c` on `master`
  (2026-04-23 push). Scalable multi-package documentation engine
  for Swift; the public unidoc instance hosts SwiftPackageIndex-
  style docs. 76 stars, MPL-2.0 licence.
- **Architecture:** Vertex-style server organised around an
  `Operation` protocol family (`InteractiveOperation`,
  `AdministrativeOperation`, etc.). Each operation has a `load(...)`
  method called by the server's request dispatcher. The webhook
  entry receives GitHub events via HTTP/2 and dispatches via a
  `switch self.event` to private `handle(installation:...)` and
  `handle(create:...)` methods, each of which calls into
  `Unidoc.DB` (MongoDB-backed via `MongoDB` / `UnidocDB`
  packages).
- **Fork:** `Joseph-Cursio/unidoc-idempotency-trial`, hardened
  per road-test recipe.
- **Trial branch:** `trial-unidoc`, forked from upstream
  `500663c`. Fork-authoritative.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required.
- **Repo layout:** single SPM package; scan target is
  `Sources/UnidocServer` subdirectory only (where the operations
  live; the broader package has 25+ targets and scanning the
  whole tree adds noise without shape evidence).

## Annotation plan

Six handlers — primary focus on the webhook switch-dispatch shape,
with shape-diversity supplements.

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Sources/UnidocServer/Operations/Interactions/Unidoc.WebhookOperation.swift:71` | `WebhookOperation.load(with:)` | **PRIMARY SLOT 23 TRIGGER.** Method-bound webhook entry. Body is 3-arm `switch self.event` dispatching to private `handle(installation:...)` / `handle(create:...)` sub-handlers, each making MongoDB writes. If silent → 2-adopter slot 23 evidence. |
| 2 | `Sources/UnidocServer/Operations/Interactions/Unidoc.WebhookOperation.swift:93` | `WebhookOperation.handle(installation:at:in:)` | **Sub-handler comparison.** Calls `db.users.update(user:)` (Mongo write) and `db.users.modify(id:)` (Mongo update). 2-arm switch on `event.action`. Annotating directly tests whether the inner switch (on action enum) propagates — different switch shape from #1. |
| 3 | `Sources/UnidocServer/Operations/Interactions/Unidoc.WebhookOperation.swift:118` | `WebhookOperation.handle(create:at:in:)` | **Richest sub-handler.** Calls `db.packages.updateWebhook`, `db.index`, `db.crawlingTickets.delete`, `db.repoFeed.insert` — multiple Mongo writes across the same body. Find-or-index pattern (parallel to tinyfaces' `checkoutCompleted`). |
| 4 | `Sources/UnidocServer/Operations/Interactions/Unidoc.AuthOperation.swift:24` | `AuthOperation.load(with:)` | **OAUTH FLOW.** Calls `client.exchange(code:)` (external GitHub API call — non-idempotent: GitHub rejects code reuse) followed by `operation.perform(on: server)` (downstream `UserIndexOperation` does Mongo writes). Cross-shape with the AWS Cognito (matool) and Brevo SendInBlue (tinyfaces) email-on-retry shape. |
| 5 | `Sources/UnidocServer/Operations/Interactions/Unidoc.PackageAliasOperation.swift:19` | `PackageAliasOperation.load(from:db:as:)` | **MONGO UPSERT.** Calls `db.packageAliases.upsert(alias:of:)`. Data-layer audit case — Mongo `upsert` is replace-by-key, semantically idempotent. Tests the SQL-ground-truth pass on Mongo. |
| 6 | `Sources/UnidocServer/Operations/Interactions/Unidoc.LoginOperation.swift:19` | `LoginOperation.load(with:)` | **PURE RENDER.** Returns `.ok(page.resource(...))` with no side effects. Correctness signal — should stay silent under replayable. |

Deliberately excluded:

- `LinkerOperation` / `BuilderPollOperation` / `BuilderLabelOperation` —
  builder-pipeline operations with deeper async semantics that
  would inflate audit cap without adding webhook-shape evidence.
- Read-only operations (`LoadDashboardOperation`,
  `LoadSitemapIndexOperation`) — same correctness-signal as #6;
  redundant.
- The full `Operations/` directory contains 30+ files; the 6
  selected above give strong shape diversity.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` (Run A) and
  `/// @lint.context strict_replayable` (Run B) on each handler
  `func`. No logic edits, no imports, no new types.
- **Audit cap.** 30 diagnostics per mode (template default).
- **Data-layer audit required.** Per `road_test_plan.md` DB-heavy
  adopter rule. Mongo equivalent of the Postgres/Fluent
  `.unique(on:)` shortcut: check whether the Mongo write methods
  the handlers call use `_id`-keyed upserts vs unconditional
  inserts. Specifically:
  - `db.users.update(user:)` — by-id upsert? unconditional insert?
  - `db.users.modify(id:)` — by-id update (idempotent on fixed row).
  - `db.packages.updateWebhook(configurationURL:repo:)` — update?
  - `db.index(package:repo:repoWebhook:mode:)` — find-or-create?
  - `db.crawlingTickets.delete(id:)` — by-id delete (idempotent —
    redelete is no-op).
  - `db.repoFeed.insert(activity:)` — unconditional insert?
  - `db.packageAliases.upsert(alias:of:)` — by-key upsert
    (semantically idempotent).

## Pre-committed questions

1. **Switch-dispatch deep-chain (slot 23 trigger).** Does
   `WebhookOperation.load(with:)` fire under `@lint.context replayable`?
   The body is `switch self.event { case .installation: ... case .create: ... case .ignore: ... }`. **Hypothesis: NO — silent.**
   The tinyfaces precedent strongly suggests the deep-chain
   inferrer doesn't walk `SwitchExprSyntax` case bodies as direct
   callees of the enclosing function. If hypothesis confirms,
   this is the 2-adopter trigger; ship the linter slice.

2. **Sub-handler direct annotation.** Do
   `handle(installation:at:in:)` and `handle(create:at:in:)` fire
   directly when annotated? Both contain non-idempotent Mongo
   writes (`db.users.update`, `db.repoFeed.insert`, etc.).
   **Hypothesis: yes — both fire.** Confirms the inner methods
   ARE inferred non-idempotent; the gap is purely upward
   propagation through the switch in `load(with:)`.

3. **Mongo upsert defensibility.** Does
   `PackageAliasOperation.load(from:db:as:)` fire on
   `db.packageAliases.upsert(...)`? **Hypothesis: yes (fires on
   non-idempotent classification — `upsert` isn't on any
   whitelist).** Audit verdict: **defensible-by-design** — Mongo
   upsert is replace-by-key, observably idempotent. Tests whether
   the linter's Postgres/Fluent-tuned heuristics produce the
   same false-positive shape on Mongo (which they should, since
   the rule is structural).

4. **Pure-render correctness signal.**
   `LoginOperation.load(with:)` returns `.ok(...)` with no DB
   calls and no external API calls. **Hypothesis: silent.**
   Confirms the rule isn't generating false positives on read
   paths.

## Predicted outcome

Run A yield prediction: 4 catches / 6 handlers = 0.67 (with 2
silent: `load(with:)` slot-23-silent + `LoginOperation.load`
correctness-signal-silent).

Slot 23 evidence prediction: **silent miss confirmed** → 2-adopter
trigger reached → ship `slice-switch-dispatch-deep-chain`.
