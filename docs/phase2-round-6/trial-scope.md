# Round 6 Trial Scope

## Research question

Do the receiver-type gating (post-R5 commit `b66316c`) and camelCase-gated prefix matching (same commit) produce the same precision profile on a corpus that was **not** tuned against?

Four sub-questions:

1. **Inference-without-anchor cleanliness** persists post-prefix-matching (i.e. no regression from R5 Run E).
2. **Real-code catch yield** under a comprehensive handler-only annotation campaign.
3. **New false-positive surface** from prefix matching on a different code style.
4. **Stdlib-exclusion coverage completeness** — does the Lambda corpus use patterns we didn't see on pointfreeco.

## Pinned artefacts

| Role | Repo / branch | SHA / tag | Local path |
|---|---|---|---|
| Linter baseline | `Joseph-Cursio/SwiftProjectLint` @ `main` | `68ad3bc` | `/Users/joecursio/xcode_projects/SwiftProjectLint` |
| Primary target | `swift-server/swift-aws-lambda-runtime` | `2.8.0` (= `553b5e3`) | `/Users/joecursio/xcode_projects/swift-aws-lambda-runtime` |
| Trial branch | `trial-inference-round-6` forked from `2.8.0` | — | same repo |

Linter baseline re-verified green post-Phase-0: 2049 tests / 267 suites. Target clone unshallowed (30 tags now reachable).

## Scope commitment

- **Measurement only.** No rule changes on the linter. No whitelist edits. No proposal updates during the round.
- **Annotation-only source edits.** The only modification: `/// @lint.context replayable` on each user-facing Lambda handler's entry method. One new trial scaffold file (Run C). No other edits.
- **Throwaway branch, not pushed.** Same policy as rounds 2-5.
- **Parser/inference-bug carve-out.** Run A diagnostic > 0 pauses the round and triages on a separate linter branch.
- **Per-diagnostic FP audit.** Cap 30 diagnostics.

## Lambda example annotation survey

Every example under `Examples/` was inspected. Nine examples expose a **named-function** entry point that can be annotated with the current grammar:

| # | File | Method | Line |
|---|---|---|---|
| 1 | `BackgroundTasks/Sources/main.swift` | `handle(_:outputWriter:context:)` | 36 |
| 2 | `ManagedInstances/Sources/BackgroundTasks/main.swift` | `handle(...)` | 38 |
| 3 | `ManagedInstances/Sources/Streaming/main.swift` | `handle(...)` | 29 |
| 4 | `Streaming+APIGateway/Sources/main.swift` | `handle(...)` | 27 |
| 5 | `Streaming+FunctionUrl/Sources/main.swift` | `handle(...)` | 27 |
| 6 | `MultiTenant/Sources/MultiTenantLocal/main.swift` | `handle(_:context:)` | 40 |
| 7 | `MultiSourceAPI/Sources/main.swift` | `handle(...)` | 27 |
| 8 | `Testing/Sources/main.swift` | `handler(event:context:)` | 27 |
| 9 | `S3_Soto/Sources/main.swift` | `handler(event:context:)` | 23 |

Out-of-reach (closure-based handler passed to `LambdaRuntime(body:)`) — the current `/// @lint.context` grammar targets function declarations, not closure expressions. This affects:

- `HelloWorld`, `HelloJSON`
- `APIGatewayV1`, `APIGatewayV2`
- `APIGatewayV2+LambdaAuthorizer` (both `simpleAuthorizerHandler` and `policyAuthorizerHandler` are closures)
- `JSONLogging`, `HummingbirdLambda`, `CDK`
- `ServiceLifecycle+Postgres`
- `_MyFirstFunction`

**This is itself a finding worth naming** — modern closure-based Lambda handler style (common in the ecosystem) is out of reach of the current annotation grammar. Run B measures the 9 named-function candidates; the closure-based surface is reported as a scope gap rather than annotated around.

Framework adapters (3 `handle` methods in `Streaming+Codable/Sources/LambdaStreaming+Codable.swift`) are **not** in scope — they pass events through to the user-supplied handler. Annotating adapter machinery as `replayable` is correct by transitivity but adds no signal the user handlers don't.

## Run C anti-injection cases

New file `Sources/SwiftProjectLintR6Fixtures/main.swift` (added as a standalone Package target so the build doesn't interfere with the Examples layout).

Positive cases (expect one diagnostic each):

1. `@lint.context replayable` → `sendNotification(to:)` — bare prefix `send`+`N`
2. `@lint.context replayable` → `createResource(spec:)` — bare prefix `create`+`R`
3. `@lint.context replayable` → bare `publishEvent(e)` — prefix, no receiver
4. `@lint.context replayable` → `queue.enqueueBatch(items)` where `queue: UserQueue` — prefix on user-typed receiver

Negative cases (expect silence):

5. `str.appending("x")` where `str: String` — stdlib-collection receiver, camelCase gate also blocks
6. `arr.sending(...)` where `arr: [Int]` — stdlib gate catches (prefix gate also blocks on lowercase `i`)
7. `publisher(for: \.prop)` — prefix `publish`+`e` lowercase, gate blocks
8. `postponed(task)` — prefix `post`+`p` lowercase, gate blocks
9. `Task { publish(event) }` — escaping-closure boundary

Total Run C contribution: +4.

## Acceptance summary

- **Run A:** 0 diagnostics. Non-zero invokes parser/inference-bug carve-out.
- **Run B:** N diagnostics, each classified; noise fraction reported. ≤ 10% adoption-ready.
- **Run C:** exactly 4 new diagnostics on cases 1-4; 0 on cases 5-9.
- **Run D (optional):** discretionary.

## Fallback

- If the `handler(event:context:)` annotation (cases 8, 9 in the survey) behaves differently from `handle(_:)` (e.g. because the visitor keys off the exact method name), flag as a visitor-level finding and adjust annotation strategy.
- If Run B's noise rate > 25%, stop and report the dominant noise shape. This becomes input for an R7 targeted fix.
- If unshallow takes excessive time or network fails, record pinned SHA and proceed from shallow clone (the pinned tag is all we strictly need).
