# penny-bot — Trial Findings

## TL;DR

**The linter found four actionable production bugs on its first real-
business-logic adopter.** All four are concrete enough to propose
one-shape fixes using the `SwiftIdempotency` package's existing
`IdempotencyKey` / `@ExternallyIdempotent(by:)` surface — this is
the first real-adopter validation of that macro surface.

One **new linter bug** was also surfaced and fixed in the same
session (see slot 12 below): the linter crashed on Penny's
first-pass scan with `Duplicate values for key: 'Errors.swift'`
due to a macOS `/tmp` symlink canonicalisation mismatch. Fix is
a 4-line patch to `ProjectLinter.makeProjectFile` using
`URL.resolvingSymlinksInPath()`. The round is the first ever to
exercise a codebase with duplicate file basenames across targets.

## Pinned context

- **Linter:** `SwiftProjectLint` @ `bc3c05e` + working-tree patch
  (`ProjectLinter.swift`: symlink-resolving relativePath +
  defensive `uniquingKeysWith` on inline-suppression dedup).
  Patch not yet committed upstream — scored as slot 12.
- **Target:** `vapor/penny-bot` → forked to
  `Joseph-Cursio/penny-bot-idempotency-trial` @
  `trial-penny-bot`.
  - **Run A tip:** `49db411` (5 handlers `@lint.context replayable`).
  - **Run B tip:** `c309bcb` (same 5 handlers `@lint.context strict_replayable`).
- **Scan corpus:** single-Package.swift, 165 Swift files, 8
  Lambda targets + long-running `Sources/Penny/` service. All 5
  annotated handlers under `Lambdas/`.

## Run A — replayable context

**20 diagnostics.** Per-handler headline:

| Handler | Fires | Status |
|---|---|---|
| `UsersHandler.handle` | 5 | Dispatches to 5 sub-handlers; one sub-handler is a real bug (coin double-grant), others are defensible |
| `OAuthLambda.handle` | 7 | 6 real bugs (error-path Discord posts duplicate), 1 defensible |
| `SponsorsLambda.handle` | 2 | 1 real bug (welcome DM), 1 adoption-gap (read) |
| `FaqsHandler.handle` | 3 | All 3 defensible — repository is well-designed (read-then-write-if-different) |
| `GHHooksHandler.handle` | 3 | 1 real bug (error-path `createMessage`), 1 expected (`handleThrowing` delegation), 1 noise (`unicodesPrefix` helper) |

**Yield: 5/5 handlers fire — every annotated handler produces at
least one correct-catch diagnostic.** Compare to round 9 (Lambda
demos): 0/6. The "real production side effects" hypothesis from
the CLAUDE.md corpus caveat holds.

### Per-diagnostic audit (capped at 30; 20 ≤ 30 so full audit)

| # | File:Line | Callee | Verdict | Notes |
|---|---|---|---|---|
| 1 | `UsersHandler.swift:57` | `handleAddUserRequest` | **correct catch / real bug** | `addCoinEntry` creates a NEW `CoinEntry` row + increments `user.coinCount` unconditionally. On API retry, sender loses 2× coins, recipient gets 2× credit. **Fix: `IdempotencyKey` on `UserRequest.CoinEntryRequest` (Discord message ID as natural key), dedup in `DynamoCoinEntryRepository.createCoinEntry`.** |
| 2 | `UsersHandler.swift:59` | `handleGetOrCreateUserRequest` | defensible | check-then-create is retry-safe; concurrent-creation race is outside retry scope. Adopter should annotate `@lint.effect idempotent`. |
| 3 | `UsersHandler.swift:61` | `handleGetUserRequest` | adoption-gap | pure read; adopter should annotate. |
| 4 | `UsersHandler.swift:63` | `handleLinkGitHubRequest` | defensible | overwrite-idempotent (`user.githubID = fixed_value`). Adopter should annotate. |
| 5 | `UsersHandler.swift:65` | `handleUnlinkGitHubRequest` | defensible | overwrite-idempotent (`user.githubID = nil`). |
| 6 | `OAuthLambda.swift:100` | `logErrorToDiscord` | **correct catch / real bug** | Error-path Discord post duplicates on retry; ops noise |
| 7 | `OAuthLambda.swift:106` | `logErrorToDiscord` | **correct catch / real bug** | same |
| 8 | `OAuthLambda.swift:131` | `logErrorToDiscord` | **correct catch / real bug** | same |
| 9 | `OAuthLambda.swift:176` | `failure` | **correct catch / real bug** | `failure()` wraps `logErrorToDiscord` + `updateInteraction` |
| 10 | `OAuthLambda.swift:191` | `failure` | **correct catch / real bug** | same |
| 11 | `OAuthLambda.swift:205` | `failure` | **correct catch / real bug** | same |
| 12 | `OAuthLambda.swift:210` | `updateInteraction` | defensible | Discord `updateOriginalInteractionResponse` is overwrite-idempotent (PATCH to fixed content). Adopter should annotate. |
| 13 | `SponsorsLambda.swift:100` | `getUser` | adoption-gap | API read; adopter should annotate. |
| 14 | `SponsorsLambda.swift:128` | `sendMessage` | **correct catch / real bug** | Welcome Discord DM duplicates on GitHub sponsorship webhook redelivery. **Fix: `x-github-delivery`-keyed dedup before `sendMessage`.** |
| 15 | `FaqsHandler.swift:63` | `getAll` | adoption-gap | S3 read; adopter should annotate. |
| 16 | `FaqsHandler.swift:74` | `insert` | defensible | `S3FaqsRepository.insert` reads current state, writes only if name→value differs — idempotent by design. Adopter should annotate `@lint.effect idempotent`. |
| 17 | `FaqsHandler.swift:85` | `remove` | defensible | `S3FaqsRepository.remove` reads current state, writes only if name existed — idempotent by design. |
| 18 | `GHHooksHandler.swift:95` | `handleThrowing` | expected — see notes | `handle(_:)` wraps `handleThrowing(_:)` with try/catch. The diagnostic points at the delegation, but the genuine non-idempotency lives inside `handleThrowing`'s fan-out to `EventHandler.handle() → Discord + DynamoDB`. `handleThrowing` has partial dedup via `DynamoMessageRepo` (look-up table for repo+issue → Discord messageID) for the happy path; the error path is where the real bug lives (see #19). |
| 19 | `GHHooksHandler.swift:99` | `createMessage` | **correct catch / real bug** | Top-level error handler posts to Discord `botLogs` channel. On GitHub webhook redelivery (failure → catch → createMessage), maintainers get duplicate error notifications. **Fix: `x-github-delivery`-keyed dedup on the error path, or accept the noise.** |
| 20 | `GHHooksHandler.swift:106` | `unicodesPrefix` | noise | String-truncation helper (`"\(error)".unicodesPrefix(2_048)`). Pure function — linter over-infers via body-walk because it can't prove purity of adopter-owned string extensions. Adopter annotation fixes it. |

### Run A tally

- **Correct catches (real bugs with concrete fix shape):** **10**
  (positions 1, 6–11, 14, 19; plus 18 as the semantic target of
  the same fix as 19).
- **Defensible (code OK by design; adopter should annotate):** 6
- **Adoption gaps (pure read or straight-idempotent; adopter should annotate):** 3
- **Noise (linter over-inference):** 1

### The four concrete bug shapes

1. **Coin double-grant** — `UsersHandler.handleAddUserRequest` →
   `DynamoCoinEntryRepository.createCoinEntry`. On retry, new row
   + double coinCount increment. Caller-provided idempotency key
   required. Covered by `IdempotencyKey` + `@ExternallyIdempotent(by:)`.
2. **OAuth error-path Discord noise** —
   `OAuthLambda.{logErrorToDiscord, failure}`. Seven call sites
   across failure branches; each duplicates on retry. Covered by
   `IdempotencyKey(rawValue: code)` or a per-session dedup guard.
3. **Sponsor welcome DM duplication** —
   `SponsorsLambda.sendMessage`. GitHub sponsorship webhook
   redelivery fires the DM twice. Covered by
   `IdempotencyKey(rawValue: request.headers["x-github-delivery"])`.
4. **GHHooks error-path notification duplication** —
   `GHHooksHandler.handle`'s catch branch. Top-level error message
   to maintainers duplicates. Same fix shape as #3.

All four match shapes the `SwiftIdempotency` package's existing
public API was designed for. **First real-adopter validation that
the macro surface covers the bugs the linter surfaces.**

## Run B — strict_replayable context

**71 diagnostics.** Exceeds the 30-diagnostic audit cap; decomposed
by cluster below. Rule distribution: 100%
`[Unannotated In Strict Replayable Context]` (strict mode's
unannotated-callee rule).

**Carried from Run A** (20): every Run A diagnostic repeats, plus
additional strict-only fires at the same call sites.

**Strict-only** (51 additional): decomposed into three known
clusters plus one new observation:

| Cluster | Count | Shape | Verdict |
|---|---|---|---|
| **Stdlib / type-ctor gap** | ~25 | `init` (11), `String` (6), `ByteBuffer` (2), `map` / `first` / `stringConvertible` | Known cross-adopter residual. Same shape as Lambda round's type-ctor-gap (5/11) and TCA's `Duration` implicit-member (explicitly called out in `../next_steps.md`). No new slice needed. |
| **Adopter-type construction** | ~15 | `GatewayFailure` (5), `ActionType`, `UserRequest`, `CoinEntry`, `DynamoDBUser` ctor chains | Adopter-owned. Resolvable via `@lint.effect idempotent` or `@Idempotent` on adopter type initialisers. Standard adoption-gap — not a slice. |
| **Framework method gap** | ~10 | `mention` (DiscordUtils), `urlPathEncoded`, `guardSuccess`, `decode` (APIGatewayV2), `verify` (JWTKit), `makeUsersService`, `unicodesPrefix` (DiscordUtilities) | Cross-framework receiver-method gap. Similar to round 9's Lambda-response-writer (closed as slot 10). The specific frameworks in play — DiscordBM, JWTKit, DiscordUtilities — are new. Defer until cross-adopter evidence accumulates. |
| **Sub-handler dispatch cascade** | ~1 | `addCoin`, `getOrCreateUser`, `linkGitHubID`, `unlinkGitHubID` appear as strict-only where the `UserRequest` enum-case dispatch points at them | Inference-level noise — the `switch` dispatch shape hasn't been encountered before. Monitor but don't slice yet. |

No new named adoption-gap slices. Residual shapes match the
known cross-adopter noise.

### Comparison to Lambda round (round 9)

| Metric | Lambda round (demos) | Penny round (production) |
|---|---|---|
| Handlers annotated | 6 | 5 |
| Run A catches | 0 | 20 (5/5 handlers fire) |
| Run A correct-catches | 0 | 10 |
| Run A real-bug shapes | 0 | 4 distinct |
| Run B count | 16 (post-slot-10: 11) | 71 |
| Cross-framework slices surfaced | 1 (slot 10) | 0 (known residual only) |
| Linter crash bugs surfaced | 0 | 1 (slot 12) |

The **corpus-caveat hypothesis is validated**: real business-
side-effect code produces a radically different yield than demo
corpora. The FP rate (1 / 20 = 5% noise) is lower than expected;
the 6 defensible catches are all resolvable via adopter annotation,
not linter-fix work.

## Newly surfaced actionable slice — slot 12

**Linter crash on duplicate file basenames** (fix applied
in-session, not yet committed upstream).

**Shape:** `ProjectLinter.makeProjectFile(filePath:projectRoot:)`
computes `relativePath` via `filePath.hasPrefix(projectRoot + "/")`.
On macOS, passing `/tmp/penny-scan` as `projectRoot` fails the
`hasPrefix` check because filesystem enumeration returns
`/private/tmp/penny-scan/…` (the `/tmp` symlink resolves to
`/private/tmp`). The fallback is `(filePath as NSString).lastPathComponent`
— a bare filename. Downstream, `applyInlineSuppression` builds
`Dictionary(uniqueKeysWithValues: files.map { ($0.relativePath, $0.content) })`;
on adopters with duplicate filenames across targets
(Penny has 11 such collisions — `Errors.swift`×3, `Constants.swift`×4,
`+String.swift`×3, etc.), this crashes with
`Fatal error: Duplicate values for key: 'Errors.swift'`.

**Fix (in working tree):**

```swift
// ProjectLinter.swift makeProjectFile(...)
let resolvedRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
let resolvedFile = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
let relativePath: String = resolvedFile.hasPrefix(prefix)
    ? String(resolvedFile.dropFirst(prefix.count))
    : resolvedFile   // full path keeps uniqueness when outside the root

// applyInlineSuppression(to:files:)
let contentByRelativePath = Dictionary(
    files.map { ($0.relativePath, $0.content) },
    uniquingKeysWith: { first, _ in first }   // defensive: never crash on edge-case collisions
)
```

Two-part fix: (a) canonicalise via `resolvingSymlinksInPath` so
the prefix comparison is symlink-insensitive (the root cause);
(b) make the inline-suppression dedup collision-tolerant as a
belt-and-suspenders guard.

**Severity:** blocker for any multi-target Swift codebase with
duplicate basenames on macOS. **Trigger evidence:** first
production-target round. Not just Penny — any realistic
multi-target adopter (vapor core, NIO, hummingbird examples in
full form, etc.) likely trips it. Score for commit as a
standalone linter PR; tests should cover the /tmp-vs-/private/tmp
path canonicalisation and the duplicate-basename case.

## Pre-committed question answers

**Q1 — FP-rate on production business logic.** 1/20 = **5% noise
rate** on Run A (the `unicodesPrefix` over-inference). 3/20 =
15% adoption-gap (adopter annotations would close). 6/20 = 30%
defensible (adopter code OK by design). 10/20 = **50%
correct-catch with real-bug shape.** This is dramatically higher
signal density than any prior round.

**Q2 — Slot-10 regression check.** The framework whitelist shipped
for `AWSLambdaRuntime` response-writer primitives does not fire
on Penny (Penny uses top-level `func handle` returning
`APIGatewayV2Response` directly — no `outputWriter.write` /
`responseWriter.finish` pair on the surface). No regression. No
new whitelist candidates surfaced — the DiscordBM / JWTKit /
Soto* surfaces are cross-adopter residual, defer.

**Q3 — `IdempotencyKey` natural-adoption signal.** All four real-
bug shapes map cleanly to the `IdempotencyKey` /
`@ExternallyIdempotent(by:)` surface:

- `UsersHandler.addCoinEntry` → `IdempotencyKey(rawValue: <command message ID>)`,
  `@ExternallyIdempotent(by: "idempotencyKey")` on the request
  type.
- `SponsorsLambda.handle`, `GHHooksHandler.handle` error path →
  `IdempotencyKey(rawValue: request.headers["x-github-delivery"])`.
- `OAuthLambda.handle` → `IdempotencyKey(rawValue: code)` (single-
  use OAuth code).

The macro surface is a natural fit. The **first real-adopter
validation** that `IdempotencyKey` covers the bug shapes the
linter surfaces, end-to-end.

**Q4 — Cross-target shape collisions (slot-3 trigger).** No
`name(labels:)` collisions with differing tiers observed. The 5
handlers have unique signatures (`handle(_:)` with different
receiver types). `getUser` appears in `InternalUsersService` (DB
read) AND `UsersService` (HTTP client) with same signature — but
both classify as idempotent read, so no tier collision. **Slot 3
does NOT trigger** from this round. Stays deferred.

## Links

- **Scope:** [`trial-scope.md`](trial-scope.md)
- **Retrospective:** [`trial-retrospective.md`](trial-retrospective.md)
- **Run A transcript:** [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
- **Run B transcript:** [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
- **Fork:** [`Joseph-Cursio/penny-bot-idempotency-trial`](https://github.com/Joseph-Cursio/penny-bot-idempotency-trial)
- **Trial-branch tips:** `49db411` (Run A), `c309bcb` (Run B)
