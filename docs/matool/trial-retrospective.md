# MaTool — Trial Retrospective

## Did the scope hold?

Yes — measurement-only, doc-comment annotations only, no logic
edits, audit cap not exceeded (6 strict-mode fires << 30).
Data-layer audit added per the road_test_plan DB-heavy adopter
rule and surfaced the expected verdict-flip pattern (DynamoDB
PutItem-only writes → defensible). Round took ~30 minutes wall
clock from "fork created" to "findings doc written."

## Pre-committed questions

### 1. Email-on-retry detection (Cognito)

**Yes — both `DistrictController.post` and `.postReissue` fired
correctly with deep-chain inference.** The 5-hop / 2-hop
diagnostic messages are the linter's correct identification
that the non-idempotent leaf is the Cognito `adminCreateUser`
call several layers below the controller surface. Both fire
verdicts hold up after data-layer audit because the side
effect (sending an invitation email) is **outside DynamoDB's
key-based dedup** — Cognito doesn't dedup invitations on its
side, so each `adminCreateUser` call with the same username
either re-emails (until user exists) or throws
`UsernameExistsException` (after user exists), and during
the create-then-throw race window the email goes out anyway.

The 2-hop chain depth on `postReissue` is shorter than `post`
because the usecase calls Cognito directly without going
through the manager-factory layer. The linter's chain-depth
reporting is accurate to the call-graph structure.

This is the round's headline finding: **the linter correctly
detects email-on-retry across both single-create and
delete-then-create flows, even when the duplicate-check
defense is present in the application code.** Annotation
remediation: `@ExternallyIdempotent(by: <user-supplied-key>)`
on the `post` / `postReissue` request handlers, threading
the iOS app's idempotency key through to Cognito create
calls.

### 2. DynamoDB PutItem defensibility after audit

**Confirmed.** Both `LocationController.put` and
`FestivalController.put` fire as catches on the Swift
surface, then flip to defensible-by-data-layer-design after
the SQL ground-truth audit reveals the call chain ends in
**unconditional `client.putItem(input:)`** with no
`ConditionExpression`. DynamoDB PutItem is replace-by-
primary-key, which is semantically idempotent on retry.

This matches the isowords pattern documented in the
road_test_plan: "isowords Run A would have been mis-scored
as 3 real-bug catches without this pass (actual: 1 real
catch + 3 defensible-by-design upserts)." MaTool would have
been similarly mis-scored as 4 real-bug catches without
the audit; the actual count is 2.

The right linter remediation is to annotate `DynamoDBStore.put`
with `/// @lint.effect idempotent`, which would silence both
of these fires globally. That's annotation work for the
adopter, not a linter shape change.

### 3. DynamoDB DeleteItem silence

**Yes — `LocationController.delete` silent in replayable.**
Strict mode fires on the `Response.success()` call (response-
builder noise) but not on the DeleteItem chain itself. The
linter's chain inference doesn't classify DeleteItem as
non-idempotent in replayable mode because the `client.deleteItem`
call boundary is `unknown` (no annotation), and replayable
mode tolerates unknown.

This is the right behavior — DynamoDB DeleteItem on a missing
key is a no-op, semantically idempotent. Same annotation
remediation as PutItem (`/// @lint.effect idempotent` on
`DynamoDBStore.delete`).

### 4. Run A yield magnitude vs awslabs/Examples

**Confirmed empirically: 4 / 6 (production) vs 0 / 6 (demos).**
The CLAUDE.md hypothesis ("production Lambda app... is a
stronger target than awslabs' demos") is now backed by direct
measurement. Awslabs/Examples gave zero Run A yield because
demo bodies have no real side effects. MaTool gave 4 catches
on the Swift surface, of which 2 hold up as real-bug catches
after data-layer audit.

This generalises beyond Lambda: the same demo-vs-production
yield gap should exist for gRPC (the grpc-swift-2 round gave
1 catch on the canonical bidi shape, which IS a real catch
but only because route-guide was *designed* with that shape
deliberately) and GraphQL (graphiti gave 0 catches because
StarWarsAPI has no real side effects). **Production-app
rounds are the right next step in any domain that's currently
demo-only-covered.**

## Counterfactuals

What would have changed the outcome:

- **If the data-layer audit had been skipped.** Run A would
  have been mis-scored as 4 real-bug catches. The audit is
  cheap (~5 minutes of grep + read) and prevented mis-scoring
  by 2 false positives. **The DB-heavy adopter rule
  unconditionally pays for itself; should always run on any
  adopter with a DB layer.**

- **If MaTool had used DynamoDB transactions or conditional
  writes.** `TransactWriteItems` is idempotent only with a
  client-supplied `ClientRequestToken`. If MaTool had used
  conditional puts (`ConditionExpression: attribute_not_exists(pk)`),
  the `PutItem` would no longer be replace-by-PK idempotent —
  it would fail on second call with `ConditionalCheckFailedException`,
  changing the "second call is a no-op" semantic to "second
  call throws." The linter would still classify as non-
  idempotent, the audit would still flip to defensible (the
  exception-on-retry is a known-handled case), but the
  verdict reasoning shifts. Worth recording: **the verdict
  flip depends on whether DynamoDB PutItem is unconditional
  (replace) or conditional (insert-or-fail).** MaTool is
  unconditional, so the simple flip applies.

- **If a pure-read adopter had been chosen.** Skipping `post`
  and `postReissue` and only annotating `LocationController.get`
  / `.put` / `.delete` and `FestivalController.put` would have
  given 2 catches / 4 handlers (both PutItems), 0 real-bug
  catches after audit, same defensible verdict. The round's
  high-value finding is the email-side-effect catch in
  `DistrictController` — without that, the round would have
  produced the same "all-defensible" outcome as a demo round.
  **Selection of email-touching handlers was the round's most
  important annotation choice.**

- **If MaTool had been on a stale SHA (e.g. the
  comics-info-backend candidate, last push 2022).** Stale
  adopters carry the same shape evidence but invite the
  question "does this still apply?" — recent activity removes
  that question. MaTool's 10-day-old push date keeps the
  evidence current.

## Cost summary

- **Estimated:** ~30 minutes (real adopter, data-layer audit
  required).
- **Actual:** ~30 minutes wall clock. Steps:
  - Target search via `gh search code "import AWSLambdaRuntime"`
    (~2 minutes; immediately surfaced 5+ candidates).
  - Target evaluation across 4 candidates (~3 minutes;
    settled on MaTool for recent push + DDD architecture +
    email side effects).
  - Fork + harden + clone (~3 minutes).
  - Annotation work (~5 minutes for 6 handlers across 3
    files).
  - Both scans (~3 minutes total — Backend dir scans instantly).
  - Data-layer audit (~5 minutes — grep / read for DataStore,
    DynamoDBStore, CognitoAuthManager).
  - Three docs + transcripts (~10 minutes).

## Policy notes

Two notes worth folding back into `road_test_plan.md` on a
future revision:

1. **Production-app FP-rate evidence is achievable in any
   demo-only-covered domain.** When CLAUDE.md or
   `next_steps.md` flags a domain as "demo-only" (currently:
   gRPC, GraphQL, Lambda), the right next-round move is to
   search for a production app via
   `gh search code "import <DomainSDK>"` and pick a candidate
   with: (a) recent push activity (≤6 months ideal), (b)
   real side effects beyond demo-shape (DB writes, third-
   party API calls, email/SMS), (c) tractable size (single
   SPM package or small set). MaTool fit all three; comics-
   info-backend fit (a) failed (3+ years stale).

2. **Cognito `adminCreateUser` is the AWS canonical "email-
   on-retry" leaf.** Add to a future linter-side framework
   whitelist as `non_idempotent` (or more precisely as
   `externally_idempotent(by: client_request_token)` for
   call sites that pass an idempotency token via Cognito's
   `ClientMetadata` parameter — Cognito does support per-
   request idempotency keys for some flows but not all).
   This is single-adopter evidence so far; mention as a
   1-adopter slice candidate in `next_steps.md`.

## Data committed

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md`
- `trial-transcripts/replayable.txt`
- `trial-transcripts/strict-replayable.txt`

Trial fork (authoritative): `Joseph-Cursio/MaTool-idempotency-trial`
on branch `trial-matool`. Final state restored to
`@lint.context replayable` (the strict variant was committed
mid-round at `4209d28`, then reverted at `e7544af`).
