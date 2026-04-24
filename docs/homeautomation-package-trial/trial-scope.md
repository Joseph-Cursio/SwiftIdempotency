# HomeAutomation — Package Integration Trial Scope

Fresh-external-signal Option B probe. Third consecutive clean-slate
external adopter (post-Vernissage, post-plc-handle-tracker). First
HomeKit / home-automation domain, first MySQL Fluent target, first
`swift-distributed-actors` adopter trial, first APNs-delivery
target.

**Selection-criteria note (2026-04-24).** With two consecutive
zero-friction fresh-signal probes behind us, the phase-2 "obscure
single-contributor" heuristic is explicitly retired. Adopter
selection now optimises for *domain / shape novelty* rather than
project obscurity. HomeAutomation happens to also be
single-contributor (311 commits, sole human author) but the
selection reason here is domain novelty — HomeKit automation and
APNs push delivery are both unprobed side-effect classes.

## Research question

> Does the v0.3.1 Option B surface model the at-least-once APNs push
> delivery shape on a production HomeKit-automation server? And does
> it extend cleanly across the delta from HTTP-handler / AsyncJob
> shapes to an *already-extracted* `Sendable` protocol the adopter
> has pre-engineered for test-mocking?

## Why HomeAutomation specifically

- **Novel domain.** HomeKit automation + energy monitoring (Tibber
  API integration) are unprobed side-effect classes. Prior eight
  adopters covered HTTP handlers, Lambda handlers, vapor/queues
  AsyncJobs, ActivityPub inbox, DID/PLC import. APNs push delivery
  is the first pure-notification-delivery target.
- **Novel framework stack.** First MySQL Fluent driver target
  (prior Fluent trials were Postgres). First adopter using
  `swift-distributed-actors` for clustering. First APNs +
  VaporAPNS target. Extends cross-framework coverage.
- **Pre-engineered protocol surface.** `NotificationSender` is
  already a `Sendable` protocol in `Sources/HAModels/` — no
  adopter-side protocol-extraction work needed. Doc comments on
  the protocol explicitly mention `id` as "a stable id used as
  `apns-collapse-id` and `threadIdentifier`". The adopter has
  already modelled the external-idempotency-key semantics at the
  API boundary.
- **Author has already engaged with idempotency concerns.** The
  implementation at
  `Sources/Server/Controllers/PushNotifcationService.swift:84-87`
  sets `notification.collapseID = id` and
  `notification.threadID = id`, leveraging APNs's
  transport-level dedup. Further comments at lines 191-204
  discuss Live Activity duplicate-prevention reasoning. This is
  an adopter who has independently reached Option B's framing at
  the transport layer; the probe demonstrates how to **test-assert
  the same reasoning at the application layer**.
- **Recently active** (pushed 2026-04-24). Low risk of dep-graph
  drift. Apache-2.0 license — clean fork workflow.
- **Swift tools 6.2.** Fourth distinct toolchain floor now
  validated (plc 6.0, Vernissage 6.2, HomeAutomation 6.2, Penny
  6.3).

## Pinned context

- **SwiftIdempotency tip:** tag `0.3.1`.
- **Upstream target:** `JulianKahnert/HomeAutomation@99751e3`
  (develop tip at trial time, 2026-04-24).
- **Trial fork:** `Joseph-Cursio/HomeAutomation-idempotency-trial`
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch switched to `package-integration-trial`.
- **Trial branch:** `package-integration-trial`.
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Baseline build:** verified green (see trial-findings.md for
  runtime and any pre-flight notes).

## Probe target

`Sources/HAModels/NotificationSender.swift` (protocol) +
`Sources/Server/Controllers/PushNotifcationService.swift`
(implementation), the `sendNotification(title:message:id:)`
method:

```swift
public protocol NotificationSender: Sendable {
    /// Sends an alert notification tagged with a stable `id` used as
    /// `apns-collapse-id` and `threadIdentifier`, allowing the
    /// notification to be coalesced and later cleared individually.
    func sendNotification(title: String, message: String, id: String) async throws
    func clearNotification(id: String) async throws
    // ...
}
```

Canonical at-least-once notification-delivery shape:

- **`id: String`** is the pre-existing external idempotency key.
  Author documentation explicitly identifies it as the "stable id".
  Directly mappable to `IdempotencyKey(fromAuditedString: id)` with
  zero adopter-side modelling work.
- **APNs `collapseID` is a transport-level hint, not a strong
  guarantee.** Coalescing only applies within APNs's buffer
  window; once the first notification has been delivered to the
  device, subsequent sends with the same `collapseID` become
  *fresh* notifications. The application-level gate is
  complementary — don't even ask APNs twice.
- **N device tokens per send → N APNs API calls per invocation.**
  The per-send `effectCount` is the number of device tokens, not
  1. Retry → 2N. This gives the Option B recorder a clean
  multi-effect-per-invocation shape to surface.

## Option B probe design

Three tests mirroring the Vernissage / plc-handle-tracker structure:

1. **Ungated send + `.issueRecord`.** Test-local
   `NotificationSender`-conforming `MockNotificationSender` with
   a fixed device-token count. Handler body calls
   `sendNotification(...)` unconditionally. `.issueRecord`
   captures the snapshot drift (e.g., 3 → 6 for 3 device tokens ×
   2 replays) without aborting.
2. **Dedup-gated send + `IdempotencyKey(fromAuditedString:
   "ha-notify:\(id)")`.** Canonical Option B shape. Second
   invocation short-circuits before
   `notificationSender.sendNotification(...)`.
3. **Distinct-ids sanity.** Two distinct notification ids each
   fire once across a two-run body. Validates the dedup gate
   doesn't collide across unrelated alerts.

## Migration plan (test-target-only)

**No HomeAutomation source files modified.** Trial declares an
inline `MockNotificationSender` conforming to the existing
`NotificationSender` protocol — a real HomeAutomation adoption
would:

- Wrap the existing `PushNotifcationService` call in a dedup gate
  keyed on `id`. Simplest: a `SentNotification` Fluent model with
  `UNIQUE(id)` index, insert-then-send pattern.
- Or a Redis `SETNX ha-notify:{id}` gate at `sendNotification`
  entry (HomeAutomation doesn't currently pull in Redis; would
  require adding the dep).

The refactor cost is documented in the trial-findings doc; not
executed here.

## Pre-flight: system-library dependencies

**TBD during baseline build.** HomeAutomation pins
`swift-distributed-actors` at revision `0041f6a` (unreleased) and
`TibberSwift` at a branch (`fix/linux-foundation-networking`).
Either could be stale or broken on the current toolchain. MySQL
Fluent also requires `mysqlclient` (Homebrew) at build time.

Documented post-build in trial-findings.md.

## Pre-committed questions

1. **Does v0.3.1 compile cleanly on HomeAutomation's dep graph?**
   First adopter with swift-distributed-actors + branch-pinned
   TibberSwift + MySQL Fluent. Any of those could conflict with
   SwiftIdempotency's swift-syntax requirement or test-target
   linking.
2. **Does `.issueRecord` fire on the ungated send shape?**
   Validates R1 on the fourth adopter (post-Penny bug-sweep,
   Vernissage, plc-handle-tracker).
3. **Does the dedup-gated path pass
   `assertIdempotentEffects` on a multi-effect-per-invocation
   body?** The APNs-per-device-token shape produces N effects per
   call — the dedup gate must short-circuit before the per-token
   loop even starts, otherwise the N-effects-are-committed-
   atomically assumption breaks.
4. **What's the refactor cost for real adoption?** With
   `NotificationSender` already extracted, the only work is the
   application-level gate. Estimated <10 LOC — lowest of any
   adopter trial so far.

## Scope commitment

- **Test-target-only.** No HomeAutomation source files modified.
- **No upstream PR.** Non-contribution fork convention preserved.
- **One shape only.** HomeAutomation has other Option-B-eligible
  shapes: `HomeEventProcessingJob.run()` (AsyncStream consumption),
  `startOrUpdateLiveActivity` (push-to-start Live Activity dedup
  with explicit author-documented token-lifecycle reasoning),
  `clearNotification`. Future bug-sweep variant if warranted.

## Predicted outcome

- **Q1 (compile):** ⚠️ **uncertain — real risk here.**
  swift-distributed-actors at a pinned unreleased commit is the
  most speculative dep in any adopter trial so far. If the
  baseline `swift build --target Server` doesn't complete green,
  the probe may need to scope *narrower* than the Server target
  — e.g., importing only `HAModels` into the test target and
  mocking the whole notification surface structurally. Degradation
  plan: if baseline is red, drop Package.swift surgery from
  test-target-opt-in to pure structural mirror (no HomeAutomation
  module imports), preserving the domain-probe value.
- **Q2 (`.issueRecord` fires):** ✅ expected. Same R1 shape as
  prior adopters.
- **Q3 (dedup happy path on multi-effect body):** ✅ expected.
  `IdempotencyKey` short-circuits before the per-device-token
  loop enters — standard Option B body-gate pattern.
- **Q4 (refactor cost):** <10 LOC — lowest so far. Protocol
  already extracted; only the dedup gate is new.

## What the trial decides

**Extends v0.3.1 Option B cross-adopter coverage to APNs push
delivery, HomeKit automation domain, MySQL Fluent, and
swift-distributed-actors stack.** Cross-adopter tally 8 → 9
production adopters. First adopter where the protocol extraction
is **pre-existing rather than invented-for-trial** — strongest
external signal yet that the Option B shape maps onto real
adopter APIs.

## Scope boundaries — NOT in this trial

- **Other HomeAutomation Option B shapes** (`HomeEventProcessingJob`,
  `startOrUpdateLiveActivity`, `clearNotification`). Future
  bug-sweep variant if warranted.
- **Full HomeAutomation refactor** (application-level dedup gate
  in production code). Adopter work.
- **Maintainer engagement / upstream PR.** Non-contribution fork.
- **Linter trial.** Macro-surface validation only.
