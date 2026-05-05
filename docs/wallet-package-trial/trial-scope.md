# Wallet — trial scope

## Research question

> Does SwiftIdempotency surface useful diagnostics on the Apple
> Wallet Web Service Protocol — a domain where retry-safety is
> mandated by spec rather than inferred from "this is an HTTP route
> on a server that retries"?

Every prior round (`hellovapor`, `luka-vapor`, `prospero`,
`myfavquotes-api`, etc.) annotated handlers as `@lint.context
replayable` based on the framework's at-least-once delivery
contract. Wallet is the first target where Apple's protocol
*explicitly mandates* the contract — see the hand-rolled `if r !=
nil { return .ok }` at line 67-68 of
`PassesServiceCustom+RouteCollection.swift`, which implements
Apple's "if registration already exists, return 200 OK" rule
verbatim. The framework is the spec.

## Pinned context

- SwiftIdempotency: `ecae768` (`docs: email-on-retry slice
  verification — already shipped + slot-23 paid out twice`)
  - `swift test` clean: 86 tests / 11 suites + 4 known issues.
- SwiftProjectLint: `5397858` (`CI: clone sibling LintStudioUI
  before swift build`)
  - `swift test` clean: 2410 tests / 295 suites.
- Target upstream: `vapor-community/wallet` v0.8.0,
  SHA `df4b665` ("Update for Swift 6.1 and Swift Wallet 1.0").
- Trial fork: `Joseph-Cursio/wallet-idempotency-trial`, branch
  `trial-wallet` (default), tip `b875f47`.

## Annotation plan

Six handlers, all in
`Sources/VaporWalletPasses/PassesServiceCustom+RouteCollection.swift`,
all bound via `use:` (method-reference shape — annotation goes on
the `func` doc comment, not on a registration helper). Coverage
reflects the full Apple Wallet Web Service Protocol surface for
Passes:

| Handler | Method | Path | Predicted Run A verdict |
|---|---|---|---|
| `registerPass` | POST | `/v1/devices/.../registrations/.../{passSerial}` | hand-rolled "already exists → 200" guard; defensible |
| `updatablePasses` | GET | `/v1/devices/.../registrations/...` | silent (pure read) |
| `updatedPass` | GET | `/v1/passes/.../{passSerial}` | silent (cached read with `If-Modified-Since`) |
| `unregisterPass` | DELETE | `/v1/devices/.../registrations/.../{passSerial}` | defensible (delete-idempotent) |
| `logMessage` | POST | `/v1/log` | silent (observational, only `req.logger.notice`) |
| `personalizedPass` | POST | `/v1/passes/.../{passSerial}/personalize` | **real-bug candidate** — `personalization.create` with no apparent dedup |

The Orders side
(`OrdersServiceCustom+RouteCollection.swift`) is structurally
symmetric (`registerDevice`, `latestVersionOfOrder`,
`unregisterDevice`, `logMessage`, `ordersForDevice`); annotating
both sides is duplicative and is not done — Orders is mentioned
in the retrospective as a counterfactual.

## Scope commitment

- **Measurement only.** No logic edits. The only source change is
  six `/// @lint.context replayable` doc-comment lines plus a
  README banner declaring the fork non-contribution.
- **Audit cap: 30 diagnostics.** Run B is expected to exceed this
  given the dense Vapor/Foundation/Fluent surface; carried
  diagnostics will be audited per-line, strict-only diagnostics
  decomposed by callee-name cluster.
- **SQL ground-truth pass mandatory** — Wallet is Fluent-backed
  via `fpseverino/fluent-wallet`. Migrations on `PassesDevice`,
  `PassesRegistration`, and `PersonalizationInfo` are read against
  every `create`-style diagnostic before assigning a verdict, per
  road_test_plan §"For Fluent adopters specifically".

## Pre-committed retrospective questions

1. **Cross-function guard recognition.** Does the linter recognize
   the `if r != nil { return .ok }` guard inside the
   `createRegistration` helper as a dedup-guarded write, or fire
   on the surrounding `registration.create(on: db)` because
   inference doesn't propagate the protective effect across the
   function boundary?
2. **Real-bug discovery on personalize.** Does `personalizedPass`
   fire a real-bug catch under Run A, and does the
   `PersonalizationInfo` migration carry a `.unique(on:)` that
   would either flip the verdict to defensible or — more
   pessimistically — turn a duplicate insert into a 500-on-retry
   that violates Apple's spec at a different layer?
3. **Observational classification.** Is `req.logger.notice`
   correctly classified as observational, allowing `logMessage`
   to remain silent?
4. **Multi-target Sources/.** Does the multi-target Sources/
   layout (`VaporWallet`/`VaporWalletPasses`/`VaporWalletOrders`
   under one `Package.swift`) scan correctly from a single root
   invocation, or does it need the per-Example shell loop from
   road_test_plan §"Multi-package corpora"?
