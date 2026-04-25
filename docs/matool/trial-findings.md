# MaTool — Trial Findings

Linter SHA `0ca8a12`. Target `kmatsushita1012/MaTool` @ `e6a40d1`.
Fork `Joseph-Cursio/MaTool-idempotency-trial` on branch
`trial-matool`. Six controller methods annotated `/// @lint.context
replayable` then flipped to `strict_replayable`.

## Run A — replayable

Transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| # | Site | Callee | Inference depth | Verdict (Swift surface) |
|---|------|--------|-----------------|------------------------|
| 1 | `LocationController.swift:51` | `put` (→ usecase → repository → store → AWS SDK) | 5-hop chain | **Catch (Swift surface)** — pending data-layer audit |
| 2 | `DistrictController.swift:56` | `post` (→ usecase → manager factory → Cognito SDK) | 5-hop chain | **Catch (Swift surface)** — pending audit |
| 3 | `DistrictController.swift:65` | `postReissue` (→ usecase → manager factory → Cognito SDK) | 2-hop chain | **Catch (Swift surface)** — pending audit |
| 4 | `FestivalController.swift:44` | `put` (→ usecase → repository → store → AWS SDK) | 5-hop chain | **Catch (Swift surface)** — pending audit |

**Yield (Swift surface):** 4 catches / 6 handlers = **0.67 including
silent**, 4/4 = **1.00 excluding silent**.

Silent handlers (correctness signal):

- `LocationController.get` — pure read on `usecase.get` →
  `repository.get` → DynamoDB GetItem chain.
- `LocationController.delete` — DynamoDB DeleteItem (idempotent
  on missing key, AWS SDK boundary classifies as `unknown`
  which replayable mode tolerates).

Predicted outcome from scope doc: 4 catches + 2 silent. **Outcome
matches prediction.**

## Data-layer audit (per road_test_plan.md DB-heavy rule)

Each Run A catch re-verified against the actual data-layer call.

### LocationController.put

`store.put(record)` in `LocationRepository.put` →
`DynamoDBStore.put` →

```swift
let attrs = try encoder.encode(record)
let input = PutItemInput(item: attrs, tableName: tableName)
let _ = try await client.putItem(input: input)
```

**Unconditional `PutItem`** (no `ConditionExpression: attribute_not_exists`).
DynamoDB `PutItem` is **replace-by-primary-key** — calling
twice with the same item produces the same final state.
**Semantically idempotent on retry.**

**Verdict flip:** catch (Swift surface) → **defensible by data-
layer design.** Silenced by adding `/// @lint.effect idempotent`
to `DynamoDBStore.put`, or to `client.putItem`.

### FestivalController.put

Same mechanism as `LocationController.put` (`FestivalRepository.put`
→ `DynamoDBStore.put` → unconditional `PutItem`).

**Verdict flip:** catch (Swift surface) → **defensible by data-
layer design.**

### DistrictController.post

`DistrictUsecase.post` does:

```swift
let _ = try await managerFactory().create(
    username: districtId,
    email: email
)
// District生成
let item = District(...)
let district = try await repository.post(item: item)
```

`managerFactory()` returns `CognitoAuthManager`. The
`.create(username:, email:)` call:

```swift
func create(username: String, email: String) async throws -> UserRole {
    let input = makeCreateInput(
        username: username,
        email: email,
        messageAction: nil
    )
    let response = try await client.adminCreateUser(input: input)
    ...
}
```

**`adminCreateUser` with `messageAction: nil`** triggers Cognito's
default behavior: **send a temporary-password invitation email
to the user.** On retry, this would attempt to create the user
again — Cognito returns `UsernameExistsException` (which the
usecase's pre-check `if let _ = try await repository.get(...)`
also defends against) — but the `client.adminCreateUser` call
itself can re-trigger email delivery if execution reached
the AWS SDK call before the duplicate check raced. Even with
the duplicate-check defense, the Cognito side effect is the
linter's correct catch.

**Verdict: REAL CATCH.** Email-on-retry is the canonical
non-idempotent shape. Maps to `IdempotencyKey` /
`@ExternallyIdempotent(by:)` with the request being the
external dedup key.

### DistrictController.postReissue

`DistrictUsecase.postReissue` does:

```swift
let manager = try await managerFactory()
do {
    try await manager.delete(username: districtId)
} catch {
    // 再発行時は存在しないユーザーでも継続して作成できるようにする
}
try await Task.sleep(nanoseconds: 1_000_000_000)
_ = try await manager.create(username: districtId, email: email)
```

`manager.delete` calls Cognito `adminDisableUser` +
`adminDeleteUser` (each idempotent on missing user, the
catch comment in Japanese explicitly notes this). Then
sleeps 1 second for Cognito eventual consistency. Then
calls `manager.create` which **fires another invitation email.**

On retry: delete + delete + sleep + create + create. The
double-create is the smoking gun — would send two
invitation emails to the user.

**Verdict: REAL CATCH** (and structurally double-non-idempotent
because the create call always re-executes regardless of
whether the user already exists).

## Final verdict tally

| Handler | Run A Swift-surface | Final verdict |
|---------|--------------------:|---------------|
| LocationController.get | silent | silent (correct read) |
| LocationController.put | catch | **defensible (DynamoDB PutItem)** |
| LocationController.delete | silent | silent (DynamoDB DeleteItem idempotent) |
| DistrictController.post | catch | **REAL CATCH (Cognito email-on-retry)** |
| DistrictController.postReissue | catch | **REAL CATCH (Cognito email-on-retry, double-non-idempotent)** |
| FestivalController.put | catch | **defensible (DynamoDB PutItem)** |

**Real-bug catches: 2 / 6 handlers = 0.33 including silent, 2/4 =
0.50 excluding silent.** This is the **first production-app
round in the AWS Lambda domain to produce non-zero real-bug
catches**, validating the CLAUDE.md hypothesis that real Lambda
apps surface real shapes that demo corpora don't.

## Run B — strict_replayable

Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

6 fires total (4 carried from Run A + 2 strict-only).

### Carried from Run A (4)

Same fires as Run A — strict mode elevates the diagnostic
severity but the verdict pattern carries through unchanged:

- `LocationController.put:51` — defensible-by-data-layer
- `FestivalController.put:44` — defensible-by-data-layer
- `DistrictController.post:56` — **real catch**
- `DistrictController.postReissue:65` — **real catch**

### Strict-only (2)

| Site | Callee | Verdict |
|------|--------|---------|
| `LocationController.swift:36` | `Date()` (in `get` — `usecase.get(districtId:user:now: Date())`) | **Known cross-adopter strict-mode noise.** Primitive constructor / time-source call. Same cluster as Int32, ContinuousClock.now, Duration in prior rounds. |
| `LocationController.swift:60` | `success` (in `delete` — `try .success()`) | **Adopter-internal response builder.** `Response.success()` is a static factory on the custom `Response` type — pure constructor, body-inferable but strict requires declaration. Same shape as Vapor `Response.success` and SwiftProtobuf `<Type>.with(_:)` (cluster B from grpc-swift-2). Defensible by strict-mode design. |

### Cluster summary

| Cluster | Fires | Verdict | Cross-adopter status |
|---------|-------|---------|----------------------|
| Carried (real-bug catches) | 2 | REAL CATCH | 2 fresh shapes from this adopter |
| Carried (DynamoDB PutItem-defensible) | 2 | Defensible by data-layer design | adopter-local |
| Strict-only (`Date()` / `Response.success` / etc.) | 2 | Defensible / known cross-adopter noise | known cluster |

**Yield (strict aggregate):** 6 / 6 = 1.00 fires per handler. The
"real signal" yield (real-bug catches only) is 2 / 6 = 0.33,
matching Run A.

The strict-mode residual is unusually small for a real
production app (only 2 strict-only fires beyond the carried
Run A catches). Reason: MaTool's controllers are very thin —
they delegate to usecase, get a result, return — so they
don't accumulate the "stdlib-pure-call tax" (filter / Int32 /
Duration) that fired heavily on grpc-swift-2 (16 strict-only
fires) or pointfreeco. The thin-controller / fat-usecase
DDD pattern keeps the strict residual confined to the leaf
side-effect calls, which is exactly where it should be.

## Comparison to scope-doc predictions

| Pre-committed question | Predicted | Observed |
|------------------------|-----------|----------|
| 1. Email-on-retry detection | yes (5+ hop chains) | **yes — 5-hop on `post`, 2-hop on `postReissue`.** Both correctly identify Cognito SDK as the non-idempotent leaf. |
| 2. DynamoDB PutItem defensibility after audit | catch on Swift surface, defensible-by-data-layer-design after audit | **confirmed.** Both `LocationController.put` and `FestivalController.put` flip from catch → defensible. |
| 3. DynamoDB DeleteItem silence | silent in replayable | **yes — `LocationController.delete` silent in replayable.** Strict mode fires on the `Response.success()` call (response-builder noise), not on the DeleteItem chain itself. |
| 4. Run A yield magnitude vs awslabs/Examples | 4 catches / 6 handlers (Swift surface) | **exactly 4 catches / 6 handlers.** Awslabs/Examples gave 0/6. **CLAUDE.md hypothesis confirmed empirically.** |

All four pre-committed predictions held. The round is the
first to definitively validate that real production Swift-on-
Lambda apps produce non-zero FP-rate evidence where demo
corpora produce zero.

## Cross-round comparison

| Round | Run A (Swift surface) | Real-bug catches (after audit) |
|-------|----------------------:|-------------------------------:|
| swift-aws-lambda-runtime (demos) | 0 / 6 | 0 |
| grpc-swift-2 (demos) | 1 / 5 | 1 (route-guide bidi) |
| graphiti (demos) | 0 / 5 | 0 |
| **MaTool (production)** | **4 / 6** | **2** |

The MaTool round vindicates the CLAUDE.md guidance on
production-vs-demo target selection. **Real production apps
on novel infrastructure surface real-bug catches; demo
corpora are infrastructure smoke tests.**

## Real-bug shapes added to the cross-adopter tally

Per `next_steps.md`: prior count "Ten real-bug shapes caught
by the linter across Penny + isowords + prospero +
myfavquotes-api + luka-vapor + hellovapor."

This round adds:

- **MaTool — `DistrictController.post`** — Cognito
  `adminCreateUser` invitation email on retry. Maps to
  `IdempotencyKey` (the request itself is the dedup key).
- **MaTool — `DistrictController.postReissue`** — same
  Cognito email shape, structurally double-non-idempotent
  (the always-execute create after delete makes the email
  fire twice on retry regardless of duplicate-check guard).

**New tally: twelve real-bug shapes across seven adopters.**
Both shapes map to the same remediation pattern as the
existing ten (`IdempotencyKey` / `@ExternallyIdempotent(by:)`),
so no new remediation pattern is introduced — the round
confirms the existing pattern's coverage extends to the
Lambda + Cognito ecosystem.
