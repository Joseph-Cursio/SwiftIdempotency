# plc-handle-tracker — Package Integration Trial Scope

Fresh-external-signal Option B probe. Second consecutive clean-slate
external adopter (post-Vernissage), first AT Protocol / Bluesky
target, first `vapor/queues` AsyncJob-shape target.

## Research question

> Does the v0.3.1 Option B surface compile cleanly and model the
> at-least-once queue-replay shape on a production Vapor + FluentKit
> + vapor/queues AT Protocol tracker built outside the existing
> trial target set?

## Why plc-handle-tracker specifically

- **Fresh adopter signal.** Neither the linter road-tests nor any
  prior package trial touched this codebase. Validates v0.3.1
  Option B on a project that wasn't on anyone's radar during the
  API design.
- **AT Protocol / Bluesky domain.** `did:plc` is atproto's natural-key
  identity layer; a "handle tracker" polls the plc.directory export
  endpoint, replays the signed-operation chain per DID, and persists
  the history locally. Adjacent to but distinct from the
  ActivityPub domain Vernissage covered — different federation
  protocol, different idempotency shape (content-addressed
  operations rather than activity URIs).
- **`vapor/queues` AsyncJob target.** First adopter trial on an
  `AsyncJob` conformer rather than an HTTP handler. Queues is
  at-least-once by construction — the job runtime will redeliver
  any job whose worker crashes mid-execution or fails its ack. The
  retry-replay shape is structural, not a policy choice.
- **Migration-history evidence this shape was real.** The repo has
  a migration `ChangePrimaryKeyToNaturalKeyOfDidAndCid.swift` that
  retrofits the `operations` table primary key from synthetic onto
  the natural composite `(did, cid)`. Earlier migrations show the
  table had a synthetic UUID PK; the switch is explicitly to make
  duplicate inserts fail-fast at the DB layer. This isn't a
  hypothetical idempotency question — kphrx hit it, fixed it, and
  the fix is preserved in the schema.
- **Single-contributor, small.** 29 stars, 1140 commits in the last
  push window. kphrx owns ~90% of human commits (the rest are
  dependabot + renovate + one drive-by). Matches the phase-2
  test-plan criterion for obscure single-maintainer adopters where
  latent bugs have the least collective-review smoothing.
- **Swift tools 6.0.** Validates SwiftIdempotency 0.3.1 on yet
  another toolchain floor (Penny 6.3, Vernissage 6.2, this one
  6.0). Tests the pin-relax breathing room in the wild.

## Pinned context

- **SwiftIdempotency tip:** tag `0.3.1`.
- **Upstream target:** `kphrx/plc-handle-tracker@6acc696`
  (master tip at trial time, 2026-04-09).
- **Trial fork:**
  `Joseph-Cursio/plc-handle-tracker-idempotency-trial` (hardened:
  issues/wiki/projects disabled, sandbox description). Default
  branch switched to `package-integration-trial`.
- **Trial branch:** `package-integration-trial`.
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64. Package declares
  `swift-tools-version: 6.0`; building on 6.3 is forwards-compatible.
- **Baseline build:** clean on the 6.3 toolchain (`swift build`
  completes in ~67s with no warnings worth flagging, no pre-flight
  system-library gotchas — no SwiftExif/SwiftGD-style friction).

## Probe target

`Sources/Jobs/Dispatched/ImportExportedLogJob.swift` — a
`vapor/queues` `AsyncJob` with the shape:

```swift
struct ImportExportedLogJob: AsyncJob {
  struct Payload: Content {
    let ops: [ExportedOperation]
    let historyId: UUID
  }

  func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
    let app = context.application
    if payload.ops.isEmpty {
      throw "Empty export"
    }
    try await payload.ops.insert(app: app)
  }
}
```

Canonical at-least-once queue shape:

- **`Payload.historyId: UUID`** is the per-job idempotency token —
  textbook `@ExternallyIdempotent(by: historyId)` /
  `IdempotencyKey(fromAuditedString: "plc-import:\(historyId)")`
  shape.
- **`ExportedOperation.cid`** is a content-addressed hash; combined
  with `ExportedOperation.did` it forms the natural key on the
  persisted `Operation` row. The `insert(app:)` extension in
  `Sources/Utilities/ExportedOperation.swift:193` partitions into
  `updateOp` / `createOp` by looking up `Operation.find(.init(cid:
  did:), on: app.db)` first — this is the existing application-
  level dedup. The Option B probe demonstrates what the shape
  looks like *without* that partition step.

## Option B probe design

Three tests mirroring the Vernissage inbox structure:

1. **Ungated replay + `.issueRecord`.** Test-local
   `OperationRepository` protocol + `MockOperationRepository`
   conformer. Job body persists every op in every replay
   unconditionally. `.issueRecord` captures the snapshot drift
   without aborting; test continues to verify `effectCount` and
   `persisted.count` post-run.
2. **Dedup-gated replay + `IdempotencyKey(fromAuditedString:
   "plc-import:\(historyId)")`.** The canonical Option B shape.
   Second invocation short-circuits before
   `repository.insert(...)`.
3. **Distinct-historyIds sanity.** Two distinct historyIds each
   persist once across a two-run body. Validates the dedup gate
   doesn't accidentally collide across unrelated imports.

## Migration plan (test-target-only)

**No plc-handle-tracker source files modified.** Trial declares
an inline `OperationRepository` protocol +
`MockOperationRepository` in the test file — a real
plc-handle-tracker adoption would:

- Extract the `[ExportedOperation].insert(app:)` extension into a
  mockable protocol on `OperationRepository`.
- Add a Redis `SETNX` gate on `"plc-import:\(historyId)"` before
  dispatching the job body, or equivalently a `PollingHistory`
  row with `UNIQUE(historyId)` as the dedup token.

The refactor cost is documented in the trial-findings doc; not
executed here.

## Pre-flight: system-library dependencies

**None.** Unlike Vernissage (SwiftExif/SwiftGD needing Homebrew
`libexif`/`libgd`/`libiptcdata`), plc-handle-tracker's deps are
pure-Swift: vapor, fluent, fluent-postgres-driver, queues,
queues-redis-driver, leaf. No C-library pre-flight required on
macOS/arm64.

## Pre-committed questions

1. **Does v0.3.1 compile cleanly on plc-handle-tracker's dep
   graph?** Validates the pin relax against a third distinct
   Swift-tools floor (6.0 here; 6.2 on Vernissage; 6.3 on Penny).
2. **Does the `.issueRecord` failure mode fire correctly on the
   ungated import shape?** Validates R1 on yet another adopter.
3. **Does the dedup-gated path pass `assertIdempotentEffects`?**
   Validates the canonical Option B happy path on a queue-job
   shape (not an HTTP handler).
4. **What's the refactor cost for real adoption?** Protocol
   extraction on `[ExportedOperation].insert(app:)` + one dedup
   gate at job entry. Estimated comparable to Vernissage
   (~10-15 LOC).

## Scope commitment

- **Test-target-only.** No plc-handle-tracker source file changes.
- **No upstream PR.** Non-contribution fork per the test-plan
  convention.
- **One shape only.** plc-handle-tracker has other Option-B-eligible
  shapes: `ImportAuditableLogJob`, `PollingPlcServerExportJob`,
  `FetchDidJob` all walk similar replay territory with different
  payload shapes. This trial is a smoke test on the single
  shape most directly mapped to at-least-once delivery.

## Predicted outcome

- **Q1 (compile):** ✅ expected. swift-syntax pin relax should
  hold; no exotic deps.
- **Q2 (`.issueRecord` fires):** ✅ expected. Same R1 shape as
  Penny's bug-sweep tests and Vernissage.
- **Q3 (dedup happy path):** ✅ expected. Standard
  `IdempotencyKey` + in-memory dedup pattern, adapted for the
  AsyncJob-body shape rather than HTTP-handler shape.
- **Q4 (refactor cost):** single protocol extraction + one
  conditional-put gate. Estimated ~10-15 LOC adopter-side. The
  existing `insert(app:)` extension already contains the
  partition logic — extraction into a mockable protocol is the
  mechanical part; the novel work is just the `historyId` gate.

## What the trial decides

**Validates v0.3.1 externally on a fresh adopter, first on an
AsyncJob shape, first atproto target** and **extends cross-adopter
Option B tally from 7 to 8 production adopters**.

## Scope boundaries — NOT in this trial

- **Other plc-handle-tracker jobs** (`ImportAuditableLogJob`,
  `PollingPlcServerExportJob`, `FetchDidJob`). Future bug-sweep
  variant if momentum warrants.
- **Full plc-handle-tracker refactor** (protocol extraction +
  Redis SETNX gate in production code). Adopter work.
- **Maintainer engagement / upstream PR.** Non-contribution fork.
- **Linter trial.** Macro-surface validation only; the linter
  side is a separate workstream.
