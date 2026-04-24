# Penny Bug-Sweep Trial — Findings

Follow-up to the initial Penny package-integration trial (see
[`trial-findings.md`](trial-findings.md)), exercising the remaining
three Penny bug shapes under the **shipped v0.3.1 Option B surface**
rather than the prototype. Dual-purpose: validates v0.3.0/0.3.1
externally AND confirms the API generalizes past the one shape the
first trial covered.

## Trial tips

- **SwiftIdempotency:** tag `0.3.1` (not the prototype SHA). First
  external adopter to pin the shipped Option B.
- **Trial fork branch:** `bug-sweep` at
  [`Joseph-Cursio/penny-bot-idempotency-trial@aa24cf9`](https://github.com/Joseph-Cursio/penny-bot-idempotency-trial/tree/bug-sweep).
  Forked from `package-integration-trial@c121ced`; the prior coin-
  double-grant test is preserved intact as a regression baseline.
- **Upstream target:** `vapor/penny-bot@e0d2752` (same as the
  first trial).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.

## Research question

> Does the shipped Option B API (`IdempotentEffectRecorder` +
> `assertIdempotentEffects` as of v0.3.1) catch the remaining three
> Penny bug shapes (OAuth error-path, sponsor welcome DM, GHHooks
> error-path notification dup), and does the three-refinement surface
> (R1 `failureMode`, R2 `Snapshot` associatedtype, R3 protocol-in-main-
> target) hold up on adopter-realistic code?

## Headline

**Yes.** 8/8 tests green in 4 suites (existing coin-double-grant ×2 +
three new suites ×2 each = 6 new). 3 known issues as designed (one
per `.issueRecord` negative-path test). All three v0.3.1 refinements
exercised in realistic Penny-shaped code; no API friction surfaced.

**Cross-adopter tally**: the four Penny bug shapes (coin double-
grant + three in this round) join the six shapes from isowords,
prospero, myfavquotes-api, and hellovapor — **10-for-10 real-bug
shapes across six production adopters** all map cleanly to either
`IdempotencyKey` / `@ExternallyIdempotent(by:)` (handler surface) or
`IdempotentEffectRecorder` / `assertIdempotentEffects` (test surface).

## Surfacing finding — swift-syntax pin friction → v0.3.1

The trial's primary finding wasn't an Option B API issue; it was a
**dep-graph constraint**. The v0.3.0 `Package.swift` pinned
`swift-syntax` at `exact: "602.0.0"`. Penny's DiscordBM transitively
requires `swift-syntax 603+` because its `@UnstableEnum` macro only
expands correctly there. SwiftPM honors the `exact` constraint and
downgrades the whole graph to 602, breaking DiscordBM at compile
time.

The prior coin-double-grant trial passed only because its
Package.resolved was committed while swift-syntax was still at 603 —
the `exact` constraint had never been actively re-resolved on that
branch. Bumping the pin from the prototype SHA to the 0.3.0 tag
triggered a clean re-resolve and surfaced the issue.

**Fix landed as v0.3.1** (same session): `exact: "602.0.0"` →
`"602.0.0"..<"604.0.0"`. Verified SwiftIdempotency's 74-test suite
passes under both swift-syntax 602.0.0 and 603.0.0 before release.
See [`../release-notes/v0.3.1.md`](../release-notes/v0.3.1.md).

Takeaway for future adopter trials: **any exact-pinned transitive
dep is adopter friction in disguise**. Prefer ranges (or `from:`)
over `exact:` unless there's a compile-time API-surface reason for
tight pinning.

## Per-shape results

### 1. OAuth error-path (slot: 2-of-4 bug shapes) — ✅ caught

**Real Penny site:** `OAuthLambda.{logErrorToDiscord, failure}` —
seven call sites across failure branches, each posts to Discord
botLogs on OAuth-exchange errors. Lambda's at-least-once invocation
semantics + error-path retry = duplicate error posts.

**Option B coverage (ungated):** `.issueRecord` failureMode with
default `Snapshot == Int` catches the bug without aborting the test
process. Observed: recorder `effectCount` goes 0 → 1 → 2; diagnostic
surfaces in Swift Testing's test output. Snapshot comparison is
type-erased via `_snapshotBox()` SPI — works with zero adopter-side
friction.

**Option B coverage (gated):** `IdempotencyKey(fromAuditedString:
"oauth-failure:\(code)")` + in-memory dedup cache. First invocation
claims the key, second short-circuits. `effectCount == 1` after
both invocations; `assertIdempotentEffects` passes cleanly.

**Refactor cost:** single `DiscordErrorLogger` protocol extraction
(~5 LOC adopter-side) + a per-call dedup-cache lookup at the top of
each of the 7 failure-branch call sites. Alternative: refactor to
route all failure-branch posts through a single keyed helper.

### 2. Sponsor welcome DM (slot: 3-of-4 bug shapes) — ✅ caught

**Real Penny site:** `SponsorsLambda.sendMessage` from the
GitHub-sponsorship webhook handler. GitHub webhook redelivery
(retry policy: up to 24h on 5xx/timeout) fires the welcome DM every
time → sponsor spam.

**Option B coverage (ungated):** same shape as OAuth. `.issueRecord`
fires on the second invocation; recorder observes two identical DMs
to the same recipient.

**Option B coverage (gated):** `IdempotencyKey(fromAuditedString:
"sponsor-welcome:\(delivery)")` where `delivery` is the
`x-github-delivery` header. GitHub guarantees header stability across
redeliveries → canonical dedup token for webhook-triggered effects.

**Refactor cost:** `DirectMessageSender` protocol extraction + one
`if-let delivery = headers[...]` guard at the top of the sponsor
handler. Minimal.

### 3. GHHooks error-path (slot: 4-of-4 bug shapes) — ✅ caught, exercises R2

**Real Penny site:** `GHHooksHandler.handle`'s `catch` branch around
the top-level `handleThrowing(_:)` call. Errors post to Discord
botLogs; on webhook redelivery, maintainers get duplicate error
notifications.

**Exercises R2 (custom `Snapshot` type):** this test uses
`typealias Snapshot = [String]` on the recorder — an ordered call
log of post bodies rather than the default `Int`. Demonstrates that
the richer-snapshot overload works end-to-end on adopter code:
diagnostic messages surface the actual post bodies, so a failure
like "handler posted the same message twice" is visible in the test
output rather than just "count went from 1 to 2."

Observed diagnostic excerpt from the .issueRecord test:

```
baseline (pre-body):        []
after first invocation:     ["gh-webhook failed: missingSignature"]
after second invocation:    ["gh-webhook failed: missingSignature",
                             "gh-webhook failed: missingSignature"]
```

**Option B coverage (gated):** same `x-github-delivery` shape as the
sponsor DM. Dedup-gate at handler entry → second invocation
short-circuits before the do/catch runs → `bodies` stays at one
element across both invocations → snapshot comparison passes.

**Refactor cost:** `BotLogsPoster` protocol extraction + same
delivery-header guard. The error-path itself isn't rewritten; the
dedup gate wraps it.

## Cumulative v0.3.1 refinement exercise

| Refinement | Exercised by | Result |
|---|---|---|
| **R1** — `failureMode: .issueRecord` | All 3 new ungated-handler tests | Clean. `Issue.record` fires + `withKnownIssue` captures + test process continues to verify `effectCount`/`bodies` post-run. |
| **R2** — `Snapshot: Equatable = Int` default + override | Custom `[String]` on `CallLogBotLogsPoster`; default `Int` on the other two mocks | Clean. Where-clause default fires automatically when no typealias declared; custom typealias participates in type-erased comparison via SPI helper. |
| **R3** — Protocol in main target | All 3 mocks conform to `IdempotentEffectRecorder` directly from `SwiftIdempotency` import | Clean. No `SwiftIdempotencyTestSupport` import needed for the mock declarations; only the test file that calls `assertIdempotentEffects` imports TestSupport. |

## Pre-committed question answers

1. **Does the shipped Option B API surface compile on Penny's test
   target?** ✅ **Yes, after v0.3.1.** The prototype SHA compiled
   (Package.resolved had a stale 603 pin); the 0.3.0 tag did not
   (clean re-resolve). v0.3.1 compiles cleanly.
2. **Does each bug shape's Option B detection fire?** ✅ **Yes.**
   All 3 ungated-handler tests fire their expected `Issue.record`
   via `withKnownIssue`. Effect-count/snapshot deltas match
   predictions.
3. **Does each bug shape's dedup-gated happy path pass?** ✅
   **Yes.** All 3 gated-handler tests call `assertIdempotentEffects`
   without a recorded issue; recorder state confirms one effect, not
   two.
4. **Any API friction from the three refinements?** ❌ **None
   surfaced.** The custom `Snapshot` typealias worked without
   incident; `.issueRecord` + `withKnownIssue` integrated cleanly; no
   TestSupport dep was needed for the recorder mocks.

## What this validates

- **v0.3.1 is externally shippable** — confirmed on Penny's heavy
  dep graph (DiscordBM + Soto + OpenAPI + FluentKit + NIO).
- **Option B generalizes past coin-double-grant.** Three distinct
  Penny bug shapes — OAuth 7-call-site failure-path duplication,
  sponsor webhook redelivery, GHHooks error-path notification
  duplication — all map to the same protocol+helper pair with
  different dedup-key sources (OAuth code, x-github-delivery
  header).
- **The three refinements earn their keep** on adopter-shaped code:
  `.issueRecord` lets failure-path tests run without aborting; the
  `Snapshot` overload makes diagnostic messages useful for richer
  mock state; the protocol-in-main-target move means the mock
  classes don't need a test-support import.

## Not exercised

- **Full Penny refactor** — the trial measures refactor cost; the
  actual protocol extractions on `OAuthLambda`, `SponsorsLambda`,
  `GHHooksHandler` remain adopter work.
- **No upstream PR** — non-contribution fork per the established
  convention.
- **Linter re-run** — this trial is macro-surface validation; the
  linter side (round 6 originals) stands pat.

## Cross-references

- [`../release-notes/v0.3.1.md`](../release-notes/v0.3.1.md) — the
  pin-friction fix that this trial surfaced.
- [`trial-findings.md`](trial-findings.md) — the original Penny
  package trial (coin-double-grant only).
- [`../penny-bot/trial-findings.md`](../penny-bot/trial-findings.md)
  — the linter round 6 Penny trial where the four bug shapes were
  first catalogued.
- [`Joseph-Cursio/penny-bot-idempotency-trial@aa24cf9`](https://github.com/Joseph-Cursio/penny-bot-idempotency-trial/tree/bug-sweep)
  — the trial branch on the Penny fork.
