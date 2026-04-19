# Round 3 Trial Findings — Swift Idempotency Linter vs. `pointfreeco/pointfreeco`

Third and final Phase-1 road-test. Scope fixed by [`trial-scope.md`](trial-scope.md). Retrospective in [`trial-retrospective.md`](trial-retrospective.md). This report is strictly descriptive.

## Test vehicle

- **Linter:** `SwiftProjectLint` branch `idempotency-trial-round-3`, forked from `idempotency-trial-round-2 @ 20c6583` with **zero code changes**. Same exact linter as rounds 1-post-follow-up and 2.
- **Target:** `pointfreeco/pointfreeco`, main HEAD SHA `06ebaa5276485c5daf351a26144a7d5f26a84a17`, swift-tools-version 6.3.
- **Demo package:** `/Users/joecursio/xcode_projects/swift-webhook-idempotency-demo/` (new, webhook-shaped).
- **Annotation experiments:** branch `trial-annotation-local` in the pointfreeco clone. Not pushed.
- **Baseline:** 1844 tests in 251 suites passed on the round-3 branch (after one transient flake re-run, consistent with round-1's xcuserdata-cache observation).

## Corpus shape

- **918 Swift source files** across 30+ modules — 6.7× Hummingbird (137), 9× the round-1 Lambda runtime (~100)
- **74,588 total lines** in `Sources/`
- **Zero `actor` declarations.** pointfreeco uses Point-Free's `Dependencies` library for state isolation rather than actors
- Swift 6.3 source parsed cleanly by SwiftSyntax 602 — no crashes, no aborted visitations

## Phase 3 — positive demonstration (webhook-shaped before/after)

Demo: `swift-webhook-idempotency-demo`. A Stripe-webhook-shaped handler annotated `/// @lint.context replayable` with `logger.info` (observational) carried forward from round 2, plus `billing.applyCharge` (non_idempotent) in the before state and `billing.applyChargeIdempotent` (idempotent) in the after state.

**Before:**
```
Sources/Demo/WebhookHandler.swift:28: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'handleWebhook' is declared `@lint.context replayable` but calls 'applyCharge', which is declared `@lint.effect non_idempotent`.
  suggestion: Replace 'applyCharge' with an idempotent alternative, or route the call through a deduplication guard or idempotency-key mechanism.

Found 1 issue (1 error)
```
One diagnostic on the charge, **zero on the logger call**. ✅

**After:**
```
No issues found.
```
Zero diagnostics. ✅

The observational-tier assertion has now held across three codebases (Lambda-demo shape, Hummingbird-route shape, Stripe-webhook shape).

## Phase 4 Run A — parser scaling at application scale

Executed as the Phase 0 toolchain-compatibility smoke test:

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
No issues found.
```

**Zero diagnostics on 918 Swift-6.3 files.** SwiftSyntax 602 handled the corpus cleanly. This is a meaningful data point beyond round 2's 137-file result: the parser tolerates a 6.7× larger corpus written in a newer Swift version without producing any false annotation reads.

**Headline parser-scaling claim after three rounds: `EffectAnnotationParser` produces zero false positives on un-annotated source across 100-file, 137-file, and 918-file corpora spanning Swift 6.0–6.3.**

## Phase 4 Run B — structural `actorReentrancy` on pointfreeco

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories codeQuality --threshold warning
…
Found 2163 issues (17 errors, 151 warnings, 1995 info)
```

`grep -i "actor reentrancy\|actorReentrancy"` on the transcript: **zero matches**. Zero `actorReentrancy` diagnostics out of 2163 total codeQuality findings. The other 2163 are from unrelated rules (`forceUnwrap`, `couldBePrivate`, etc.).

### Triage

| Bucket | Count | Notes |
|---|---|---|
| A — true positive | 0 | |
| B — AST match, design-intent mismatch | 0 | |
| C — rule bug | 0 | |

### Why zero

**pointfreeco declares zero `actor` types.** The application uses Point-Free's own `Dependencies` library for state isolation — a protocol-based DI framework, not actor isolation. The rule is correctly scoped to actor methods and has no surface to match against.

This is **not** a false negative. The rule's precondition (actor-isolated mutable state accessed via async methods) simply does not occur in the codebase. The three-round pattern is now unambiguous: application actors and framework-style actors with structured concurrency are *not* where this rule earns its keep.

### The three-trial pattern for `actorReentrancy`

| Round | Target | Actor count | `actorReentrancy` findings | Shape |
|---|---|---:|---:|---|
| 1 | AWS Lambda runtime | multiple (runtime state machines) | **3** (all Bucket B) | State-machine invariant guards on `LambdaRuntimeClient.lambdaState` |
| 2 | Hummingbird | 2 | **0** | Both actors use claim-before-await or no-await-in-critical-section |
| 3 | pointfreeco | 0 | **0** | No actors exist |

The rule's value is architecturally specific. It will produce signal on **runtime** code that uses actors for state-machine modelling. It will produce little or no signal on codebases that use structured concurrency, DI, or lock-protected value types for state isolation.

This three-trial result is strong enough to motivate a concrete adoption-guidance note in the proposal — tracked as OI-6 below.

## Phase 4 Run C — **the real-code annotation test**

This is the most important result of round 3. The first time in the trial record where annotations are placed on **real production code that genuinely is replayable** (not synthetic demo code).

### Setup (on throwaway branch `trial-annotation-local`)

Honest annotations on pointfreeco's Stripe payment-intents webhook chain:

- `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:8` — `stripePaymentIntentsWebhookMiddleware` → `/// @lint.context replayable` ("Stripe documents webhook delivery as at-least-once: any non-2xx response triggers automatic retry with exponential backoff for up to 3 days.")
- `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:35` — `fetchGift` (private helper) → `/// @lint.context replayable` ("reachable only via the webhook middleware")
- `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:52` — `handlePaymentIntent` (private helper) → `/// @lint.context replayable`
- `Sources/PointFree/Gifts/GiftEmail.swift:16` — `sendGiftEmail(for:)` → `/// @lint.effect non_idempotent` ("Sends an email via Mailgun. Replaying on webhook redelivery sends a duplicate email to the gift recipient.")

Four annotations total. All four are **true** — this is not a manufactured test.

### Result

```
Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:68: error: [Non-Idempotent In Retry Context] Non-idempotent call in replayable context: 'handlePaymentIntent' is declared `@lint.context replayable` but calls 'sendGiftEmail', which is declared `@lint.effect non_idempotent`.
  suggestion: Replace 'sendGiftEmail' with an idempotent alternative, or route the call through a deduplication guard or idempotency-key mechanism.

Found 1 issue (1 error)
```

**Exactly one diagnostic, on the correct line (`handlePaymentIntent:68`), with the correct explanation, on production Stripe webhook code.**

### What Run C actually demonstrated

1. **The linter handles production Swift 6.3 code with generic middleware signatures** (`Conn<StatusLineOpen, Void> → Conn<ResponseEnded, Data>`) without confusion. The generic types are irrelevant to the annotation pipeline.
2. **Cross-file cross-directory resolution works.** `sendGiftEmail` lives in `Sources/PointFree/Gifts/GiftEmail.swift`; the calling annotation lives in `Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift`. The linter resolved the symbol across file *and* directory boundaries within the same module.
3. **The diagnostic's prose is immediately actionable.** A maintainer reading this output understands the problem, the specific edge, and a concrete remediation path.

### Annotation granularity — a real adoption concern surfaced

Getting the diagnostic to fire required annotating **three** functions in the webhook call chain as `@lint.context replayable`: the entry middleware, `fetchGift`, and `handlePaymentIntent`. Not just the entry point.

This is because Phase 1 has no effect inference or context propagation — each function's effect/context is judged only by its own annotation. A `replayable` context does not flow automatically to the functions it calls. For a real team adopting Phase 1, this means:

- Either annotate every function in a retry-exposed call chain individually (tedious, but sound — and discoverable, because the missing diagnostic is a hint)
- Or wait for Phase 2's effect inference to propagate automatically

This is a **working-as-specified** behaviour for Phase 1. It's also a clear motivating case for Phase 2's effect inference being the right next investment. The annotation-granularity observation is captured as a new entry under OI-1 / OI-6 below.

## Phase 4 Run D — observational tier substitute

Run D as originally designed assumed a codebase with dense `logger.info` / `Metrics.counter` call sites. **pointfreeco does not match that shape** — it uses `print()` statements (a different lint category entirely) and sparse custom logging helpers based on `Logger.log(_:_:metadata:...)`. The 15–20-call-site stress test round 2 executed on Hummingbird is not reproducible here without manufacturing synthetic call sites.

Substitute: added a small harness (`Sources/PointFree/Webhooks/TrialObservational.swift`) declaring two observational wrappers and one `@lint.context replayable` caller making three observational calls. Verified the rule produces zero diagnostics on those call sites.

Result:
```
Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:68: error: [Non-Idempotent In Retry Context] …
Found 1 issue (1 error)
```

The only diagnostic is the Run C carryover (`handlePaymentIntent → sendGiftEmail`). **Zero diagnostics from any of the three observational calls in `trialPfReplayableLoggingOnly`.** The observational tier behaves consistently at a third codebase's scale, even if pointfreeco's native logging doesn't exercise the tier the way round 2's did.

**Observational tier verdict after three rounds:** behaves correctly on demo shapes (rounds 2, 3) and at 20-call-site synthetic volume (round 2). Not stress-tested at application-scale logging volume; would need to be re-run on a target that uses `swift-log` natively.

## Summary

| Run | Expected | Observed | Pass? |
|---|---|---|---|
| Phase 3 before | 1 `nonIdempotentInRetryContext`, 0 observational | 1 on `applyCharge`, 0 on `logger.info` | ✅ |
| Phase 3 after | 0 | 0 | ✅ |
| Run A (idempotency / un-annotated pointfreeco) | 0 on 918 files | 0 | ✅ |
| Run B (actorReentrancy) | sparse or zero (pointfreeco has no actors) | 0 | ✅ (working-as-specified) |
| Run C (real-code annotation) | 1 diagnostic on real webhook chain | 1 on `handlePaymentIntent → sendGiftEmail` | ✅ **key new result** |
| Run D (observational substitute) | 0 FP on observational calls | 0 (only Run C carryover) | ✅ |

## Three-round comparison

| Dimension | Round 1 (AWS Lambda runtime) | Round 2 (Hummingbird) | Round 3 (pointfreeco) |
|---|---|---|---|
| Codebase type | serverless runtime | HTTP-server framework | real application |
| Files | ~100 | 137 | **918** |
| Swift tools version | 6.0 | 6.1 | **6.3** |
| Actor count | multiple (state-machine) | 2 | **0** |
| Run A result | 0 | 0 | 0 |
| `actorReentrancy` findings | 3 (all Bucket B, state-machine invariant) | 0 | 0 |
| Cross-file resolution demonstrated? | Not tested in-corpus (same-file demo) | Yes (unique names); blocked by collision on protocol methods | Yes, across cross-directory boundaries, on **real** production code |
| Observational tier behaviour | not shipped | 0 FP on 20 call sites | 0 FP on substitute shape |
| Real-code annotation campaign | No (demo only) | No (synthetic names only) | **Yes** — four annotations on real Stripe webhook chain; one diagnostic, correctly placed |
| New finding unique to round | OI-1's Bucket B state-machine subtype | OI-4's protocol-method collision gap | OI-6 motivation strengthens; annotation-granularity observation |

## Findings with proposal implications

Three observations the proposal should absorb, in decreasing order of importance:

### Finding R3-1 (strongest) — `actorReentrancy`'s architectural specificity is three-trial confirmed

After 1155 total Swift files across three stylistically different codebases, the rule has produced exactly **three findings** — all in round 1's actor-heavy Lambda runtime, all on the same state-machine-invariant subtype. Rounds 2 and 3 produced zero findings each.

This is strong evidence for an **adoption-guidance** note in the proposal, tracked as candidate OI-6: *"`actorReentrancy` is most valuable on code that uses actors for state-machine modelling. Teams with structured-concurrency + DI-based architectures (Hummingbird, pointfreeco patterns) may see zero findings. This is not a rule-quality signal — it reflects the rule's structural scope."*

Not a code change. One paragraph in the proposal.

### Finding R3-2 — Annotation granularity is an adoption concern Phase 1 has no answer for

Run C required annotating three functions along the webhook call chain to produce the diagnostic. A realistic team would experience this as "I have to annotate every helper, not just the entry point." This is the most concrete motivating case so far for **Phase 2's effect inference.**

Not a bug. But the trial record should carry this forward: the Phase 1 annotation ergonomics on real code are *slightly worse than the demo suggests.* The demo functions are small and linear; real webhook chains have 2-5 private helpers each. A realistic annotation campaign on a mid-sized Swift app is 10-30 annotations, not 2-3.

### Finding R3-3 (weakest, informational only) — pointfreeco doesn't stress the observational tier

Run D's form-as-designed could not be executed. pointfreeco's logging pattern (`print()` + custom source-location helpers) doesn't produce dense `Logger.info` call sites. Round 2's 20-call-site Hummingbird result remains the decisive observational-tier validation; round 3 added consistency but not new signal. **No proposal change.** Worth recording that the tier would benefit from one more stress test on a `swift-log`-native application codebase if one appears.

## Proposal amendments (suggested — not implemented on this branch)

- **OI-6 (new, promote from candidate to open issue).** Architecture-dependent rule value. Adoption-guidance paragraph as described in Finding R3-1.
- **OI-4 (carried forward from round 2).** Signature-aware collision policy. Still not pulled forward, per round 3's scope commitment. Round 3 did not re-trigger the policy because the uniquely-named `sendGiftEmail` avoided it.
- **OI-5 (validated across three codebases).** Status upgrades to "shipped, validated on one synthetic and two corpus-scale tests (one at 20-call-site volume, one at minimal substitute scale). Performance at application-scale dense-logging volume not yet verified."
- **Under OI-1, add:** annotation-granularity observation from R3-2 — the most concrete motivating case yet for Phase 2's effect inference.

## Follow-ups (deferred; consistent with scope commitment)

None of the above are implemented on `idempotency-trial-round-3`. The branch is a pure measurement artefact. Follow-ups land as separate commits on `idempotency-trial` (or a Phase-1.1 branch), not this one.
