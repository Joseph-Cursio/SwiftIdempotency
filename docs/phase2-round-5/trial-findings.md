# Round 5 Trial Findings

Measurement of heuristic + upward inference (commits `83c828c` + `b4c1a81` + `14a38df` + `cf128da`) on real code. Linter baseline `9cc3bfe` — 1976 tests / 264 suites green. Primary target `pointfreeco/pointfreeco` at `06ebaa5`; secondary target `swift-aws-lambda-runtime` at tag `2.8.0`.

## Diagnostic count per run

| Run | Pointfreeco state | Lambda state | Diagnostics | Notes |
|---|---|---|---|---|
| A | bare `06ebaa5`, zero annotations | — | 0 | Inference silent without anchor — as expected |
| B | +1 `@lint.context replayable` on `handlePaymentIntent` | — | 0 | **Round-3 diagnostic NOT reproduced via inference** |
| C | B + TrialInferenceAnti.swift (9 cases) | — | 5 | 5/5 positives fire, 4/4 negatives stay silent |
| D | C + widened context on 4 webhook entry points | — | 6 | 1 new real-code diagnostic; classified *noise* |
| E | — | `2.8.0`, zero annotations | 0 | Cross-project inference-without-anchor clean |
| E' | — | +1 `@lint.context replayable` on Lambda `handle` | 0 | Observational + writer + sleep all correctly silent |

## Run B — the round-3 diagnostic did not reproduce

One edit: `/// @lint.context replayable` above `handlePaymentIntent` in `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift`. Everything else un-annotated, including `sendGiftEmail` and its callees.

**Expected per plan:** exactly one `nonIdempotentInRetryContext` diagnostic on the `handlePaymentIntent → sendGiftEmail` edge via either bare-name or body-based inference.

**Observed:** 0 diagnostics.

**Why the inference chain doesn't reach:** walking the call graph from `handlePaymentIntent`:

```
handlePaymentIntent → sendGiftEmail (unannotated)
                        → sendEmail (unannotated, defined in SendEmail.swift:163)
                            → mailgun.sendEmail
                            → prepareEmail
                      → notifyAdmins (unannotated)
                        → sendEmail
```

The bare-name heuristic whitelist contains exact names: `send`, `insert`, `append`, `create`, `publish`, `enqueue`, `post`. Every callee in the chain is `sendEmail` or `sendGiftEmail` — **prefix `send` without exact match**. The whitelist entry `send` does not match `sendEmail`. Upward inference therefore computes no effect for any function in the chain (no lub-contributing callees), and the call-site check on `sendGiftEmail(for: gift)` also finds no bare-whitelist match.

**Classification:** this is the plan's explicitly-anticipated "chain-reach gap" result. From the plan:

> "**If Run B produces 0 diagnostics:** either the inferrer didn't reach `sendGiftEmail`'s mailgun call (escaping-closure boundary? non-direct call shape?), or `sendGiftEmail`'s body doesn't actually use a bare-whitelist name."

The "doesn't use a bare-whitelist name" branch is the evidence. No escaping-closure boundary is involved; it's a pure whitelist-precision finding.

**Consequence for the plan's headline hypothesis:** the hope that inference reduces round 3's 4-annotation campaign to 1 annotation is **not supported by this first-slice whitelist on this chain**. The annotation burden that the round-3 retrospective called "the dominant Phase-1 adoption friction" is not addressed by what has shipped.

## Run C — every inference mode fires per fixtures

New file `Sources/PointFree/Webhooks/TrialInferenceAnti.swift` exercises each inference mode. Five positive cases:

| # | Shape | Callee | Provenance emitted | Result |
|---|---|---|---|---|
| 1 | `@context replayable` → bare `publish(...)` | `publish` | "from the callee name `publish`" | ✅ fired |
| 2 | `@effect idempotent` → bare `insert(...)` | `insert` | "from the callee name `insert`" | ✅ fired |
| 3 | `@effect observational` → `queue.enqueue(...)` | `enqueue` | "from the callee name `enqueue`" | ✅ fired (observational contract violation) |
| 4 | `@context replayable` → `r5Case4Leaf()` whose body calls `publish` | `r5Case4Leaf` | "from its body" (1-hop) | ✅ fired |
| 5 | `@context replayable` → 3-hop chain ending in `append` | `r5Case5Top` | "from its body via 3-hop chain of un-annotated callees" | ✅ fired, depth 3 |

Four negative cases:

| # | Shape | Why silence expected | Result |
|---|---|---|---|
| 6 | `@effect observational` → `logger.info` | Two-signal observational match — caller and callee same tier | ✅ silent |
| 7 | `@context replayable` → `store.save(...)` | `save` deliberately out-of-whitelist | ✅ silent |
| 8 | `@context replayable` → `customThing.debug(...)` | Receiver doesn't contain "log" — fails two-signal gate | ✅ silent |
| 9 | `@context replayable` + `Task { publish(...) }` | Escaping-closure policy applies | ✅ silent |

**Totals:** 5/5 positives fired with correct provenance prose and correct depth; 4/4 negatives silent. Every inference mode works on a realistic project layout at corpus scale. The unit-fixture claims generalise.

## Run D — widened context finds one real-code diagnostic

Added `/// @lint.context replayable` to four more webhook entry points (`stripePaymentIntentsWebhookMiddleware`, `fetchGift`, `stripeSubscriptionsWebhookMiddleware`, `handleFailedPayment`). Total pointfreeco annotations now: 5 `@lint.context replayable`, 0 `@lint.effect`. Total diagnostics: 6 (the 5 from Run C + 1 new).

### New diagnostic on real code

```
Sources/PointFree/Webhooks/SubscriptionsWebhook.swift:62
[Non-Idempotent In Retry Context] Non-idempotent call in replayable context:
'handleFailedPayment' is declared `@lint.context replayable`
but calls 'removeBetaAccess', whose effect is inferred `non_idempotent` from its body.
```

### FP audit

**`handleFailedPayment → removeBetaAccess` — verdict: noise.**

Walking `removeBetaAccess`'s body to find the inference anchor:

```swift
func removeBetaAccess(for subscription: Models.Subscription) async {
  ...
  await withErrorReporting("Remove beta access") {
    let owner = try await database.fetchUser(id: subscription.userId)
    var users = [owner]
    if let teammates = try? await database.fetchSubscriptionTeammatesByOwnerId(owner.id) {
      users.append(contentsOf: teammates)   // <— inference anchor
    }
    ...
  }
}
```

The anchor is `users.append(contentsOf: teammates)`. `append` is on the bare-name non-idempotent whitelist. But `users` is a **local Swift Array** (declared one line above). A local array mutation is by definition idempotent with respect to business state — it has no external effect on replay. Zero bearing on idempotency.

The bare-name heuristic cannot distinguish this from `queue.append(message)` where `queue` is a user-defined `AsyncQueue` writing to persistent storage. Both look identical at the SwiftSyntax level: `<receiver>.append(<arg>)`.

A team adopting this diagnostic would either annotate `removeBetaAccess` with `/// @lint.effect idempotent` (distorting the model — the function's non-idempotent hazards, including the actual `gitHub.removeRepoCollaborator` external call chain, would then also be trusted), or annotate `Array.append` itself with `/// @lint.effect idempotent` (which they can't — `Array` is from stdlib), or silence the rule. None of these are healthy outcomes.

### Real-code noise rate

- Fired diagnostics on real un-annotated code (excluding the trial scaffold): **1**
- Classified *correct catch*: 0
- Classified *defensible*: 0
- Classified *noise*: 1

N=1 is too small to compute a noise rate against the 10% / 25% thresholds in the plan. But N=1 being noise is itself a data point — the first diagnostic the system produced under the intended adoption pattern (add `@context replayable` to your webhook handlers) was a false positive on a local stdlib operation.

### What `handleFailedPayment` actually does on replay

Worth naming: the body of `handleFailedPayment` includes calls to `sendPastDueEmail(to: user)` (inside `fireAndForget { }`) and `sendEmail(to: adminEmails, ...)` (inside a different `fireAndForget { }`) at lines 68 and 73 and 92. These are the **real idempotency hazards** — webhook replay genuinely re-sends the past-due email and the admin alert.

The linter missed both. Reasons (same root cause as Run B):

1. `sendPastDueEmail` is `send`-prefixed but not bare-whitelist exact match.
2. `sendEmail` is `send`-prefixed but not bare-whitelist exact match.
3. Even if either were annotated, `fireAndForget { }` is not on the escaping-closure list in `UpwardEffectInferrer.escapingCalleeNames`, so calls inside it *would* propagate. But since neither callee matches the bare whitelist, the escaping-closure policy is moot.

So the one diagnostic the system produced (`removeBetaAccess`) was noise, and the two genuine hazards in the same function (`sendPastDueEmail`, admin `sendEmail`) were missed. The inference machinery had the wrong precision on both sides of the line simultaneously.

## Run E — cross-project cleanliness

Base Run E on `swift-aws-lambda-runtime` at `2.8.0` with zero annotations: **0 diagnostics**. No rule fired without an anchor on a codebase shape the inference was not tuned for. Cross-project inference-without-anchor cleanliness confirmed.

### Run E' — light-touch extension

Added `/// @lint.context replayable` to one Lambda handler's `handle(...)` method in `Examples/BackgroundTasks/Sources/main.swift`. The handler's body calls:

- `context.logger.debug(...)` — two-signal observational match (receiver name `logger` contains "log", method `debug` on log-level list). Observational in replayable context is fine.
- `outputWriter.write(...)` — "write" is explicitly out-of-whitelist (per the plan's "too ambiguous to classify by name alone" exclusion list). No inference.
- `Task.sleep(...)` — no bare-whitelist match on `sleep`.

**Observed:** 0 diagnostics.

This result is interesting in the same way Run B was: the Lambda handler *does* call `outputWriter.write(...)`, which is a business-state write to the response stream. A human reviewing this code for idempotency would flag it. The linter correctly doesn't fire (the bare name isn't whitelisted), but this is another instance of the "first slice under-reads real hazards" pattern. Unlike Run B, here "write" is out-of-whitelist by explicit design choice — so this is conservative-by-design rather than a gap.

## Cross-round diagnostic delta

| Round | Pointfreeco annotations | Diagnostic on `sendGiftEmail` edge | Source |
|---|---|---|---|
| 3 | 4 (context + 3 effects) | **1** fired | declared-annotation enforcement |
| 4 | 1 (context, `externally_idempotent` tier) | 0 fired | lattice refinement — round-3 catch was phase-appropriate artifact |
| 5 (Run B) | 1 (context only) | 0 fired | inference whitelist doesn't reach the chain |

The round-4 zero and the round-5 zero are not the same zero. Round 4's is "lattice trusts keyed tier"; round 5's is "bare-name whitelist misses prefix-named callees." Different root causes, and round 5's is the less satisfying outcome: it reflects a whitelist-precision gap, not a correctness decision.

## Net output

- **Inference-without-anchor cleanliness validated** on two corpora (Run A, Run E, Run E').
- **Inference machinery end-to-end validated** on the 9-case scaffold (Run C): all modes fire with correct provenance and depth; all negatives silent.
- **First-slice whitelist precision is the adoption blocker.** Two converging pieces of evidence:
  - *Too narrow:* Run B's whole `sendGiftEmail → sendEmail → mailgun.sendEmail` chain misses because none are bare exact matches. Hypothesised annotation-burden reduction not delivered.
  - *Too broad:* Run D's `users.append(contentsOf:)` fires on a stdlib local-array mutation. First real-code diagnostic produced under the intended adoption pattern is noise.
- **Receiver-type inference is the natural fix for both problems.** Prefix matching makes the too-narrow case better but the too-broad case worse. YAML whitelists push the precision problem onto each adopting team. Receiver-type inference distinguishes `Array<T>.append` from `Queue.append` and `SendEmailer.send` from `String.send` (if any). It is the one additive slice that improves both ends of the precision problem.

## Data committed

All run transcripts in `docs/phase2-round-5/trial-transcripts/`:

- `run-A.txt` — pointfreeco bare
- `run-B.txt` — pointfreeco + 1 context annotation
- `run-C.txt` — pointfreeco + context + TrialInferenceAnti.swift
- `run-D.txt` — pointfreeco + widened context
- `run-E.txt` — swift-aws-lambda-runtime bare
- `run-E-annotated.txt` — swift-aws-lambda-runtime + 1 context annotation on `handle`

No rule changes on the linter baseline. `trial-inference-local` branch on pointfreeco holds all round-5 edits; not pushed. One edit on swift-aws-lambda-runtime's local `trial-annotation-local` branch; not pushed. Test baseline `9cc3bfe` re-confirmed green 1976/264.
