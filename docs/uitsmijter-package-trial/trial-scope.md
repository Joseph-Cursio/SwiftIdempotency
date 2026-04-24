# Uitsmijter — Package Integration Trial Scope

Fresh-external-signal Option B probe. Fourth consecutive clean-slate
external adopter (post-Vernissage, plc-handle-tracker,
HomeAutomation). First OAuth2 authorization-server target; first
**RFC-spec-mandated** single-use shape.

**Selection criterion note.** Per the 2026-04-24 retired phase-2
heuristic, this adopter was selected for domain/shape novelty, not
obscurity. Uitsmijter is 9⭐ single-contributor but also has
**Kubernetes + Traefik + OAuth2 + JWT + swiftkube/client +
SwiftPrometheus + Soto + JXKit scripting** — an unusually rich
dep stack that extends cross-framework coverage meaningfully.

## Research question

> Does the v0.3.1 Option B surface model the **spec-mandated**
> OAuth2 single-use semantics cleanly? Unlike prior trials where
> idempotency was a best-practice or app-specific concern, OAuth2
> RFC 6749 §4.1.2 explicitly requires the authorization server
> to enforce single-use on authorization codes. An implementation
> without a gate ships a CVE-shaped bug, not a usability issue.

## Why Uitsmijter specifically

- **Novel domain.** First OAuth2 authorization-server target; prior
  9 trials covered HTTP handlers, Lambda handlers, vapor/queues
  AsyncJobs, ActivityPub inbox, PLC import, APNs delivery, and
  HomeKit events. OAuth2 code redemption is a new side-effect
  class (JWT issuance + refresh-token persistence + Kubernetes
  CRD status update + Prometheus metric emission per redemption).
- **Novel stack.** First adopter using:
  - `swiftkube/client` (0.15.0) — Kubernetes API client, used for
    Traefik middleware config + CRD status updates
  - SwiftPrometheus — metrics emission
  - JWT 5.0 + swift-crypto — token signing
  - JXKit — JavaScript scripting engine for user-defined rules
  - Redis as the primary session store (prior Redis adopters used
    it as a cache only)
  - Soto — AWS SDK (used for key management)
- **Spec-mandated shape.** RFC 6749 §4.1.2 is unambiguous:
  "The client MUST NOT use the authorization code more than
  once." The server enforces this by invalidating the code on
  first redemption. An adopter whose token handler isn't
  idempotent on `code` ships a replay-attack vulnerability — this
  is the strongest motivation for Option B framing of any trial.
- **Adopter already has the right shape.** The real
  `authorisationTokenGrantTypeRequestHandler` in
  `Sources/Uitsmijter-AuthServer/Controllers/TokenController+TokenGrantTypeRequestHandler.swift:106-156`
  uses `authCodeStorage.get(type: .code, codeValue: code, remove: true)`
  — atomic retrieve-and-delete on the storage actor. This is the
  correct pattern; the trial validates it at the test level and
  shows what would break if the atomicity were lost.
- **Swift tools 6.2** — fourth distinct toolchain floor now
  validated across Option B adopters (6.0 plc-handle-tracker,
  6.2 Vernissage + HomeAutomation + Uitsmijter, 6.3 Penny).
- **Git-LFS adoption gotcha.** Repo uses LFS for Graphics,
  Fonts, and e2e-test snapshots. Clone requires
  `GIT_LFS_SKIP_SMUDGE=1` followed by `git checkout HEAD -- .`
  (after `git-lfs install`) to get a clean working tree; Swift
  sources are not LFS-tracked, so this doesn't affect the probe.
  First trial surfacing an LFS-related clone friction — worth
  documenting for future LFS-adopting targets.

## Pinned context

- **SwiftIdempotency tip:** tag `0.3.1`.
- **Upstream target:** `uitsmijter/Uitsmijter@8317133`
  (main tip at trial time, 2026-04-24).
- **Trial fork:** `Joseph-Cursio/Uitsmijter-idempotency-trial`
  (hardened: issues/wiki/projects disabled, sandbox description).
  Default branch switched to `package-integration-trial`.
- **Trial branch:** `package-integration-trial`.
- **Toolchain:** Swift 6.3.1 / macOS 26 / arm64.
- **Baseline build:** verified green (168.4s cold build on 6.3.1).
  `swift-crypto` + `swiftkube/client@0.15.0` + `JXKit` (branch:main)
  + `soto@6.0.0` + `SwiftPrometheus` all resolve transitively
  with SwiftIdempotency's swift-syntax requirement.

## Probe target

`authorisationTokenGrantTypeRequestHandler` at
`Sources/Uitsmijter-AuthServer/Controllers/TokenController+TokenGrantTypeRequestHandler.swift:106-156`.
Shape:

```swift
private func authorisationTokenGrantTypeRequestHandler(
    for tenant: Tenant,
    on req: Request
) async throws -> TokenResponse {
    let request = try req.content.decode(CodeTokenRequest.self)

    guard let authCodeStorage = req.application.authCodeStorage else {
        throw Abort(.insufficientStorage, reason: "ERRORS.CODE_STORAGE_AVAILABILITY")
    }

    // SPEC-MANDATED single-use: atomic retrieve-and-delete on actor.
    guard let session = await authCodeStorage.get(
        type: AuthSessionType.code,
        codeValue: request.code,
        remove: true
    ) else {
        throw Abort(.forbidden, reason: "ERRORS.INVALID_CODE")
    }

    // ... tenant check ...

    let (accessToken, refreshToken) = try await getNewTokenPair(
        on: req, tenant: tenant, session: session, scopes: scopes
    )
    return TokenResponse(...)
}
```

And `getNewTokenPair` at the same file:412-460 — the side-effect
bundle per redemption:

1. **Refresh session stored** in AuthCodeStorage (Redis write).
2. **Access token JWT signed** via `signerManager` (crypto + Prometheus `oauthToken` metric increment).
3. **Kubernetes CRD status update** triggered via
   `entityLoader.triggerStatusUpdate(for: tenantName, client:)` —
   the swiftkube/client side effect.
4. **Prometheus `oauthFailure` metric NOT incremented** (success path).

Per redemption, 4 distinct observable side effects. Retry on a
naive (non-atomic-remove) handler would double ALL of them — rich
surface for the `IdempotentEffectRecorder`.

## Option B probe design

Four tests (adding one beyond the standard three-test pattern
because the spec-mandated framing warrants a "the spec matters"
variant):

1. **Ungated redemption + `.issueRecord`.** Non-atomic `get` + `delete`
   pattern (hypothetical). Replay fans out duplicate effects across
   all 4 side-effect classes. `.issueRecord` captures the snapshot
   drift 0 → 4 → 8.
2. **Atomic-gate (spec-compliant) redemption.** The adopter's
   actual `get(remove: true)` pattern. Replay's `get` returns nil,
   handler throws `ERRORS.INVALID_CODE`. Second invocation
   short-circuits before any token-issuing code path. `effectCount
   == 4` across the whole two-run body (4 effects from the first
   redemption; second redemption threw before any effect).
3. **Application-level `IdempotencyKey` gate.** Alternative to
   the storage-atomic approach — wrap the handler body in
   `IdempotencyKey(fromAuditedString: "oauth-code:\(code)")` +
   dedup cache. Demonstrates the surface works regardless of
   whether the adopter's gate is at the storage layer (Uitsmijter's
   current design) or the application layer (what an adopter
   coming from a different architecture might use).
4. **Distinct-codes sanity.** Two distinct authorization codes,
   each redeemed once across a two-run body. Validates dedup
   doesn't collide across unrelated codes.

## Migration plan (test-target-only)

**No Uitsmijter source files modified.** The trial declares a
test-local `AuthCodeStorageShape` protocol (minimally mirroring
`AuthCodeStorageProtocol` from the `Uitsmijter-AuthServer`
internal module — the real protocol is `internal`, not `public`,
so the trial can't import it directly; structural mirror only).

The refactor cost for a real adopter is essentially **zero** —
the shape already exists. The trial's value is test-level
assertion of the existing implementation's correctness.

## Pre-flight: system-library dependencies

**Git LFS** required for the initial clone (see §"Why Uitsmijter"
above). No C-library system deps beyond what the production
deployment already needs (Redis server runtime, not build-time).

## Pre-committed questions

1. **Does v0.3.1 compile cleanly on Uitsmijter's dep graph?**
   First adopter with swiftkube/client + SwiftPrometheus + JXKit
   + Soto. Any could conflict.
2. **Does `.issueRecord` fire on the non-atomic redemption
   shape?** R1 validation on a new adopter.
3. **Does the atomic-gate path pass `assertIdempotentEffects`
   on a multi-effect-per-invocation body?** 4 distinct
   side-effect classes per redemption — tests that
   `IdempotentEffectRecorder` handles heterogeneous effect
   tracking cleanly.
4. **What's the refactor cost for real adoption?**
   Approximately **zero**: the adopter's existing `remove: true`
   pattern already gives Option B's guarantees. The trial
   validates rather than introduces.

## Scope commitment

- **Test-target-only.** No Uitsmijter source files modified.
- **No upstream PR.** Non-contribution fork convention preserved.
- **Spec-mandated framing explicit.** Unlike prior trials where
  idempotency was best-practice, this one is spec-mandated.
  Trial-findings doc calls out the RFC 6749 §4.1.2 connection.

## Predicted outcome

- **Q1 (compile):** ✅ expected. JXKit branch pin is the
  speculative dep; baseline cleared green.
- **Q2 (`.issueRecord` fires):** ✅ expected.
- **Q3 (atomic-gate passes on multi-effect body):** ✅ expected.
  Prior HomeAutomation trial already validated multi-effect
  body shape.
- **Q4 (refactor cost):** **~0 LOC** — lowest of any trial.
  Adopter's code is already correct; the trial is a test-level
  assertion.

## What this trial decides

**Validates v0.3.1 externally on a fourth consecutive fresh
adopter**, on a **spec-mandated single-use shape** (first such
framing), on a **Kubernetes-integrated stack** (first
swiftkube/client adopter). Cross-adopter tally 9 → 10 production
adopters. **Four consecutive zero-friction rounds is now a
superset of the 3/3 plateau bar** → surface demonstrably stable
under rigorous probing.

## Scope boundaries — NOT in this trial

- **Other Uitsmijter Option B shapes** (device authorization
  grant per RFC 8628, refresh-token rotation,
  client-credentials grant, login-session storage). Future
  bug-sweep variant if warranted.
- **Validation against production PKCE semantics** — Uitsmijter
  supports PKCE but trial doesn't exercise the code_verifier
  round trip.
- **Kubernetes CRD status-update path exercised end-to-end** —
  mocked, not validated against a real swiftkube/client call.
- **Linter trial.** Macro-surface validation only.
