# Wallet — trial findings

Transcripts:
[`replayable.txt`](trial-transcripts/replayable.txt) · [`strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

All line numbers are in
`Sources/VaporWalletPasses/PassesServiceCustom+RouteCollection.swift`
on the trial branch (fork tip `b875f47`).

## Run A — replayable

Five diagnostics across three of the six annotated handlers.
Three handlers are silent.

| # | Line | Handler | Callee | Inference source | Verdict |
|---|---:|---|---|---|---|
| 1 | 52 | `registerPass` | `createRegistration` | body of helper | defensible (cross-fn guard, see §1) |
| 2 | 55 | `registerPass` | `create` (FluentKit) | callee name `create` | defensible (read-then-create guarded by line 50 lookup) |
| 3 | 56 | `registerPass` | `createRegistration` | body of helper | defensible (same cross-fn guard, else-branch path) |
| 4 | 176 | `unregisterPass` | `delete` (FluentKit) | ORM verb `delete` | defensible (DELETE-idempotent; early `Abort(.notFound)` at 169-171 short-circuits second call) |
| 5 | 218 | `personalizedPass` | `create` (FluentKit) | callee name `create` | **correct catch** (no read-guard; SQL pass below) |

Silent handlers: `updatablePasses`, `updatedPass`, `logMessage`.

### SQL ground-truth pass

Migrations live under `fpseverino/fluent-wallet`'s
`Sources/FluentWalletPasses/Models/Concrete Models/`. Read in
full and intersected with every diagnostic above:

| Migration | Unique constraint | Implication for retry |
|---|---|---|
| `PassesDevice` | `.unique(on: pushToken, libraryIdentifier)` | Diagnostic 2: sequential retry hits the line-46 query, finds the existing device, returns `.ok` via the `if let device` branch — never re-enters create. **Sequential retry safe.** |
| `PassesRegistration` | none | Diagnostic 1+3: hand-rolled `if r != nil { return .ok }` at line 67-68 inside `createRegistration` is the only dedup. Sequential retry safe by handler logic. |
| `PersonalizationInfo` | `.unique(on: passID)` | Diagnostic 5: no read-guard before `personalization.create`. Sequential retry → unique-violation throw → 500. **Apple's spec gets a 5xx, not the expected 200.** Confirmed real bug. |

### Yield

Per road_test_plan §"Yield metric":
- 1 catch / 6 handlers = **0.17 including silent handlers**.
- 1 catch / 3 non-silent handlers = **0.33 excluding silent**.

The low yield is the headline. On a corpus where retry-safety is
*spec-mandated*, the linter's coarse callee-name inference
generated four false positives (Diagnostics 1-4) that the SQL
ground-truth pass swept. The single real-bug catch
(Diagnostic 5) is a clean find: `personalizedPass` does not
implement Apple's protocol correctly under retry, even though
`PersonalizationInfo`'s migration declares `.unique(on: passID)`
— that constraint converts a duplicate insert into a 500, which
loops Apple's retry rather than satisfying it.

### Adoption gap surfaced

**`cross-function-dedup-guard-not-propagated`.** Diagnostics 1
and 3 fire on `createRegistration` because the inferrer reads
the helper's body and sees `try await registration.create(on:
db)` without seeing that the call sits *after* `if r != nil {
return .ok }`. The guard correctly dedup-protects sequential
retry, but body-level inference doesn't represent the
read-then-write-with-early-return pattern. Whether to score this
as a slice depends on prior-round residual; flagging here for the
retrospective.

## Run B — strict_replayable

44 diagnostics total. 5 carried from Run A (line numbers
unchanged), 39 strict-only `Unannotated In Strict Replayable
Context` fires. Per road_test_plan §"Cap the per-round audit at
30 diagnostics" — strict-only fires are decomposed by callee
class instead of audited per-line.

### Carried from Run A

Same 5 diagnostics, same lines (52, 55, 56, 176, 218), wording
swapped from `replayable` → `strict_replayable`. Verdicts
unchanged.

### Strict-only — 39 fires, decomposed

| Cluster | Count | Sample callees | Verdict |
|---|---:|---|---|
| Vapor `Abort` early-error throw | 13 | `Abort(.badRequest)`, `Abort(.notFound)`, `Abort(.noContent)`, `Abort(.notModified)`, `Abort(.internalServerError)` | adoption gap — `throw Abort(...)` is observational by construction (a control-flow exit, no side effect on success path); strict-mode framework whitelist gap |
| Vapor / SwiftNIO HTTP plumbing | 11 | `HTTPHeaders`, `LastModified`, `Response`, `Body`, `add` (HTTPHeaders.add) | adoption gap — same framework whitelist gap; HTTP response construction is value-typed, idempotent on identical input |
| Fluent ORM read methods | 7 | `for`, `get`, `requireID`, `decode` | adoption gap — these are reads/value-coercion, classifiable as `idempotent` if the framework whitelist were extended |
| Foundation initializers | 3 | `Date(timeIntervalSince1970:)`, `TimeInterval(_:)`, `data(using:)` | adoption gap — value-type init, idempotent by construction |
| DTO / model initializers | 3 | `SerialNumbersDTO(with:maxDate:)`, `PersonalizationInfoType()`, `DeviceType(libraryIdentifier:pushToken:)` | adoption gap — model construction is pure; the *create-on-db* call is what carries effect, and that fires separately |
| Pure transforms | 2 | `signature(for:)`, `append(_:)` | mixed — `signature(for:)` calls into the WalletPasses signing builder (likely cryptographic, idempotent on input); `append` is array mutation (idempotent on receiver). adoption gap |

All 39 strict-only fires fall into one of six known clusters
already documented in prior trials (`hellovapor`,
`luka-vapor`). No new strict-mode adoption-gap class is
introduced by Wallet — the cluster shape is the **same** as on
prior Vapor adopters, which is itself a useful signal: strict
mode's residual on Vapor is stable.

## Comparison to predicted outcome

The scope doc predicted `personalizedPass` would be the real-bug
candidate. **Confirmed.** It also predicted the hand-rolled
`registerPass` guards would surface as defensible — they did, but
*not* because the linter recognized them. The linter fired
identically; the SQL ground-truth pass + handler-logic reading
swept them. That's the cross-function-dedup-guard adoption gap
above.

The scope predicted `logMessage` would be silent. **Confirmed.**
`req.logger.notice` is correctly classified as observational.

The scope predicted three silent handlers; got three
(`updatablePasses`, `updatedPass`, `logMessage`).

The Orders side was annotated as out-of-scope. By symmetry, Run A
on Orders would produce 4-5 diagnostics with verdicts identical
to the Passes side except no `personalizedPass` analogue exists
— so Orders' real-bug yield is predicted at 0/5. This is recorded
as a counterfactual rather than measured.
