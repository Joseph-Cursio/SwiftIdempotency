# Post-Fix Verification — Receiver-Type Inference + CamelCase-Gated Prefix Matching

Appended after round 5. Captures two related fixes shipped on linter `main` after R5:

1. **Receiver-type inference** — syntactic resolver + stdlib-exclusion table (phases 1-5 of [`claude_phase_2_receiver_type_inference_plan.md`](../claude_phase_2_receiver_type_inference_plan.md)). Addresses R5's *too-broad* failure.
2. **CamelCase-gated prefix matching** — extension to the bare-name heuristic. Addresses R5's *too-narrow* failure.

Both shipped in a single session after R5. Verified together against the same `trial-inference-local` branch.

## New linter baseline

- **New files:**
  - `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/ReceiverTypeResolver.swift` — 7-layer syntactic resolver
  - `Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/StdlibExclusions.swift` — 13-pair (type, method) exclusion table
- **Modifications:**
  - `HeuristicEffectInferrer.infer(call:)` — receiver-type gate before bare-name check, plus camelCase-gated prefix matching for non-idempotent verbs (`send*`, `create*`, `insert*`, `append*`, `publish*`, `enqueue*`, `post*` — uppercase next char, non-stdlib receiver)
  - `HeuristicEffectInferrer.inferenceReason(for:)` — mirrors both suppressions; emits distinct provenance prose for prefix matches ("from the callee-name prefix `send` (in `sendEmail`)")
- **New tests:**
  - `ReceiverTypeResolverTests.swift` — 28 cases
  - `StdlibExclusionsTests.swift` — 19 cases
  - `ReceiverTypeR5RepoFixtureTests.swift` — 2 cases reproducing the exact pointfreeco `removeBetaAccess` shape
  - `HeuristicInferenceTests.swift` — 7 receiver-type-gated cases + 17 prefix-matching cases (positive, negative, camelCase-gate, stdlib-gate, reason-prose)

**Full linter test suite:** **2049 tests in 267 suites, all green** (R5 baseline was 1976/264).

## R5 fixture re-run

Target: `pointfreeco/pointfreeco` at `06ebaa5`, branch `trial-inference-local`. Same annotation state as R5 Run D (5 `@lint.context replayable` on webhook entry points + `TrialInferenceAnti.swift`).

Command (unchanged from R5):

```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
```

### Diagnostic count trajectory

| Linter state | Total | Scaffold (C) | Real-code | Noise |
|---|---|---|---|---|
| R5 (`9cc3bfe`) | 6 | 5 | 1 (`removeBetaAccess`) | 1 |
| Post stdlib-exclusion only | 5 | 5 | 0 | 0 |
| **Post stdlib-exclusion + prefix matching** | **9** | 5 | **4** | **0** |

### The 4 real-code catches — all correct

1. **`PaymentIntentsWebhook.swift:58` — `handlePaymentIntent → sendGiftEmail`**
   Inference route: 2-hop upward chain. `sendGiftEmail`'s body calls `sendEmail` (prefix match `send`+`E`); upward inference propagates non_idempotent up.
   Diagnostic: *"whose effect is inferred `non_idempotent` from its body via 2-hop chain of un-annotated callees"*.
   **This is the exact diagnostic R5 Run B hypothesised would fire but didn't.** The annotation-burden-reduction claim — round 3's four annotations collapsing to one — is now supported by evidence.

2. **`SubscriptionsWebhook.swift:70` — `handleFailedPayment → sendPastDueEmail`**
   Upward route: `sendPastDueEmail`'s body calls `sendEmail` (prefix match). R5 findings explicitly called this a "real hazard missed."
   **Genuine webhook-replay hazard.** Past-due email re-sent on Stripe webhook redelivery.

3. **`SubscriptionsWebhook.swift:75` — `handleFailedPayment → sendEmail`**
   Direct prefix match at a call site inside a `fireAndForget { }` trailing closure.
   **Genuine hazard.** Admin-alert email re-sent on replay.

4. **`SubscriptionsWebhook.swift:94` — `handleFailedPayment → sendEmail`**
   Error-path call. Same shape as (3).
   **Genuine hazard.** Admin error-alert re-sent on replay.

FP classification: **4/4 correct catches, 0 defensible, 0 noise.**

### The scaffold (5 diagnostics) — unchanged

All 5 `TrialInferenceAnti.swift` cases fire with identical line numbers and provenance prose as in R5. No regression.

## The debug gap that surfaced

When I first landed the stdlib-exclusion slice and re-ran Run D, it stayed at 6 diagnostics — the fix looked broken. Unit tests (28 resolver cases) all passed, but the real-code noise persisted.

A reproducing unit test matching pointfreeco's exact shape (`ReceiverTypeR5RepoFixtureTests`) failed with `.unresolved`. Root cause: the resolver walked `CodeBlockSyntax.statements` but not `ClosureExprSyntax.statements`. `withErrorReporting("...") { ... }` wraps the whole `removeBetaAccess` body in a trailing closure; `var users = [owner]` lives in that closure's statements (CodeBlockItemListSyntax without a CodeBlockSyntax wrapper). Walking up from `users.append(...)`, the resolver reached the closure but had no branch for it. Fix: one additional branch in `resolveIdentifier`, symmetrical to the existing `CodeBlockSyntax` branch.

The gap is worth naming because purely-synthetic unit tests couldn't have caught it. The fixture needed to mirror a real-code closure-wrapping pattern. Future resolver work should include a "shape copied from real target" fixture as a standard component, not a bug-hunt reaction.

## Acceptance against the implementation plan

| Plan Phase-5 criterion | Status |
|---|---|
| Run D drops by exactly 1 (the noise diagnostic) | ✅ 6 → 5 after stdlib slice |
| Run C unchanged | ✅ 5 positives, same prose, same depth |
| Run B unchanged | ✅ under stdlib slice (plan-scoped-out); prefix slice changes this — now fires ✓ |
| No regression on existing linter tests | ✅ — full suite green (2049/267) |

**Bonus above plan:** the prefix matching slice — not part of the original plan — produced 3 additional real-code catches (sendPastDueEmail + two sendEmail sites in `handleFailedPayment`). All correct, all previously-missed hazards per R5 findings.

## What this evidence changes for round 6

R5's retro named three candidate pieces of next work. Post this session:

1. **Receiver-type inference** — done (stdlib-exclusion slice + camelCase-gated prefix slice). Both R5 precision failures resolved.
2. **User-defined type-qualified anchors (YAML / baked-in library list)** — unchanged in priority. Would catch `mailgun.sendEmail`-style matches where both receiver and method are known non-idempotent. With prefix matching in place, many of these now fire anyway via `send*` — the YAML slice addresses only the cases where the method name doesn't follow a clear verb-prefix pattern.
3. **Macro package (proposal Phase 5)** — unchanged in priority. Still the largest qualitative improvement; `IdempotencyKey` as a compile-time-enforced strong type is stronger than any linter rule.

A round 6 measurement plan could now be written around: "rule set reproduces the four real pointfreeco hazards with one annotation per webhook entry point (down from zero catches in R5 despite four annotations). Is this the level of precision a real adopting team would sign off on, or does widening context to a larger pointfreeco or running against a `swift-log`-heavy internal microservice produce new noise?"

That's the next planning document when the team is ready.
