# HomeAutomation — Package Integration Trial Findings

Fresh-external-signal Option B probe, validating SwiftIdempotency
0.3.1 on a production HomeKit-automation server
(`JulianKahnert/HomeAutomation`). Trial scope in
[`trial-scope.md`](trial-scope.md); fork and branch pointers at
the foot.

## Headline

**v0.3.1 compiles cleanly on HomeAutomation's dep graph and all
three Option B tests pass** (3/3 green, 1 known-issue from the
intentional `.issueRecord` negative-path test). No new API
friction surfaced. **Third consecutive clean-slate fresh-signal
round with zero API friction** (first Vernissage, second
plc-handle-tracker).

Cross-adopter tally bumps from 8 to **9 production adopters** with
the Option B / `IdempotencyKey` surface validated end-to-end:
Penny, isowords, prospero, myfavquotes-api, luka-vapor, hellovapor,
VernissageServer, plc-handle-tracker, **HomeAutomation**.

First **APNs-delivery target** and first **HomeKit-automation
domain**. Also first adopter where the probed protocol is
**pre-existing in the adopter's own module** (`HAModels.NotificationSender`)
rather than extracted-for-trial — the test-target imports it
directly and conforms to it via a `MockNotificationSender`.

## Pre-committed question answers

| # | Question | Answer |
|---|---|---|
| 1 | Does v0.3.1 compile cleanly on HomeAutomation's dep graph? | ✅ Yes. `swift-distributed-actors` pinned at `0041f6a` + `TibberSwift` on a branch + MySQL Fluent + APNSwift + TCA all resolve transitively with SwiftIdempotency's swift-syntax requirement. |
| 2 | Does `.issueRecord` fire on the ungated send shape? | ✅ Yes. Failure captured via `withKnownIssue`; snapshot drift 0 → 3 → 6 (3 devices × 2 replays) correctly surfaced. |
| 3 | Does the dedup-gated path pass `assertIdempotentEffects` on a multi-effect-per-invocation body? | ✅ Yes. Gate short-circuits before the per-device-token fan-out runs; second invocation returns cleanly. `effectCount` stays at 3 across both invocations. |
| 4 | Refactor cost for real adoption? | **~5-8 LOC** — lowest of any adopter trial so far. `NotificationSender` is already an extracted `Sendable` protocol in `HAModels`; the dedup gate is the only new code. |

## Per-test results

### Test 1 — Ungated send + `.issueRecord`

```
Recorder MockNotificationSender snapshot changed across the second
invocation.
    baseline (pre-body):        0
    after first invocation:     3
    after second invocation:    6
```

Observed: `effectCount` goes 0 → 3 → 6 across the two-run body;
`alertsSent.count == 6` with all six sharing the same
notification id. This is the exact fan-out shape real
HomeAutomation users would see on retry — a user with the
HomeAutomation iOS client on iPhone + iPad + Watch gets the same
"Front Door Unlocked" alert twice per device.

Note on APNs's `collapseID`: the real `PushNotifcationService`
already sets `notification.collapseID = id` and
`notification.threadID = id` (source at
`Sources/Server/Controllers/PushNotifcationService.swift:84-87`).
APNs coalesces alerts with the same `collapseID` that are *still
buffered* at the APNs edge when the second send arrives — but
once the first alert has been delivered to the device, the second
becomes a fresh user-visible notification. The application-level
gate is complementary, catching the duplicate *before* the N
per-device APNs requests even start.

### Test 2 — Dedup-gated send

```swift
try await assertIdempotentEffects(recorders: [sender]) {
    try await handlerGated(id: Self.sampleID)
}
```

Observed: first invocation claims the `id`-based dedup gate,
sendNotification fans out to 3 device tokens. Second invocation
hits the cache, short-circuits before any
`sender.sendNotification(...)` call. `effectCount == 3`,
`alertsSent.count == 3`. Passes.

**Critical ordering property confirmed:** the dedup gate must
short-circuit *before* the per-device-token loop inside
`sendNotification`, not after. If the gate were inside the loop
(e.g., per-device-token dedup), a partial-delivery retry would
still send to non-delivered devices — violating the
"sendNotification-is-atomic" semantics the caller expects. The
probe confirms the gate placement at the send entry is the
correct level.

### Test 3 — Distinct-ids sanity

Two distinct notification ids across the body (front-door and
living-room-light). Each fans out to 2 devices exactly once
across a two-run body. `effectCount == 2 × 2 = 4`, with the
filter assertions confirming 2 sends per id. Passes — dedup
doesn't accidentally collide across unrelated notifications.

## Surfacing findings

### 1. First pre-extracted adopter protocol

All prior 8 trials extracted a protocol *for the trial* — the
trial's mock conformed to something that didn't exist in the
adopter's code. HomeAutomation is the first where:

- `NotificationSender` is already a `public protocol` in
  `Sources/HAModels/NotificationSender.swift`.
- It's already `Sendable`-conformed.
- Its doc comments already identify `id` as "a stable id used as
  `apns-collapse-id` and `threadIdentifier`" — the adopter has
  already articulated the external-idempotency-key semantics.

The test-target imports `HAModels` and conforms
`MockNotificationSender` to `NotificationSender` directly. **No
protocol-shape invention, no extraction refactor needed for the
trial.** This is the cleanest adopter-surface match of any trial.

### 2. Adopter has independently reached Option B framing at the transport layer

`PushNotifcationService` already uses `collapseID` and `threadID`
to leverage APNs's transport-level dedup. The implementation
comments at lines 191-204 describe the author's own reasoning
about Live Activity duplicate-prevention (the push-to-start
token lifecycle). Lines 212-218 describe CancellationError
handling with the explicit framing "we want to send the most
recent state, not stale data."

**This is an author who has independently reached the Option B
framing at the transport layer.** The SwiftIdempotency surface
demonstrates how to *test-assert the same reasoning at the
application layer* — completing the picture rather than
introducing new concerns.

### 3. Multi-effect-per-invocation body doesn't destabilise the recorder

Prior 8 trials all had per-invocation effect count of 1 (one
row inserted, one activity persisted, one `save(on:)` call).
HomeAutomation is the first where a single invocation produces
`N > 1` effects (one per device token). The `IdempotentEffectRecorder`
surface handles this cleanly — the recorder's `effectCount`
accrues per *individual* effect, and `assertIdempotentEffects`
compares the full snapshot across the two invocations without
any per-call-granularity assumptions.

**Confirms R2's `Snapshot: Equatable = Int` default is
sufficient for fan-out shapes** — adopters with richer per-device
state could opt into `Snapshot = [(id, deviceIndex)]` for tighter
diagnostics, but the default Int covers the bug-catch.

### 4. Novel dependency stack resolved cleanly

First adopter with:
- `swift-distributed-actors` (revision-pinned unreleased commit
  `0041f6a`)
- `TibberSwift` (branch-pinned)
- `fluent-mysql-driver` (all prior Fluent trials were Postgres)
- `swift-openapi-generator` + `swift-openapi-vapor` + OpenAPI
  code-gen plugin in the Server target
- APNSwift + VaporAPNS

Baseline `swift build --target Server` completed green in 183.6s
on the current toolchain (6.3.1); adding the SwiftIdempotency
0.3.1 dep + the `IdempotencyTrialTests` target bumped the test
build to 226s (one-time cost; incremental test runs are
instantaneous).

**Zero transitive-dependency friction from SwiftIdempotency's
swift-syntax requirement** against the most exotic dep graph
trialled so far.

## Refactor cost estimate — real HomeAutomation adoption

A real JulianKahnert-side adoption of Option B at the
`PushNotifcationService.sendNotification` layer would look like:

1. **Add a `SentNotification` Fluent model with `UNIQUE(id)`**
   (~5 LOC) — migration + model. Already consistent with
   HomeAutomation's existing FluentKit usage.
2. **Wrap the `sendAlert` call in an insert-then-send pattern**
   (~3 LOC) — `try SentNotification(id: id).create(on: database)`
   throws on duplicate; catch the unique-violation, return early.

Total: **~5-8 LOC adopter-side**. Lowest of any trial so far.
The protocol is already shaped right; the only new code is the
dedup model + one insert-then-send gate.

Alternative: Redis SETNX on `ha-notify:{id}`. HomeAutomation
doesn't currently pull in Redis, so adding a dep would cost more
than the Fluent approach.

## Trial commitments honoured

- ✅ **Test-target-only.** `Sources/HAModels/NotificationSender.swift`
  and `Sources/Server/Controllers/PushNotifcationService.swift`
  unmodified. No HomeAutomation production code touched.
- ✅ **No upstream PR.** Non-contribution fork convention
  preserved.
- ✅ **One shape only.** `HomeEventProcessingJob.run()`,
  `startOrUpdateLiveActivity`, `clearNotification` unprobed;
  future bug-sweep variant if needed. The Live Activity
  push-to-start shape looks particularly rich — author's own
  comments explicitly discuss duplicate-prevention reasoning.

## Context

- **SwiftIdempotency tip pinned:** tag `0.3.1`.
- **Upstream target:** `JulianKahnert/HomeAutomation@99751e3`
  (develop tip at trial time, 2026-04-24).
- **Trial fork:** [`Joseph-Cursio/HomeAutomation-idempotency-trial`](https://github.com/Joseph-Cursio/HomeAutomation-idempotency-trial)
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch: `package-integration-trial`.
- **Trial branch tip:** `package-integration-trial` at
  [`26cb15b`](https://github.com/Joseph-Cursio/HomeAutomation-idempotency-trial/commit/26cb15b).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Baseline build:** clean, 183.6s Server-target cold build; no
  system-library pre-flight required beyond what the dep graph
  fetches automatically.
- **Trial test-target build:** 226s (first run with SwiftIdempotency
  linked in). Test runtime: 3 tests, 0.001s wall-clock.

## Cross-adopter Option B tally

9 production adopters validated end-to-end on the `IdempotencyKey`
/ `IdempotentEffectRecorder` / `.issueRecord` surface:

| # | Adopter | Shape | Framework | Pre-existing key? |
|---|---|---|---|---|
| 1 | Penny | Lambda handler | AWS Lambda + SotoDynamoDB | implicit |
| 2 | isowords | HTTP handler | PointFree HttpPipeline | implicit |
| 3 | prospero | HTTP handler | Hummingbird | implicit |
| 4 | myfavquotes-api | HTTP handler | Hummingbird | implicit |
| 5 | luka-vapor | HTTP handler | Vapor | implicit |
| 6 | hellovapor | HTTP handler | Vapor + FluentKit | implicit |
| 7 | VernissageServer | HTTP handler (inbox) | Vapor + FluentKit | `activity.id` |
| 8 | plc-handle-tracker | AsyncJob | Vapor + vapor/queues | `historyId: UUID` |
| 9 | **HomeAutomation** | **APNs send** | **Vapor + APNSwift + MySQL Fluent** | **`id: String` (documented)** |

**Nine-for-nine Option B surface coverage** across AWS Lambda /
PointFree HttpPipeline / Hummingbird / Vapor / Vapor + vapor/queues /
Vapor + APNSwift. First APNs-delivery target. First adopter
where the external idempotency key is **named in the protocol's
own public API documentation** rather than inferred from payload
content.

## What this trial decides

**Validates v0.3.1 externally on a third consecutive fresh
adopter, on a new domain (HomeKit), new delivery class (APNs),
new ORM (MySQL Fluent), and new cluster framework
(swift-distributed-actors).** Strongest no-friction round yet —
the probed protocol was already extracted in the adopter's own
module. **Three consecutive zero-friction rounds** is now a
stable pattern.

Per the road-test-plan convention (3/3 consecutive plateaus =
SHIP), this round closes the analogous bar for Option B surface
stability. Selection criterion going forward: domain/shape
novelty, not project obscurity (memory updated accordingly).
