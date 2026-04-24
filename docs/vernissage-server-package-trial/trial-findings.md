# VernissageServer — Package Integration Trial Findings

Fresh-external-signal Option B probe, validating SwiftIdempotency
0.3.1 on a production Vapor/FluentKit ActivityPub server
(VernissageApp/VernissageServer). Trial scope in
[`trial-scope.md`](trial-scope.md); fork and branch pointers at the
foot.

## Headline

**v0.3.1 compiles cleanly on Vernissage's dep graph and all three
Option B tests pass** (3/3 green, 1 known-issue from the
intentional `.issueRecord` negative-path test). No new API friction
surfaced.

Cross-adopter tally bumps from 6 to **7 production adopters** with
the Option B / `IdempotencyKey` surface validated end-to-end:
Penny, isowords, prospero, myfavquotes-api, luka-vapor, hellovapor,
**VernissageServer**.

## Pre-committed question answers

| # | Question | Answer |
|---|---|---|
| 1 | Does v0.3.1 compile cleanly on Vernissage's dep graph? | ✅ Yes. Transitive swift-syntax resolved to 603 (up from 602 under the v0.3.0 exact pin). FluentKit, JWT-Kit, Soto, Redis, SwiftExif, SwiftGD all coexist. |
| 2 | Does `.issueRecord` fire on the ungated inbox shape? | ✅ Yes. Failure captured via `withKnownIssue`, test process continues to verify recorder state. |
| 3 | Does the dedup-gated path pass `assertIdempotentEffects`? | ✅ Yes. `IdempotencyKey(fromAuditedString: "ap-inbox:\(activity.id)")` + in-memory cache → second invocation short-circuits. |
| 4 | Refactor cost? | ~10-15 LOC adopter-side: one protocol extraction on the persistence layer + one conditional-put gate at handler entry. Lower than Penny's cost. |

## Per-test results

### Test 1 — Ungated inbox + `.issueRecord`

```
Recorder MockInboxRepository snapshot changed across the second
invocation.
    baseline (pre-body):        0
    after first invocation:     1
    after second invocation:    2
```

Observed: `effectCount` goes 0 → 1 → 2 across the two-run body;
`persisted.count == 2` with both entries having the same
`activity.id`. This is the exact ActivityPub-spec-violating shape
a real Vernissage inbox handler would ship if it persisted
unconditionally on POST.

### Test 2 — Dedup-gated inbox

```
try await assertIdempotentEffects(recorders: [repo]) {
    try await processActivityGated(activity)
}
```

Observed: first invocation claims the dedup gate, persists one
row. Second invocation short-circuits before `repo.persist(...)`.
`effectCount == 1`, `persisted == [activity]`. Passes.

### Test 3 — Distinct-ids sanity

Two distinct activities across the body, each gated by its own
`activity.id`. First invocation persists both, gates claim both
tokens. Second invocation short-circuits on both. `effectCount ==
2`, `persisted == [first, second]`. Passes — dedup doesn't
accidentally collide across unrelated activities.

## Surfacing finding — system-library pre-flight

Not a SwiftIdempotency issue, but worth capturing for future
Vernissage-shape trials: VernissageServer's SwiftExif and SwiftGD
deps need Homebrew-installed C libraries (`libexif`, `libgd`,
`libiptcdata`), and the Swift builder doesn't find
`/opt/homebrew/include` by default on macOS/arm64. Either set
`CPATH=/opt/homebrew/include` or pass `-Xcc -I/opt/homebrew/include`
on every `swift build/test` invocation.

This is an adopter-side pre-flight, not a SwiftIdempotency bug. But
it's the kind of gotcha that would eat 20-30 minutes on a fresh
machine if undocumented, so registered in the trial-scope doc for
future Vernissage-shape validators.

## Option B refinement exercise

| Refinement | Exercised? | Result |
|---|---|---|
| **R1** — `failureMode: .issueRecord` | Test 1 | Clean. `Issue.record` fires; `withKnownIssue` captures; test continues. |
| **R2** — `Snapshot: Equatable = Int` default | Tests 1-3 (all use default `Int`) | Clean. Where-clause extension provides `snapshot() -> Int` from `effectCount`; no custom typealias needed for this shape. |
| **R3** — Protocol in main target | All three tests | Clean. `MockInboxRepository` conforms to `IdempotentEffectRecorder` directly from `import SwiftIdempotency`; `SwiftIdempotencyTestSupport` only needed for the `assertIdempotentEffects` call. |

The custom `Snapshot` overload (R2's precision path) isn't
exercised here — the ActivityPub inbox bug is visible in the count
alone ("one new activity row on retry" is the snapshot-size-of-1
delta that default `Int` catches). A richer trial shape — e.g.,
the same-count-different-content retry scenario — would exercise
the `[String]` call-log overload, but this trial stuck to canonical-
shape per the scope commitment.

## What this validates

- **v0.3.1 is externally ship-worthy on fresh adopters.** Compiles
  cleanly against Vapor 4 + FluentKit + Redis + JWT + Soto +
  Postgres drivers with no transitive-dep friction.
- **Option B generalizes to ActivityPub federation.** The canonical
  shape — spec-mandated dedup on a server-supplied message id —
  maps to `IdempotencyKey(fromAuditedString:)` exactly as adopters
  would expect.
- **Cross-adopter tally at 7 production apps.** Adds a
  server-side Vapor photo-sharing platform to the existing coverage
  (Discord Lambda bot, SPM index, two Hummingbird apps, two small
  Vapor apps, game server).

## Not validated by this trial

- **Other Vernissage Option B shapes.** Account signup
  (email-sends), favourites (double-click), follow-requests
  (duplicate friendship row), avatar uploads (S3 PUT on redelivery)
  are all adopter-realistic shapes but not probed. A future
  Vernissage bug-sweep variant could widen coverage, mirroring the
  Penny bug-sweep pattern.
- **Production code path.** Tests run against stand-in protocols,
  not the real `ActivityPubService`. Refactor cost is documented;
  the refactor itself is adopter work.
- **Linter side.** This trial is macro-surface-only. The linter
  side (whether SwiftProjectLint's Vapor + FluentKit + Route-DSL
  whitelists + route-trailing-closure annotations cover
  VernissageServer cleanly) is a separate future round.

## Follow-ups — parked candidates

- **Vernissage linter round.** Run SwiftProjectLint on the trial
  fork with `@lint.context replayable` banner on the
  ActivityPubActorController inbox handlers. 30+ controllers and
  a rich SQL-backed persistence layer; likely to surface at least
  one slice-driven candidate.
- **Vernissage bug-sweep variant.** Add 2-3 more Option B tests on
  shapes beyond the inbox (favourite, follow, signup email).
  Exercise the `Snapshot = [String]` overload on one of them.

## Cross-references

- [`../release-notes/v0.3.1.md`](../release-notes/v0.3.1.md) — the
  swift-syntax pin relax that unblocked this trial (and will
  unblock any future Vapor adopter whose graph includes a 603+
  transitive requirement).
- [`../penny-package-trial/bug-sweep-findings.md`](../penny-package-trial/bug-sweep-findings.md)
  — Penny's bug-sweep, second-to-last cross-adopter validation.
- [`trial-scope.md`](trial-scope.md) — this trial's scope doc.
- [`Joseph-Cursio/VernissageServer-idempotency-trial@ed40976`](https://github.com/Joseph-Cursio/VernissageServer-idempotency-trial/tree/package-integration-trial)
  — the trial branch on the Vernissage fork.
