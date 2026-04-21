# isowords — Trial Scope

## Research question

> Does the Penny round's yield (5/5 handlers fire; 10 correct-catches
> across 4 real-bug shapes; 50% of Run A diagnostics are real-bug-
> shaped) reproduce on a second production adopter, or is it Penny-
> specific?

## Pinned context

- **Linter:** `SwiftProjectLint` @ `6200514` (the Penny-round close-
  out commit; `swift test` green at 2272/276).
- **Target:** `pointfreeco/isowords` @ `c727d3a7c49cf0c98f2fa4f24c562f81e30165f7`
  (default branch `main`, last pushed 2024-08-16).
- **Fork:** `Joseph-Cursio/isowords-idempotency-trial` (public,
  issues/wiki/projects disabled, default branch `trial-isowords`).
- **Trial branch tip:** `a71c99390493c3b8a56d3ed95bf589670b87fa23`
  (Run A state — 5 handlers `/// @lint.context replayable` + fork
  banner).

## Annotation plan

Five `public func *Middleware(_ conn: Conn<...>)` handlers, selected
for shape diversity against isowords' real production side effects
(DB writes, SNS dispatch, Apple StoreKit verification):

| Handler | Target file | Why |
|---|---|---|
| `submitGameMiddleware` | `Sources/LeaderboardMiddleware/SubmitGameMiddleware.swift` | Score submission. Row insert into `leaderboardScores` + context-dependent follow-ups (complete daily challenge, fetch rank). Highest bug-shape likelihood — retried submit could double-record. |
| `registerPushTokenMiddleware` | `Sources/PushMiddleware/PushTokenMiddleware.swift` | SNS `createPlatformEndpoint` + DB `insertPushToken`. Classic two-stage external-then-internal side-effect pair. |
| `startDailyChallengeMiddleware` | `Sources/DailyChallengeMiddleware/DailyChallengeMiddleware.swift` | DB `startDailyChallenge` creates a play row. Retried start → duplicate play rows. |
| `verifyReceiptMiddleware` | `Sources/VerifyReceiptMiddleware/VerifyReceiptMiddleware.swift` | Apple iTunes verify (external HTTP) + DB `updateAppleReceipt`. Receipt hash is a natural idempotency key. |
| `submitSharedGameMiddleware` | `Sources/ShareGameMiddleware/ShareGameMiddleware.swift` | `insertSharedGame` creates a new row + share code. Retried submit → duplicate shared-game entries. |

All five annotated with the doc-comment form
(`/// @lint.context replayable`). Attribute form not exercised this
round — isowords does not currently depend on the `SwiftIdempotency`
package, and adding it for measurement is out of scope.

## Scope commitment

- Measurement only. No logic edits to isowords source.
- Source-edit ceiling: 5 one-line annotations + 1 README banner.
- Audit cap: 30 diagnostics. If Run B exceeds the cap, decompose
  the excess by cluster.
- Two scans: `replayable` (Run A) then `strict_replayable` (Run B).

## Pre-committed questions

1. **Does yield generalise?** Penny produced 5/5 handlers fire, 10
   correct-catches, 4 real-bug shapes. Does isowords reproduce that
   density, or does it collapse to a Penny-specific outcome?
2. **Does the HttpPipeline Middleware shape interact differently
   from Lambda `handle(_:)`?** The prior pointfreeco round (www,
   same `HttpPipeline` stack) was already measured, but with a
   different business domain (subscriptions / email). isowords' game-
   submission shape is new terrain for this stack.
3. **Do the four Penny bug-shape categories — double-increment,
   error-path notification duplication, external-webhook redelivery,
   single-use-token replay — recur on an independent codebase?**
4. **Are there new adoption-gap slices, or does the residual match
   the known cross-adopter noise (stdlib/type-ctor gap + adopter-
   type construction + framework-method gap)?**
