# MaTool — Trial Scope

Sixteenth adopter road-test. **First production-app round in
the AWS Lambda domain** — closes the gap CLAUDE.md explicitly
flagged: *"For FP-rate evidence on Lambda specifically, a
production Lambda app (real side effects — DB writes, webhook
delivery, third-party API calls) is a stronger target than
awslabs' demos."*

The awslabs/swift-aws-lambda-runtime round produced zero Run A
yield because demo bodies (echo + base64 + AWS SDK reads)
contain no real side effects. This round substitutes a real
production Swift-on-Lambda app with real Cognito email
delivery + real DynamoDB writes to validate FP-rate evidence
on the same domain.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On a production Swift-on-Lambda backend (DDD-style:
> controller → usecase → repository, with DynamoDB writes and
> AWS Cognito email-send via API Gateway-bound handlers), do
> the canonical email-on-retry and DB-write-on-retry handler
> shapes fire under `@lint.context replayable` placed on the
> controller method? After SQL ground-truth audit, do real-
> bug catches differentiate cleanly from data-layer-defensible
> writes?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `0ca8a12`
  (2397 tests green, same SHA as graphiti + grpc-swift-2 rounds
  earlier this session).
- **Upstream target:** `kmatsushita1012/MaTool` @ `e6a40d1` on
  `main` (2026-04-14 push). Backend for "MaTool", an iOS app
  for the Kakegawa Matsuri (掛川祭) festival in Shizuoka
  Prefecture, Japan. Used in production by festival
  participants and tourists. Ship date appears to be late
  2025-2026 based on file timestamps.
- **Architecture:** custom lightweight `APIGateway` framework
  built on top of `awslabs/swift-aws-lambda-runtime`. DDD-
  style layering: Controllers extract request params, call
  Usecases (business logic), call Repositories (data access),
  which call `DataStore` → `DynamoDBStore` → AWS SDK
  `client.putItem(input:)`. Auth flows go through
  `CognitoAuthManager` calling `client.adminCreateUser(input:)`
  (which sends invitation emails via Cognito's default
  message action).
- **Fork:** `Joseph-Cursio/MaTool-idempotency-trial`, hardened
  per road-test recipe.
- **Trial branch:** `trial-matool`, forked from upstream
  `e6a40d1`. Fork-authoritative.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required.
- **Multi-package layout:** Repo contains Backend (SPM), Shared
  (SPM), iOSApp (Xcode project). Linter scoped to `Backend/`
  subdirectory only.

## Annotation plan

Six controller methods spanning CRUD across three domains
(Location / District / Festival) with deliberate shape diversity.

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Backend/Sources/Controller/LocationController.swift:33` | `LocationController.get(_:next:)` | **READ.** Pure correctness signal — should stay silent. Calls `usecase.get` → `repository.get` chain. |
| 2 | `Backend/Sources/Controller/LocationController.swift:48` | `LocationController.put(_:next:)` | **WRITE.** FloatLocation update (real-time location updates from float-tracking iOS app). Calls `usecase.put` → `repository.put` → `store.put` → `client.putItem`. |
| 3 | `Backend/Sources/Controller/LocationController.swift:56` | `LocationController.delete(_:next:)` | **DELETE.** Calls `usecase.delete` → `repository.delete` → `store.delete` → `client.deleteItem`. |
| 4 | `Backend/Sources/Controller/DistrictController.swift:52` | `DistrictController.post(_:next:)` | **CREATE with email side effect.** Calls `usecase.post` which calls **`managerFactory().create(username:email:)`** (Cognito invitation-email send) **and** `repository.post`. **High-value catch candidate.** |
| 5 | `Backend/Sources/Controller/DistrictController.swift:61` | `DistrictController.postReissue(_:next:)` | **REISSUE with email side effect.** Calls `usecase.postReissue` which calls Cognito `delete` + `create` (sends fresh invitation email). **High-value catch candidate — double-non-idempotent.** |
| 6 | `Backend/Sources/Controller/FestivalController.swift:41` | `FestivalController.put(_:next:)` | **WRITE — different domain.** FestivalPack update. Calls `usecase.put` → `repository.put` (DynamoDB PutItem). |

Deliberately excluded:

- `LocationController.query` — same shape as `get`, no new
  evidence.
- `DistrictController.put` and `.updateDistrict` — write paths
  similar to `LocationController.put`, would not differentiate
  catch verdicts.
- `RouteController` / `SceneController` / `PeriodController` —
  similar CRUD-style layouts. Skipping doesn't lose shape
  evidence and keeps the audit cap tight.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each controller `func`. No
  logic edits, no imports, no new types.
- **Audit cap.** 30 diagnostics per mode (template default).
- **Data-layer audit required.** Per road_test_plan.md DB-heavy
  adopter rule, every write-style verdict gets re-checked
  against the actual DynamoDB API call (PutItem / DeleteItem
  semantics). Cognito `adminCreateUser` semantics also re-
  checked for email-send default behavior.

## Pre-committed questions

1. **Email-on-retry detection (Cognito).** Do `DistrictController.post`
   and `.postReissue` fire as non-idempotent in replayable mode,
   correctly identifying that the `Cognito.adminCreateUser` call
   sends an invitation email on each invocation? This is the
   canonical "real-bug" shape — replay would email the user
   twice. **Hypothesis: yes — both fire with deep-chain
   inference (5+ hops through controller → usecase → manager
   factory → Cognito client).**

2. **DynamoDB PutItem defensibility.** Do `LocationController.put`
   and `FestivalController.put` fire as non-idempotent in
   replayable mode? After data-layer audit, **what should the
   final verdict be?** Hypothesis: fires in Run A (Swift surface
   shows non-idempotent inference), flips to defensible-by-data-
   layer-design after audit (DynamoDB PutItem is replace-by-
   primary-key, semantically idempotent on retry).

3. **DynamoDB DeleteItem silence.** Does `LocationController.delete`
   stay silent in replayable mode? DynamoDB DeleteItem on a
   missing key is a no-op, so it's semantically idempotent —
   but the linter doesn't know that without an annotation on
   the AWS SDK boundary. Hypothesis: silent in replayable (the
   call chain inference doesn't classify it as non-idempotent).

4. **Run A yield magnitude vs awslabs/Examples.** Awslabs Lambda
   Examples gave 0/6 Run A yield (all demo bodies). What does
   a real production app give? Hypothesis: significantly higher
   — probably 4 catches / 6 handlers (3 writes + 1 reissue), with
   the 2 readers + DynamoDB-PutItem-defensible-by-design giving
   the silent half. **The CLAUDE.md note's claim is testable
   here.**
