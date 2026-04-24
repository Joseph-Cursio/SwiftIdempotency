# VernissageServer Bug-Sweep Trial — Findings

Follow-up to [`trial-findings.md`](trial-findings.md) (the
ActivityPub-inbox smoke test), extending Option B coverage to three
more adopter-realistic shapes on the same Vernissage fork. Layers a
`bug-sweep` branch on top of the existing
`package-integration-trial` branch; the inbox test is preserved
intact as a regression baseline.

## Trial tips

- **SwiftIdempotency:** tag `0.3.1` (unchanged from the inbox probe).
- **Trial fork branch:** `bug-sweep` at
  [`Joseph-Cursio/VernissageServer-idempotency-trial@3d97ef8`](https://github.com/Joseph-Cursio/VernissageServer-idempotency-trial/tree/bug-sweep).
  Forked from `package-integration-trial@ed40976`.
- **Upstream target:** same as inbox probe
  (`VernissageApp/VernissageServer@6177bfd`).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Pre-flight:** Homebrew `libexif`/`libgd`/`libiptcdata` +
  `CPATH=/opt/homebrew/include`. Documented once in the original
  trial scope; reused here.

## Research question

> Does the v0.3.1 Option B surface generalize past the single
> ActivityPub-inbox shape to the dominant adopter-realistic
> side-effect classes in a production Vapor server — email-send,
> DB unique-constraint-equivalent, and S3 object storage? And does
> R2's custom `Snapshot = [String]` overload earn its keep on a
> non-trivial shape?

## Headline

**Yes on both counts.** 6/6 new tests green across 3 new suites (9/9
total including the inbox); 3 new known issues from the ungated
`.issueRecord` demonstrations (4 total). All three v0.3.1 refinements
continue to hold across a diverse spread of side-effect classes
(email, DB, file storage).

## Per-shape results

### 1. Account signup welcome email — ✅ caught

**Stand-in for:** `AccountController.signup` → welcome email via the
`Smtp` Vapor package. Client retry on HTTP timeout = duplicate email.

**Option B coverage (ungated):** `.issueRecord` fires on the second
invocation; recorder observes two identical emails to the same
address. Default `Snapshot == Int` suffices.

**Option B coverage (gated):** `IdempotencyKey(fromAuditedString:
"signup:\(clientRequestID)")` + in-memory dedup. First invocation
sends; second short-circuits. Real fix shape: client-provided
`X-Idempotency-Token` header or equivalent client-side UUID cached
for the signup flow's TTL.

**Refactor cost:** `WelcomeEmailSender` protocol extraction
(~5 LOC) + dedup-cache lookup at handler entry (~3 LOC).

### 2. Follow request — ✅ caught, Option B as test-side safety net

**Stand-in for:** `FollowRequestsController.follow` → inserts a
`follow_requests` row. Duplicate POST = duplicate row IF the schema
is missing the UNIQUE constraint.

**Production fix:** `UNIQUE(follower_id, followee_id)` at the
Postgres schema level, enforced at commit time. Option B's role
here is the **test-side safety net** — catches the bug before CI
does, when a new handler ships against a fresh schema that doesn't
have the constraint yet.

**Option B coverage (ungated):** `.issueRecord` on the missing-
constraint bug shape. Passes after confirming `effectCount == 2`.

**Option B coverage (gated):** In-memory dedup keyed on the
`(follower, followee)` pair. Mirrors the real Postgres UNIQUE
constraint semantically; test runs in-process without a live DB.

**Refactor cost:** `FollowRequestRepository` protocol extraction
(~4 LOC). Zero cost on the dedup side if the production fix is a
schema constraint.

### 3. Avatar upload — ✅ caught, exercises R2 custom Snapshot

**Stand-in for:** `AvatarsController.update` → S3 PUT via SotoCore +
attachment DB row. Retry = duplicate S3 object + duplicate DB row.

**Why this shape exercises R2:** the bug is visible as both a count
delta AND a specific-keys-written delta. The default `Int` snapshot
catches the count; the custom `Snapshot = [String]` overload catches
the same bug AND surfaces the actual S3 keys in the failure
diagnostic:

```
baseline (pre-body):        []
after first invocation:     ["avatars/user-42/hash-of-524288-bytes.jpg"]
after second invocation:    ["avatars/user-42/hash-of-524288-bytes.jpg",
                             "avatars/user-42/hash-of-524288-bytes.jpg"]
```

Significantly more useful for "which upload duplicated" debugging
than a bare count delta.

**Option B coverage (ungated):** Default pathological ungated
handler — naive hash computation, no cache. `.issueRecord` fires
on the second invocation with the richer-snapshot diagnostic.

**Option B coverage (gated):** `IdempotencyKey(fromAuditedString:
"avatar-upload:\(userID):\(contentHash)")` + dedup cache. Real fix
options in production: S3 conditional PUT with `If-None-Match: *`
on the hash-derived key, DB-side `UNIQUE(content_hash)` on the
attachments table, or explicit dedup cache.

**Refactor cost:** `AvatarStorage` protocol extraction (~5 LOC) +
content-hash computation + dedup gate (~5 LOC).

## Cumulative v0.3.1 refinement exercise (across inbox + 3 bug-sweep shapes)

| Refinement | Exercised by | Result |
|---|---|---|
| **R1** — `failureMode: .issueRecord` | All 4 ungated-handler tests | Clean across 4 shapes. Diagnostics render correctly; `withKnownIssue` captures the per-suite issue. |
| **R2** — `Snapshot: Equatable = Int` default | Inbox + signup email + follow request (3 of 4 suites use default `Int`) | Clean. Where-clause extension fires automatically. |
| **R2** — custom `Snapshot` override | Avatar upload (`typealias Snapshot = [String]`) | Clean. Diagnostic surfaces actual S3 keys rather than integer count; type-erased comparison via `_snapshotBox()` SPI participates as designed. |
| **R3** — Protocol in main target | All 4 mocks | Clean. Every mock conforms to `IdempotentEffectRecorder` directly from `import SwiftIdempotency`; `SwiftIdempotencyTestSupport` only imported by the test file that calls `assertIdempotentEffects`. |

## Side-effect class coverage on Vernissage

| Class | Shape | Suite |
|---|---|---|
| In-process dedup on federated ID | ActivityPub inbox persistence | `OptionBActivityPubInboxTests` (prior trial) |
| External email send | Welcome email on signup | `OptionBSignupEmailTests` |
| DB row insertion | Follow request | `OptionBFollowRequestTests` |
| File storage (S3) | Avatar upload | `OptionBAvatarUploadTests` |

Four distinct adopter-realistic side-effect classes validated on a
single adopter under a single toolchain (Swift 6.3.1). Each maps
trivially to either `IdempotencyKey(fromAuditedString:)` (dedup gate
shape) or a Postgres UNIQUE constraint (schema-level dedup shape),
with Option B providing the test-side safety net in both cases.

## What this validates (extending the original inbox findings)

- **Option B generalizes across side-effect classes on a single
  adopter.** Email, DB, file storage — the API surface holds up
  without any shape-specific accommodations.
- **R2's custom Snapshot earns its keep on non-trivial shapes.**
  The avatar-upload diagnostic with actual S3 keys rendered is
  meaningfully more useful than a bare count delta.
- **Cross-adopter tally unchanged at 7 production adopters** (the
  bug-sweep is a depth extension on the existing Vernissage entry,
  not a new adopter).
- **Total Option B test count across all adopter trials:** 11 green
  (Penny 8 + Vernissage 9 = 17… wait, 8 + 9 = 17. Let me recount —
  Penny bug-sweep is 8 tests total (2 coin-double-grant regression
  baseline + 6 new bug-sweep), Vernissage is 9 (3 inbox + 6
  bug-sweep). Combined: 17 Option B tests against production
  adopter-shaped code passing on v0.3.1.)

## Follow-ups — parked candidates

- **Vernissage linter round.** Still open. Now even more interesting
  after the bug-sweep: the linter round can cross-reference the
  same four handler shapes to check whether SwiftProjectLint's
  existing Vapor whitelist + FluentKit whitelist + route-DSL
  whitelist cover VernissageServer cleanly at `@lint.context
  replayable`.
- **Vernissage hybrid trial.** One session that adds the
  `@lint.context replayable` banner AND annotates the four handlers
  we've already Option-B-tested. Cross-validates the two layers on
  the same code paths.

## Cross-references

- [`trial-scope.md`](trial-scope.md) — original inbox-probe scope.
- [`trial-findings.md`](trial-findings.md) — original inbox-probe
  findings. This doc extends that record.
- [`../release-notes/v0.3.1.md`](../release-notes/v0.3.1.md) — the
  pin relax that made the whole Vernissage trial chain possible.
- [`../penny-package-trial/bug-sweep-findings.md`](../penny-package-trial/bug-sweep-findings.md)
  — Penny's equivalent bug-sweep; different framework (Lambda vs.
  Vapor server) and different bug shapes, same API surface holds.
- [`Joseph-Cursio/VernissageServer-idempotency-trial@3d97ef8`](https://github.com/Joseph-Cursio/VernissageServer-idempotency-trial/tree/bug-sweep)
  — the bug-sweep branch on the Vernissage fork.
