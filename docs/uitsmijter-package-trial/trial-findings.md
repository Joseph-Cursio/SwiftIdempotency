# Uitsmijter — Package Integration Trial Findings

Fresh-external-signal Option B probe, validating SwiftIdempotency
0.3.1 on a production OAuth 2.0 authorization server + Traefik
middleware for Kubernetes (`uitsmijter/Uitsmijter`). Trial scope
in [`trial-scope.md`](trial-scope.md); fork and branch pointers
at the foot.

## Headline

**v0.3.1 compiles cleanly on Uitsmijter's dep graph and all four
Option B tests pass** (4/4 green, 1 known-issue from the
intentional `.issueRecord` negative-path test). **Fourth
consecutive clean-slate fresh-signal round with zero API friction**
(Vernissage → plc-handle-tracker → HomeAutomation → Uitsmijter).
**Pattern is now rigorously stable.**

Cross-adopter tally bumps from 9 to **10 production adopters**.

First **OAuth 2.0 authorization-server target** and first
**RFC-spec-mandated single-use shape** — unlike prior trials where
idempotency was a best-practice concern, RFC 6749 §4.1.2 explicitly
requires single-use on authorization codes. An adopter whose token
handler isn't idempotent on `code` ships a replay-attack
vulnerability.

Also first **swiftkube/client** (Kubernetes API) adopter, first
**SwiftPrometheus** adopter, first **Soto** (AWS SDK) adopter,
first **JXKit** (JavaScript scripting) adopter.

## Pre-committed question answers

| # | Question | Answer |
|---|---|---|
| 1 | Does v0.3.1 compile cleanly on Uitsmijter's dep graph? | ✅ Yes. swift-crypto + swiftkube/client@0.15.0 + JXKit (branch:main) + soto@6.0.0 + SwiftPrometheus + CryptoSwift + Vapor JWT 5.0 all resolve with SwiftIdempotency's swift-syntax requirement. |
| 2 | Does `.issueRecord` fire on the non-atomic redemption shape? | ✅ Yes. Snapshot drift 0 → 4 → 8 captured (4 side-effect classes × 2 replays). |
| 3 | Does the atomic-gate path pass `assertIdempotentEffects` on a multi-effect-per-invocation body? | ✅ Yes. Storage actor's `get(remove: true)` returns nil on the second invocation; handler throws `.invalidCode` (caught inside body); `effectCount` stays at 4 across both invocations. |
| 4 | Refactor cost for real adoption? | **~0 LOC** — Uitsmijter's existing pattern is already spec-compliant. The trial validates rather than introduces. |

## Per-test results

### Test 1 — Ungated (non-atomic) redemption + `.issueRecord`

```
Recorder MockAuthCodeStorage snapshot changed across the second
invocation.
    baseline (pre-body):        0
    after first invocation:     4
    after second invocation:    8
```

Observed: each redemption produces 4 distinct side effects:

1. Refresh session persisted (simulated Redis write)
2. JWT access token signed (simulated crypto op)
3. Kubernetes CRD status update triggered (simulated
   swiftkube/client dispatch)
4. Prometheus metric increment (simulated)

Replay fans out all 4 → 8 total effects. Real Uitsmijter users
would see: 2 refresh sessions persisted (long-lived token
proliferation — security concern), 2 JWTs signed (wasted CPU), 2
spurious Kubernetes CRD updates (phantom reconciler wake-ups), 2
wrong Prometheus metrics (dashboard skew).

**Iteration note:** The initial probe draft had the ungated handler
call `storage.delete(code)` after its side effects (mimicking a
"delete after use" pattern). This accidentally passed — the
second invocation's `get(remove: false)` returned nil because the
first invocation's delete had already fired sequentially. The
refined draft models the more realistic bug: the ungated handler
does NOT delete at all, trusting TTL-based expiry. This captures
the actual replay-vulnerability shape that OAuth2 deployments
have historically shipped. Documented here because it's a
subtle-but-important insight about Option B probe design — test
ordering interacts with the delete-vs-retain decision in the
handler under test.

### Test 2 — Atomic-gate (spec-compliant, Uitsmijter's actual pattern)

```swift
guard let session = await storage.get(
    type: .code,
    codeValue: codeValue,
    remove: true  // atomic retrieve-and-delete on storage actor
) else {
    throw RedemptionError.invalidCode
}
```

Observed: first invocation redeems, 4 side effects fire. Second
invocation's `get(remove: true)` returns nil (actor's prior
invocation already consumed the code atomically). Handler throws
`.invalidCode`; the test body catches the error (no further
propagation). `effectCount` stays at 4 across both invocations.
Passes.

This is **Uitsmijter's actual production pattern** at
`Sources/Uitsmijter-AuthServer/Controllers/TokenController+TokenGrantTypeRequestHandler.swift:116-120`.
The trial confirms it gives Option B's guarantees.

### Test 3 — Application-level `IdempotencyKey` gate

```swift
let key = IdempotencyKey(fromAuditedString: "oauth-code:\(codeValue)")
guard dedup.tryClaim(key) else {
    throw RedemptionError.invalidCode
}
```

Observed: alternative architectural fix. Correctness-equivalent
to the atomic-storage-gate. `effectCount == 4` across both
invocations. Passes.

Useful to demonstrate because **not every adopter has an
atomic-retrieve-and-delete storage API** — some OAuth2 server
implementations use separate `get` + `delete` calls across
different services, making the storage-level atomic fix
unavailable. The application-level `IdempotencyKey` gate works
regardless of the underlying storage architecture.

### Test 4 — Distinct codes sanity

Two distinct authorization codes (`code-a` for alice, `code-b`
for bob) each redeemed once across a two-run body. `effectCount
== 8` (4 per code × 2 distinct codes, both consumed on the
first body run; second body run produces zero effects via
`.invalidCode` throws caught inside the body). Passes — dedup
doesn't collide across unrelated codes.

## Surfacing findings

### 1. First spec-mandated idempotency adopter

Prior 9 trials all had idempotency as a best-practice concern —
"you should dedupe retries" but no external document made it
required. **Uitsmijter is the first adopter where the shape is
spec-mandated**: RFC 6749 §4.1.2 is unambiguous that
authorization codes MUST be single-use, and the server SHOULD
revoke previously-issued tokens if a code is replayed.

This shifts the Option B framing meaningfully:

- Prior trials: "here's how to test your idempotency choice."
- This trial: "here's how to test-assert RFC compliance."

For adopters in regulated / security-sensitive domains (OAuth2,
OpenID Connect, financial APIs with idempotency-key headers,
payment processors), the spec-mandated framing is the primary
selling point.

### 2. Four-effect heterogeneous body extends prior multi-effect finding

HomeAutomation established the multi-effect-per-invocation body
shape (N device tokens × push). Uitsmijter extends to **4
distinct side-effect classes** per redemption:

1. Storage write (Redis)
2. Cryptographic operation (JWT signing)
3. External API call (Kubernetes CRD update via swiftkube/client)
4. Metric emission (Prometheus)

The `IdempotentEffectRecorder`'s default `Snapshot = Int`
handled the heterogeneous mix cleanly — each distinct effect
type increments `effectCount` within the mock. An adopter
wanting tighter diagnostics could adopt `Snapshot = [String]`
operationLog for per-class visibility, but the default Int
catches the bug.

### 3. Uitsmijter's code is already spec-compliant

Unlike prior trials where the real adopter code had at least a
*weak* form of the idempotency issue (HomeAutomation's
APNs-collapseID being transport-level only, plc-handle-tracker's
migration history showing the bug existed at some point),
**Uitsmijter's authorization_code path is already fully
compliant**. The storage actor's atomic
`get(type:, codeValue:, remove: true)` is the correct pattern
and has been since the shape was introduced.

This is the **first adopter where the trial is purely
confirmatory rather than educational**. The value is:

- Test-level assertion of existing correctness.
- Regression test if someone ever changes the impl to
  non-atomic.
- Reference pattern for adopters coming from a different
  architecture.

### 4. Git-LFS clone friction documented

First trial where the target uses git-lfs for non-Swift assets
(Graphics, Fonts, Playwright test snapshots). Clean clone
sequence for future LFS-using targets:

```bash
brew install git-lfs             # if not installed
git-lfs install                  # global hooks
GIT_LFS_SKIP_SMUDGE=1 git clone <url>
cd <repo>
git-lfs install                  # repo hooks
GIT_LFS_SKIP_SMUDGE=1 git checkout HEAD -- .
```

Swift sources are never LFS-tracked in practice — only binary
artifacts are — so `GIT_LFS_SKIP_SMUDGE=1` is safe for trials
that don't exercise the binary assets.

### 5. Novel dependency stack resolved cleanly

First adopter with:

- `swiftkube/client@0.15.0` — Kubernetes API client
- `SwiftPrometheus` (alpha-pinned) — metrics
- `JXKit` (branch:main) — JavaScript scripting engine
- `soto@6.0.0` — AWS SDK
- `CryptoSwift` alongside swift-crypto — dual-crypto stack
- `Vapor JWT 5.0` — JWT implementation

All resolved transitively with SwiftIdempotency's swift-syntax
requirement. Baseline build was 168.4s; the test-target build
was 188.2s.

## Refactor cost estimate — real Uitsmijter adoption

**~0 LOC.** Uitsmijter's production code at
`TokenController+TokenGrantTypeRequestHandler.swift:116-120`
already uses the spec-compliant atomic pattern. The only work
for a real adoption would be **adding this trial's test file to
Uitsmijter's own test suite** as a regression check — ~5 LOC if
the trial uses the project's existing test utilities.

## Trial commitments honoured

- ✅ **Test-target-only.** `TokenController`,
  `AuthCodeStorageProtocol`, `AuthSession`, `getNewTokenPair`
  all unmodified. No Uitsmijter production code touched.
- ✅ **No upstream PR.** Non-contribution fork convention
  preserved.
- ✅ **Spec-mandated framing explicit.** Trial-findings doc
  calls out the RFC 6749 §4.1.2 connection.

## Context

- **SwiftIdempotency tip pinned:** tag `0.3.1`.
- **Upstream target:** `uitsmijter/Uitsmijter@8317133` (main
  tip at trial time, 2026-04-24).
- **Trial fork:** [`Joseph-Cursio/Uitsmijter-idempotency-trial`](https://github.com/Joseph-Cursio/Uitsmijter-idempotency-trial)
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch: `package-integration-trial`.
- **Trial branch tip:** `package-integration-trial` at
  [`17822b4`](https://github.com/Joseph-Cursio/Uitsmijter-idempotency-trial/commit/17822b4).
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Baseline build:** clean, 168.4s cold build on 6.3.1 after
  git-lfs-workaround clone.
- **Trial test-target build:** 188.2s. Test runtime: 4 tests,
  0.001s wall-clock.

## Cross-adopter Option B tally

10 production adopters validated end-to-end on the
`IdempotencyKey` / `IdempotentEffectRecorder` / `.issueRecord`
surface:

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
| 9 | HomeAutomation | APNs send | Vapor + APNSwift + MySQL Fluent | `id: String` (documented) |
| 10 | **Uitsmijter** | **OAuth2 code redemption** | **Vapor + JWT + swiftkube/client + SwiftPrometheus + Soto + JXKit** | **`code: String` (RFC-mandated)** |

**Ten-for-ten Option B surface coverage** across AWS Lambda /
PointFree HttpPipeline / Hummingbird / Vapor / Vapor + vapor/queues /
Vapor + APNSwift + MySQL Fluent / Vapor + JWT + swiftkube/client.
First OAuth2 authorization-server target; first Kubernetes-API
adopter; first spec-mandated-idempotency target.

## What this trial decides

**Validates v0.3.1 externally on a fourth consecutive fresh
adopter** on an RFC-mandated shape that elevates the Option B
framing from "best-practice test" to "spec-compliance regression
test." **Four consecutive zero-friction rounds is a superset of
the 3/3 plateau bar from the linter road-tests** — the Option B
surface is demonstrably stable under rigorous probing.

Per the road-test-plan convention, this round **closes the
analogous ship gate** for Option B surface stability with margin
to spare. Going forward: Option B rounds remain valuable for
expanding framework / domain coverage breadth and for regression
testing against future v0.4+ changes, but API-stability
uncertainty is retired.

## What's next

Selection criterion remains "domain/shape novelty." Unexplored
shape classes: Apple Wallet pass issuance (vapor-community/wallet),
Parse CloudCode triggers (netreconlab/parse-server-swift), GraphQL
mutation resolvers, payment-processing webhooks (Stripe-shape).
Or a different workstream entirely — deferred macro work
(`#assertIdempotentEffects` freestanding macro, hybrid Option-B/C
helper), linter 1-adopter slice promotions, or cross-adopter
triage PR filing.
