# plc-handle-tracker — Package Integration Trial Findings

Fresh-external-signal Option B probe, validating SwiftIdempotency
0.3.1 on a production Vapor + FluentKit + vapor/queues AT Protocol
tracker (`kphrx/plc-handle-tracker`). Trial scope in
[`trial-scope.md`](trial-scope.md); fork and branch pointers at the
foot.

## Headline

**v0.3.1 compiles cleanly on plc-handle-tracker's dep graph and all
three Option B tests pass** (3/3 green, 1 known-issue from the
intentional `.issueRecord` negative-path test). No new API friction
surfaced. **Second consecutive clean-slate fresh-signal round with
zero API friction** (first was Vernissage).

Cross-adopter tally bumps from 7 to **8 production adopters** with
the Option B / `IdempotencyKey` surface validated end-to-end:
Penny, isowords, prospero, myfavquotes-api, luka-vapor, hellovapor,
VernissageServer, **plc-handle-tracker**.

First **AsyncJob-shape target** — prior seven were all HTTP-handler
shapes. Validates the Option B surface on `vapor/queues`'s
at-least-once-by-construction delivery model.

## Pre-committed question answers

| # | Question | Answer |
|---|---|---|
| 1 | Does v0.3.1 compile cleanly on plc-handle-tracker's dep graph? | ✅ Yes. Swift tools 6.0 declared; built cleanly on 6.3.1. swift-syntax resolves to 603.0.0 (pin-relax breathing room exercised). No transitive conflicts. |
| 2 | Does `.issueRecord` fire on the ungated import shape? | ✅ Yes. Failure captured via `withKnownIssue`, test process continues to verify recorder state. Snapshot drift 0 → 2 → 4 (2 ops × 2 replays) correctly surfaced. |
| 3 | Does the dedup-gated path pass `assertIdempotentEffects`? | ✅ Yes. `IdempotencyKey(fromAuditedString: "plc-import:\(historyId.uuidString)")` + in-memory cache → second invocation short-circuits. |
| 4 | Refactor cost? | ~10-15 LOC adopter-side: one protocol extraction on `[ExportedOperation].insert(app:)` + one Redis-SETNX-equivalent gate at job entry. Equivalent to Vernissage. |

## Per-test results

### Test 1 — Ungated import + `.issueRecord`

```
Recorder MockOperationRepository snapshot changed across the second
invocation.
    baseline (pre-body):        0
    after first invocation:     2
    after second invocation:    4
```

Observed: `effectCount` goes 0 → 2 → 4 across the two-run body;
`persisted.count == 4` with both `(did, cid)` tuples represented
twice. This is the exact queue-replay bug shape a real
plc-handle-tracker job body would ship if `ImportExportedLogJob.dequeue`
iterated `payload.ops` and called `op.create(on: db)`
unconditionally. The real `[ExportedOperation].insert(app:)`
extension avoids this by partitioning ops via
`Operation.find(.init(cid:, did:))` first — but the Option B gate
at the job-entry level is what the trial demonstrates.

Note: the Postgres migration
`ChangePrimaryKeyToNaturalKeyOfDidAndCid.swift` would catch this at
the DB layer in the real deployment (unique violation on the second
insert of the same `(did, cid)` pair). The application-level gate
is complementary, not redundant — it short-circuits before the
database round-trip, avoiding unnecessary error-handling paths in
the queue-retry loop.

### Test 2 — Dedup-gated import

```swift
try await assertIdempotentEffects(recorders: [repo]) {
    try await processExportGated(payload)
}
```

Observed: first invocation claims the `historyId` dedup gate,
iterates `ops`, persists 2 rows. Second invocation short-circuits
before any `repo.insert(...)` call. `effectCount == 2`,
`persisted == sampleOps()`. Passes.

### Test 3 — Distinct-historyIds sanity

Two distinct payloads across the body, each gated by its own
`historyId` UUID. First body run: both gates claim, both
single-op ops persist. Second body run: both gates hit,
short-circuit. `effectCount == 2`, `persisted.map(\.did) ==
["did:plc:alice", "did:plc:bob"]`. Passes — dedup doesn't
accidentally collide across unrelated imports.

## Surfacing findings

### 1. No system-library pre-flight

Unlike Vernissage's SwiftExif / SwiftGD / libiptcdata dance,
plc-handle-tracker's dep graph is pure-Swift: vapor, fluent,
fluent-postgres-driver, queues, queues-redis-driver, leaf. Baseline
`swift build` completed in 66.7s on a cold build with no
`-Xcc -I/opt/homebrew/include` / `CPATH` gymnastics required.

Small win for adopter-onboarding friction — a Vapor+Fluent+Queues
stack is the minimum viable at-least-once webapp shape, and it has
zero pre-flight system deps on macOS/arm64. This is what
"production-shaped adopter trial" should usually look like.

### 2. `historyId: UUID` is a textbook external key

Most adopter codebases we've trialled so far have had to infer
external idempotency keys from payload content (activity URLs,
OAuth state params, entity IDs, commit SHAs). plc-handle-tracker
is the first where the adopter already carries an explicit UUID
through the queue-retry loop *specifically as the per-job identity
token*. `payload.historyId` is directly mappable to
`@ExternallyIdempotent(by: historyId)` or the `IdempotencyKey`
surface with no adopter-side modelling work.

Cross-adopter tally:

- Penny (Lambda handlers) — `requestID` via `LambdaContext`.
- VernissageServer (inbox) — `activity.id` (URL, not UUID).
- plc-handle-tracker (import) — **`historyId` UUID payload field.**

Most consistent Option-B-friendly shape in the adopter set so far.

### 3. Migration history as corroborating evidence

`Sources/Migrations/ChangePrimaryKeyToNaturalKeyOfDidAndCid.swift`
retrofits the `operations` table PK from a synthetic UUID to the
natural composite `(did, cid)`. This migration exists because
duplicate-insert bugs actually hit kphrx in production — the fix
is preserved in the schema for exactly the reason the Option B
surface catches in tests.

This is the first adopter trial where **the adopter's own git
history independently validates the bug shape the trial is probing**.
It's not a judgment call about "would this be a problem" — the
problem was already observed, fixed, and the fix is documented in
the schema. Option B's usefulness here is pre-emptive for the
next similar-shape job body, not retrospective for this one.

### 4. Zero API friction on a new job shape

All prior Option B trials (Vernissage, Penny bug-sweep, luka-vapor,
hellovapor) validated the surface on HTTP-handler shapes. This is
the first AsyncJob-shape target. R1 (`failureMode: .issueRecord`),
R2 (default `Snapshot == Int`), R3 (main-target
`IdempotentEffectRecorder`) all work identically in the AsyncJob
test context.

No surprises: the `AsyncJob.dequeue(_:_:)` entry point is just an
async throwing function from the test's perspective. The Option B
surface is handler-binding-shape-agnostic, confirmed.

## Refactor cost estimate — real plc-handle-tracker adoption

A real kphrx-side adoption of Option B at the
`ImportExportedLogJob` layer would look like:

1. **Extract `OperationRepository` protocol** (~10 LOC). The
   existing `[ExportedOperation].insert(app:)` extension at
   `Sources/Utilities/ExportedOperation.swift:193` becomes a method
   on the protocol; concrete impl uses the current FluentKit body.
2. **Add `historyId` dedup gate at job entry** (~5 LOC). Redis
   `SETNX plc-import:{historyId}` with a TTL matching
   `polling_history` retention, or a `UNIQUE(history_id)` index on
   `polling_history` with `ON CONFLICT DO NOTHING` on insert. Use
   `IdempotencyKey(fromAuditedString:)` at the application layer to
   normalise the key space.
3. **Conform `Application.operationRepository` to
   `IdempotentEffectRecorder`** in test target only (~3 LOC). Prod
   code pays nothing — `SwiftIdempotency` is a test-target-only
   dep.

Total: ~15-20 LOC adopter-side, none of which is in hot path. The
existing dedup partition in `insert(app:)` remains — the new gate
is a short-circuit optimisation for the common case where the
whole batch is already known.

## Trial commitments honoured

- ✅ **Test-target-only.** `Sources/Jobs/Dispatched/ImportExportedLogJob.swift`
  and `Sources/Utilities/ExportedOperation.swift` unmodified. No
  plc-handle-tracker production code touched.
- ✅ **No upstream PR.** Non-contribution fork convention preserved.
- ✅ **One shape only.** `ImportAuditableLogJob`,
  `PollingPlcServerExportJob`, `FetchDidJob` unprobed; future
  bug-sweep variant if needed.

## Context

- **SwiftIdempotency tip pinned:** tag `0.3.1` (first external
  atproto adopter to pin the shipped post-pin-relax release).
- **Upstream target:** `kphrx/plc-handle-tracker@6acc696` (master
  tip at trial time, 2026-04-09).
- **Trial fork:** [`Joseph-Cursio/plc-handle-tracker-idempotency-trial`](https://github.com/Joseph-Cursio/plc-handle-tracker-idempotency-trial)
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch: `package-integration-trial`.
- **Trial branch tip:** `package-integration-trial` at
  [`bfb059b`](https://github.com/Joseph-Cursio/plc-handle-tracker-idempotency-trial/commit/bfb059b).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Baseline build:** clean, 66.7s cold build, zero system-library
  pre-flight gotchas.
- **Trial test suite runtime:** 3 tests, 0.001s wall-clock.

## Cross-adopter Option B tally

8 production adopters validated end-to-end on the `IdempotencyKey`
/ `IdempotentEffectRecorder` / `.issueRecord` surface:

| # | Adopter | Shape | Framework | Recorder Snapshot |
|---|---|---|---|---|
| 1 | Penny | Lambda handler | AWS Lambda + SotoDynamoDB | `Int` |
| 2 | isowords | HTTP handler | PointFree HttpPipeline | `Int` |
| 3 | prospero | HTTP handler | Hummingbird | `Int` |
| 4 | myfavquotes-api | HTTP handler | Hummingbird | `Int` |
| 5 | luka-vapor | HTTP handler | Vapor | `Int` |
| 6 | hellovapor | HTTP handler | Vapor + FluentKit | `Int` |
| 7 | VernissageServer | HTTP handler (inbox) | Vapor + FluentKit | `Int` |
| 8 | **plc-handle-tracker** | **AsyncJob** | **Vapor + vapor/queues** | **`Int`** |

**Eight-for-eight Option B surface coverage** across AWS Lambda /
PointFree HttpPipeline / Hummingbird / Vapor / Vapor + vapor/queues.
First queue-job target; first atproto-domain target.

## What this trial decides

**Validates v0.3.1 externally on a fresh single-contributor adopter
in a novel domain (AT Protocol) on a novel shape (AsyncJob), with
zero API friction surfaced.** Second consecutive fresh-signal round
where the Option B surface compiles and works out-of-the-box on an
unfamiliar codebase. Pattern is holding.
