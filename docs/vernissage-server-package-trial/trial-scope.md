# VernissageServer — Package Integration Trial Scope

Fresh-external-signal Option B probe, post-v0.3.1 ship. First
adopter-integration trial on a codebase we haven't previously
touched for either a linter round or a package trial.

## Research question

> Does the v0.3.1 Option B surface compile cleanly and catch the
> ActivityPub inbox bug shape on a production Vapor/FluentKit
> ActivityPub server built outside the test-plan's existing trial
> targets?

## Why VernissageServer specifically

- **Fresh adopter signal.** Neither the linter road-tests nor the
  prior package trials touched this codebase. Validates v0.3.1
  Option B on a project that wasn't on anyone's radar during the
  API design.
- **ActivityPub domain.** Fediverse federation is the canonical
  at-least-once-delivery domain in modern server codebases. Other
  ActivityPub servers retry on any 5xx/timeout per spec, so inbox
  handlers MUST be idempotent on the activity's canonical id or
  they ship a spec violation. No judgement call about whether dedup
  is required — it always is.
- **Production Vapor + FluentKit + Postgres + Redis + JWT + S3 +
  Queues.** Full server-side Swift stack; different from Penny's
  Lambda shape, extends framework coverage.
- **Small active maintainer base.** 60 stars, daily commits at
  trial time. Matches the phase-2 test-plan criterion for
  single-contributor / small-team adopters where latent bugs are
  more likely to survive collective review.
- **Swift tools 6.2.** Slightly older than Penny's 6.3 — validates
  SwiftIdempotency 0.3.1 on a second toolchain.

## Pinned context

- **SwiftIdempotency tip:** tag `0.3.1` (first external adopter to
  pin the shipped post-pin-relax release).
- **Upstream target:** `VernissageApp/VernissageServer@6177bfd`
  (develop tip at trial time).
- **Trial fork:** `Joseph-Cursio/VernissageServer-idempotency-trial`
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch switched to `package-integration-trial`.
- **Trial branch:** `package-integration-trial` at
  [`ed40976`](https://github.com/Joseph-Cursio/VernissageServer-idempotency-trial/commit/ed40976).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.

## Option B probe design

Target a single canonical shape rather than a bug-sweep. The
ActivityPub inbox is ideal: spec-mandated idempotency on
`activity.id`, routine redelivery, and a trivial map to
`IdempotencyKey(fromAuditedString:)`.

Three tests:

1. **Ungated inbox + `.issueRecord`.** Demonstrates the detection
   logic without aborting the process — `withKnownIssue { }`
   captures the failure, test continues to verify `effectCount`
   + `persisted` state post-run.
2. **Dedup-gated inbox + `IdempotencyKey(fromAuditedString:
   "ap-inbox:\(activity.id)")`.** Canonical Option B shape. Second
   invocation short-circuits before persistence.
3. **Distinct-ids sanity.** Two distinct activities each persist
   once across a two-run body. Validates the dedup gate doesn't
   accidentally collide across unrelated activities.

## Migration plan (test-target-only)

**No VernissageServer source files modified.** Trial declares an
inline `InboxActivityRepository` protocol + `MockInboxRepository`
in the test file — a real Vernissage adoption would extract this
from `Sources/VernissageServer/Services/ActivityPubService.swift`
and add a Postgres `UNIQUE(activity_id)` constraint or Redis `SETNX`
on activity id.

The refactor cost is documented in the trial-findings doc; not
executed here.

## Pre-flight: system-library dependencies

VernissageServer transitively depends on **SwiftExif** (wrapping
`libexif` + `libiptcdata`) and **SwiftGD** (wrapping `libgd`). Both
need Homebrew-installed C libraries on macOS:

```
brew install libexif libgd libiptcdata
```

And builds need the include path exposed either via:

```
swift build -Xcc -I/opt/homebrew/include ...
```

or via the `CPATH` environment variable:

```
export CPATH=/opt/homebrew/include
swift build ...
```

Documented here so future Vernissage-shape adopters don't rediscover
the pre-flight fix.

## Pre-committed questions

1. **Does v0.3.1 compile cleanly on Vernissage's dep graph?**
   First clean-slate external adopter — any fresh swift-syntax /
   FluentKit / other transitive friction surfaces here.
2. **Does the `.issueRecord` failure mode fire correctly on the
   ungated inbox shape?** Validates the R1 refinement on a new
   adopter.
3. **Does the dedup-gated path pass `assertIdempotentEffects`?**
   Validates the canonical Option B happy path.
4. **What's the refactor cost Vernissage would pay for real
   adoption?** Protocol extraction on the persistence layer + one
   dedup gate at the inbox handler entry.

## Scope commitment

- **Test-target-only.** No VernissageServer source file changes.
- **No upstream PR.** Non-contribution fork per the test-plan
  convention.
- **One shape only.** Vernissage has other Option-B-eligible shapes
  (account signup retries, favourite double-clicks, follow-request
  dedup, avatar upload redelivery) that could be probed in a
  future bug-sweep variant. This trial is a smoke test on a single
  canonical shape.

## Predicted outcome

- **Q1 (compile):** ✅ expected. SwiftIdempotency 0.3.1's pin relax
  should allow clean resolution against Vapor 4 + FluentKit +
  swift-syntax 603.
- **Q2 (`.issueRecord` fires):** ✅ expected. Same shape as Penny's
  bug-sweep tests.
- **Q3 (dedup happy path):** ✅ expected. Standard
  `IdempotencyKey` + in-memory dedup pattern.
- **Q4 (refactor cost):** single protocol extraction + one
  conditional-put gate. Estimated ~10-15 LOC adopter-side. Lower
  than Penny (Penny's `InternalUsersService` has two-repo init
  signature to update; Vernissage's `ActivityPubService` has one
  persistence point per activity verb).

## What the trial decides

**Validates v0.3.1 externally on a fresh adopter** and **extends
cross-adopter Option B tally** from 6 to 7 production adopters.
Registers VernissageServer as an Option B-eligible target if a
future maintainer engagement becomes relevant.

## Scope boundaries — NOT in this trial

- **Other Vernissage Option B shapes** (account signup retries,
  favourite double-clicks, follow-request dedup). Future bug-sweep
  variant.
- **Full Vernissage refactor** (protocol extraction + dedup gate
  in production code). Adopter work.
- **Maintainer engagement / upstream PR.** Non-contribution fork.
- **Linter trial.** Macro-surface validation only; the linter side
  is a separate workstream for a different future session.
