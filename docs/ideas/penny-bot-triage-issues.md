# Deferred idea: open narrowly-scoped penny-bot triage issues for the four real-bug shapes

**Status.** Deferred — gated on user approval. The underlying
research is complete; filing four narrowly-scoped GitHub issues on
`vapor/penny-bot` is a publicly-visible communication action, and
the user has not yet decided whether pursuing upstream adopter
bugs is in scope for this project.

## Origin

Round 6 (penny-bot) verification. See
[`../penny-bot/trial-findings.md`](../penny-bot/trial-findings.md)
for the full audit (20 Run A diagnostics, 10 correct-catches, 4
distinct real-bug shapes) and
[`../penny-bot/trial-retrospective.md`](../penny-bot/trial-retrospective.md)
for the macro-surface validation argument (every shape maps
cleanly to `IdempotencyKey` / `@ExternallyIdempotent(by:)`).

Headline: **every real-bug shape is a concrete fix-shape, not a
judgment call.** Unlike the pointfreeco findings (where #2–#4
required policy decisions about Stripe-retry email intent),
Penny's four bug shapes are all unambiguous duplicate-side-effect
hazards on at-least-once delivery surfaces.

## The four bug shapes

For each, the shape includes: file / line / callee, the retry
mechanism that exposes it, and the fix pattern.

### 1. Coin double-grant — `UsersHandler.handleAddUserRequest`

- **Site:** `Lambdas/Users/UsersHandler.swift` →
  `InternalUsersService.addCoinEntry`.
- **Mechanism:** on API-layer retry (API Gateway / async-http-
  client / Lambda async invocation), `addCoinEntry` creates a
  fresh `CoinEntry` row in DynamoDB **and** increments
  `user.coinCount` by `coinEntry.amount`. No idempotency key,
  no dedup guard. A sender awarding 10 coins could have
  `coinCount` reduced by 20 on retry; recipient credited 20
  instead of 10.
- **Fix shape:** add an `IdempotencyKey` field (natural key:
  the Discord message ID of the coin-awarding slash-command
  invocation, which callers already have) to
  `UserRequest.CoinEntryRequest`. Annotate the request type
  with `@ExternallyIdempotent(by: "idempotencyKey")`. Inside
  `DynamoCoinEntryRepository.createCoinEntry`, conditionally
  insert on the idempotency key and return the existing row
  on collision.
- **User-visible severity:** financial-ish
  (coin-economy integrity); a retry storm under partial
  outage would corrupt user balances.

### 2. OAuth error-path Discord duplication — `OAuthLambda.handle`

- **Sites:** 7 call sites across `OAuthLambda.swift`:
  `logErrorToDiscord` × 3 (lines 100, 106, 131),
  `failure` × 3 (lines 176, 191, 205 — each wrapping
  `logErrorToDiscord` + `updateInteraction`), and
  `updateInteraction` × 1 (line 210, a defensible-idempotent
  but still caught site).
- **Mechanism:** OAuth callback retries (Lambda async
  invocation failures, GitHub OAuth callback redelivery).
  GitHub's OAuth `code` is single-use — so `getGHAccessToken`
  itself would reject a retried code — but only AFTER Discord
  has already been notified of the previous error. The net
  effect: maintainers get duplicate error messages in the
  `botLogs` channel on every transient OAuth failure that
  gets retried.
- **Fix shape:** dedup on the OAuth `code` (single-use, cheap
  to key on). A small DynamoDB `processed_codes` table with
  TTL, consulted at the top of `handle(_:)`. Or: rely on
  GitHub's single-use-code rejection and add an
  `if isRetry { return .init(statusCode: .ok) }` short-circuit
  on the specific "code already used" error variant.
- **User-visible severity:** operational noise only (no
  incorrect state; just duplicate error posts). Lowest of the
  four.

### 3. Sponsor welcome DM duplication — `SponsorsLambda.sendMessage`

- **Site:** `Lambdas/Sponsors/SponsorsLambda.swift:128` →
  `sendMessage(to:role:)` sending a Discord DM.
- **Mechanism:** GitHub sponsorship webhook redelivery. The
  GitHub Webhook Delivery ID (`x-github-delivery` header) is
  stable across retries. Without dedup, the recipient gets
  multiple welcome DMs; with aggressive GitHub retry policy,
  could be dozens.
- **Fix shape:** read `x-github-delivery` from the request
  headers at the top of `handle(_:)`. Use it as an
  `IdempotencyKey`. Gate the entire sponsorship-processing
  block on "haven't seen this delivery ID yet."
- **User-visible severity:** user-facing Discord DM spam.
  Community-optics sensitive.

### 4. GHHooks error-path notification duplication — `GHHooksHandler.handle`

- **Site:** `Lambdas/GHHooks/GHHooksHandler.swift:99` →
  `createMessage` in the top-level error-catch branch of
  `handle(_:)`.
- **Mechanism:** GitHub webhook redelivery on 5xx responses.
  The happy-path of `handleThrowing` has partial dedup via
  `DynamoMessageRepo` (keyed on `repo + issue_number`), but
  the error path is outside that infrastructure — each failed
  invocation posts a full error + body dump to the `botLogs`
  Discord channel. Under a redelivery storm, maintainers are
  drowned in duplicate stack traces.
- **Fix shape:** same as #3 — `x-github-delivery` header
  dedup, but specifically on the error-path `createMessage`
  call. Two-level cache: a short-TTL (say 5 min)
  recent-error-deliveries set that suppresses the Discord
  post on repeat.
- **User-visible severity:** operational noise under outage.
  Same shape as #2, different channel.

## Why not filed

- **User approval required.** Four public GitHub issues on a
  community-maintained repo is a step beyond the pointfreeco
  case's one-issue shape. The right filing strategy (one
  consolidated issue vs. four separate ones, with or without
  a cover issue proposing the `IdempotencyKey` pattern as a
  general answer) is also a policy choice the user hasn't
  taken yet.
- **Scope uncertainty.** Same as pointfreeco — the project's
  stated scope is linter + macros design + validation, not
  upstream adopter engagement. Filing these is a separable
  extension.
- **One-shot, non-reversible.** Four issues cannot be
  cleanly un-filed. Editing or deleting leaves a trace,
  especially if contributors have responded.
- **Filing etiquette.** Four issues at once from the same
  source can read as a dump. The user may prefer either
  (a) one consolidated issue with all four shapes, (b)
  spacing them out across weeks, or (c) filing only the
  highest-impact one (#1, coin double-grant) and holding
  the others pending maintainer response.

## Shape of the issue(s) if filed

### Option A — one consolidated issue

Title: "Four at-least-once-delivery hazards on retry-exposed
Lambda handlers (webhooks, OAuth callback, API-layer)."

Body: brief preamble, then four sub-sections matching the
four shapes above (file/line, mechanism, fix shape). Lead
with the coin double-grant as the highest-impact. Reference
the `SwiftIdempotency` prototype linter as the surfacing
tool, one sentence, no advocacy.

### Option B — four separate issues

One issue per shape. Cross-link them with a "related:" block.
Pros: each can be triaged on its own merits, closed
independently. Cons: higher review-overhead for maintainers;
reads more demanding.

### Option C — file #1 only

The coin double-grant. Title: "CoinEntry double-grant on API
retry in `UsersHandler.handleAddUserRequest`." Mirror the
pointfreeco-triage-issue playbook — one narrow, high-impact
issue; hold the others for later signal.

### Common constraints regardless of option

- Pin the finding to the exact commit analysed during round 6:
  `vapor/penny-bot` @ `ac9391916b7d96537709b72269d5757e49163ab5`.
- Don't advocate for linter adoption in the issue body. The
  linter is the tool that found the bug; it isn't the subject.
  A brief "surfaced by an idempotency-linter prototype" line
  is the most that belongs in the issue.
- Include a minimal patch sketch for each shape (not a PR —
  just the file/line and the `IdempotencyKey` pattern).
- Name `x-github-delivery` explicitly for #3 and #4 — GitHub's
  official recommendation for webhook dedup, which maintainers
  will recognise immediately.

## Trigger for promotion

Promote this idea to action when one of:

1. The user explicitly approves filing (one or more of the
   three options above).
2. Adopter-engagement (upstream triage of linter-surfaced bugs)
   becomes a named workstream of this project. In that case
   Penny is the second exemplar after pointfreeco, and the
   pattern becomes standard.
3. An independent, unrelated penny-bot idempotency bug report
   gets filed (by anyone) and the maintainers' reply signals
   receptiveness to a second narrow report — bar-for-filing
   drops, as with the pointfreeco case.
4. The `SwiftIdempotency` package gets announced / released
   to the Swift Server community. Penny's findings become a
   natural worked-example in the announcement, and reporting
   them upstream becomes part of the launch narrative.

## Why it's parked, not discarded

The findings are load-bearing for the project's evidence:
**four concrete production bugs found by the linter, verified
against runtime behaviour, each with a one-shape fix using the
shipped macro surface.** That narrative holds whether or not
the issues are filed. Parking the filing while keeping the
research is the right separation — same logic as the pointfreeco
case.

## Related

- [`../penny-bot/trial-findings.md`](../penny-bot/trial-findings.md)
  — full round-6 audit. Section "The four concrete bug shapes"
  is the source for the filings.
- [`../penny-bot/trial-retrospective.md`](../penny-bot/trial-retrospective.md)
  — macro-surface validation (Q3) — argues each shape maps
  cleanly to `IdempotencyKey`.
- [`pointfreeco-triage-issue.md`](pointfreeco-triage-issue.md)
  — the sibling idea doc; if both get promoted, the Penny
  filing inherits the issue-shape conventions codified there.
