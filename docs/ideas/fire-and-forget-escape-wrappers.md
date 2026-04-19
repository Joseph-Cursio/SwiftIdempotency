# Deferred idea: escape-gate recognition for `fireAndForget`-style wrappers

**Status.** Real gap, observed during round-5 triage on pointfreeco. Not currently producing noise in the trial record (the prefix-matching slice happens to catch the relevant cases by a different path), but the underlying flaw is real and would surface on a codebase with different idioms. Saved here as a follow-up the next time escape-gate behaviour is on the table.

## Origin

During round 5's Run D investigation of `handleFailedPayment → removeBetaAccess`, I noticed pointfreeco wraps several retry-context-sensitive calls inside `fireAndForget { ... }` trailing closures:

```swift
// from Sources/PointFree/Webhooks/SubscriptionsWebhook.swift
await fireAndForget {
    await removeBetaAccess(for: subscription)
}

// ... and later
await fireAndForget {
    try await sendPastDueEmail(to: user)
}

// ... and in the error path
await fireAndForget {
    try await sendEmail(to: adminEmails, subject: "...", content: ...)
}
```

Semantically, `fireAndForget` is an **escape boundary** — the closure's body runs later in a detached task, after the outer function has returned. Per the proposal's escape-closure policy, calls inside escape boundaries should not propagate effects to the outer function's inference scope (they're in a different retry context).

But `UpwardEffectInferrer.escapingCalleeNames` is hardcoded to a short list of structured-concurrency constructs:

```swift
private static let escapingCalleeNames: Set<String> = [
    "Task", "detached", "withTaskGroup", "withThrowingTaskGroup",
    "withDiscardingTaskGroup", "withThrowingDiscardingTaskGroup", "task"
]
```

`fireAndForget` isn't on the list, so its closure is walked as non-escaping. Calls inside propagate.

## What's broken, exactly

When the inferrer walks `handleFailedPayment`'s body to compute its upward-inferred effect, it descends into the `fireAndForget { sendEmail(...) }` closure as if the call were inline. After the prefix-matching slice shipped, this produced the *correct* diagnostic on `handleFailedPayment → sendEmail` — but only because the call happens to be non-idempotent AND the replayable context annotation is present AND the user would indeed want that diagnostic. The escape-gate wasn't consulted at all.

Replace `sendEmail` with a **transient local observability call** — say `metricsCollector.record(duration)` — and the same code path would fire a false positive: the closure is semantically fire-and-forget, the call inside it might legitimately run on a different schedule, and the replayable outer context says nothing about what fires inside a detached task.

Replace the outer effect annotation from `@lint.context replayable` to `@lint.effect idempotent` and the body-based upward inferrer would propagate `sendEmail`'s non-idempotency up to `handleFailedPayment`, reclassifying it as `non_idempotent` — *for reasons that exist entirely inside a detached task's closure*. That's the exact shape of noise the escape-gate exists to prevent.

## Why it hasn't surfaced as noise

Three coincidences keep the current record clean:

1. **All three of pointfreeco's `fireAndForget` call sites do non-idempotent work that the user legitimately wants flagged.** The closure-body calls happen to be `removeBetaAccess` (caught once via `append` in its body pre-receiver-type-fix; now correctly silent), `sendPastDueEmail` (prefix-matched correctly), and admin `sendEmail` (prefix-matched correctly). Every fire was a true positive.
2. **The trial hasn't yet measured a codebase with a different set of wrappers.** SwiftNIO's `eventLoop.execute { }`, Hummingbird's middleware `async let`, Vapor's `req.eventLoop.future { }`, and team-local wrappers would all exhibit the same blind spot.
3. **R6's Lambda corpus uses only the standard structured-concurrency constructs** (`Task.sleep`, no fire-and-forget helpers), so the gap didn't surface there either.

All three coincidences are likely to break on the next real-adopter codebase.

## Candidate fixes, if the gap surfaces

### Shape A — baked-in extension to `escapingCalleeNames`

Add the commonly-observed wrappers to the hardcoded list:

```swift
private static let escapingCalleeNames: Set<String> = [
    // existing
    "Task", "detached", "withTaskGroup", ...
    // additions from observed codebases
    "fireAndForget", "execute", "schedule",
]
```

Cheap, brittle, invites endless curation. Reasonable as a first-slice fix for the specific names that show up in the trial record, but not a long-term answer.

### Shape B — attribute-based detection

Swift's own `@_unsafeInheritExecutor`, `@Sendable @escaping` on a closure parameter type, and similar attributes carry the semantic signal. The resolver could inspect the call-expression's callee declaration (if reachable in source) and check whether the closure argument's declared type is `@escaping`.

Problem: we don't currently resolve the callee's declaration across files for this rule, and `@escaping` is optional in modern Swift (non-escaping is the default; `@escaping` is required only for storing the closure beyond the call). Many escape-semantics functions don't carry the attribute.

### Shape C — type-annotation-based gate

If the call's closure argument is of type `@Sendable () async -> Void` or similar dispatched-later shape, treat it as escaping. This is receiver-type inference's cousin — a *closure-type* inference.

Technically feasible with the resolver infrastructure already shipped. The lexical signal is there: a function that takes `@escaping () async throws -> Void` and synchronously returns without awaiting is almost certainly a fire-and-forget dispatch.

Problem: distinguishing "dispatches later" from "calls inline" from syntactic signals alone is fragile. `func foo(_ body: () async throws -> Void) async throws { try await body() }` takes the same-shaped argument but runs the closure inline.

### Shape D — YAML-configurable escape list

Project `.swift-idempotency.yml`:

```yaml
inference:
  escape_wrappers:
    - fireAndForget
    - execute
    - schedule
```

The cleanest fit for per-codebase idioms. Teams own the list. Ships naturally with any future YAML-whitelist slice. Current proposal roadmap already names YAML as "still deferred" — this would be a companion feature.

## Why it's not shipped

- **Zero evidence of noise.** R5 and R6 both produced zero false positives. No real-code case motivates the fix today.
- **The fix is speculative until the corpus proves the shape matters.** Any of shapes A-D would ship on a false assumption about which wrappers teams actually use.
- **Any YAML-based solution (shape D) couples to the larger YAML-whitelist slice** that's also deferred. Building a single-purpose YAML file just for the escape list is premature.

## Trigger for promotion

Promote this idea to an active plan when one of:

1. A trial round produces a false positive directly traceable to a non-stdlib escape wrapper.
2. A real adopter's codebase is observed to use non-stdlib dispatch wrappers at volume (Vapor/SwiftNIO EventLoop patterns, Hummingbird middleware, custom team patterns). The `swift-aws-lambda-runtime` corpus does not stress this; an internal microservice or a Vapor trial round might.
3. The YAML-whitelist slice ships for other reasons and this falls naturally under its scope.

## Related

- Escape-closure policy source: `UpwardEffectInferrer.escapingCalleeNames` in the linter repo.
- Related proposal-level deferred item: "name-configurable whitelists via project YAML" (see the Phase 2 section of `idempotency-macros-analysis.md`).
- [`inline-trailing-closure-annotation-gap.md`](inline-trailing-closure-annotation-gap.md) — the other closure-region gap from round 6.
