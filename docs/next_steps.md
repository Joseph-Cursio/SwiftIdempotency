# Next Steps

Session-handoff note for the next working session. Prioritised by
value-per-effort, top to bottom.

## Where things stand

- **Linter** (`Joseph-Cursio/SwiftProjectLint`): main at the most
  recent tip. Six slices shipped last session: Fluent save/update/delete
  (PR #11), drop nil-imports backcompat (#12), Fluent query-builder
  reads (#13), Hummingbird primitives (#14), move `update` to bare
  prefix (#15), wall-clock budget on the fixed-point loop (#16).
- **Macros** (this repo): shipped; unchanged this past session.
  `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`, `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.
- **Adopter road-tests**: three rounds completed — `todos-fluent/`,
  `pointfreeco/`, `swift-nio/`. Each has its own `docs/<slug>/`
  directory with scope / findings / retrospective / transcripts.
  pointfreeco round surfaced 4 probable Stripe-retry duplicate-email
  shapes in production code (see caveats in the retrospective).
- **Macro-form end-to-end validation**: ticked on `todos-fluent`
  via the attribute-form A/B supplement. Three macros still
  un-exercised on adopter code: `@IdempotencyTests`,
  `#assertIdempotent`, `IdempotencyKey`.

## Immediate candidates (small, concrete)

### 1. Point-Free library adopter round

Last remaining framework tier from [`swift_idempotency_targets.md`](swift_idempotency_targets.md).
TCA or swift-dependencies. Pure-function-heavy — very different shape
from the webhook/server adopters we've scanned. May surface
reducer / effect patterns the current heuristic misses. Follow the
template in [`road_test_plan.md`](road_test_plan.md); 30-45 min
per round.

### 2. Escape-wrapper recognition slice

Only open deferred slice candidate. `fireAndForget` (pointfreeco),
`detach` / `runInBackground` (AWS Lambda / Hummingbird-shape).
A per-framework whitelist of known "trusted observational wrappers"
would reduce strict-mode noise.

**Hold until a second adopter surfaces the same pattern** — the
current evidence is pointfreeco-specific. A Point-Free library
round or any AWS Lambda adopter round would be the natural
cross-adopter data point. Shape would mirror PR #14's
`idempotentReceiverMethodsByFramework`.

### 3. `.init(...)` member-access form gap

Long-running known gap. Firing at ~1/10 rate on todos-fluent,
~1/10 on pointfreeco. Current type-constructor whitelist matches
bare-identifier calls only (`JSONDecoder()`, `HTTPError(.notFound)`).
Extending to `Type.init(...)` member-access form would close one
diagnostic per framework-response-builder call site.

Low priority in isolation (1 catch per adopter) but the sum
across rounds is creeping up. Slice when it firing rate exceeds
~2/round consistently.

## Deeper work (bigger slices)

### 4. Real perf fix on the inference loop

PR #16 is a safety net (wall-clock budget, default 30s). The
underlying cause — `EffectSymbolTable.runInferencePass` scales
worse than linear in some dimension of swift-nio's wide per-file
call graphs — isn't fixed. Impact: multi-hop inference on huge
corpora is incomplete even with the budget.

Requires profiling + algorithm work. Probably 1-2 sessions.
Unlocks full correctness on swift-nio-scale codebases.

### 5. Macro-form validation for `IdempotencyKey` + `@ExternallyIdempotent(by:)`

Ties into pointfreeco finding #6 below: Stripe's `paymentIntent.id`
is the canonical idempotency-key carrier. Two paths:

- **Purpose-built sample**: tiny SPM package that consumes
  `SwiftIdempotency`, defines a webhook handler signature with
  `idempotencyKey: IdempotencyKey`, verifies the type system
  rejects raw `UUID()` construction. Cheap, demonstrates the
  type safety.
- **Annotate a real webhook adopter**: add `IdempotencyKey` to
  pointfreeco's `handlePaymentIntent` (or similar). Refactor-heavy;
  requires running the code to confirm; crosses from measurement
  into production changes.

Start with the sample; the adopter integration is its own project.

## Follow-ups on what we found

### 6. Verify the pointfreeco findings

The road-test surfaced 4 static patterns matching "Stripe retry →
duplicate email" in pointfreeco's webhook handlers. Unknown
whether runtime mitigations (Stripe event-ID dedup, `gift.delivered`
guards, DB-level constraints) prevent them from firing in
production. Three possible next moves:

- Read `pointfreeco`'s runtime path carefully for dedup guards
  outside the webhook handlers (database models, job queue layer).
- Open an issue on pointfreeco with the static findings — let
  the maintainers confirm or explain.
- Leave it. The round's value was validating the linter's
  precision; pursuing adopter bugs is a different project.

### 7. Remeasure swift-nio with annotations under the new budget

Now that full-corpus scans complete (~3 min post PR #16), a
proper full-corpus measurement with real annotations on NIO
handlers is cheap. Probably confirms the null-result conclusion
from the scoped scan. Worth doing once to close the loop on the
swift-nio round with a cleaner dataset.

## Memory note

The Claude-Code memory at
`/Users/joecursio/.claude/projects/-Users-joecursio-xcode-projects-swiftIdempotency/memory/`
has one entry — the direct-to-main workflow preference for both
`SwiftIdempotency` and `SwiftProjectLint`. Linter rule slices still
follow the PR workflow (PRs #11-16 form the heuristic-evolution
audit trail). Docs and simple tweaks go straight to main.

## Recommended next-session opener

"Let's do the Point-Free library adopter round on
`swift-composable-architecture`." That's slot (1) above. After
that round closes, revisit this file — the landscape will look
different.
