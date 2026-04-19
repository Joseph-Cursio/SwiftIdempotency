# hummingbird-examples / todos-fluent — Trial Retrospective

This round's authoritative measurement has been re-run twice as
linter slices have landed. Git history is the chronological audit
trail; this retrospective describes the current state of the
answers.

## What landed since the first measurement

- **PR #11** (`SwiftProjectLint`) — Fluent ORM-verb gate. Made
  `save` / `update` / `delete` infer `non_idempotent` when
  `FluentKit` is imported. Motivated by the round's zero-yield
  result on `replayable` mode and directly validated by it.
- **PR #12** — dropped nil-imports backward-compat from the
  heuristic inference API. Cognitive-surface cleanup, no adopter
  behaviour change.
- **PR #13** — Fluent query-builder idempotent-read slice.
  Predicted ~7 strict-mode silences on this corpus; measured 8.
  Same shape as PR #11 but for the read-only side of the Fluent
  API surface.
- **PR #14** — Hummingbird primitive slice. Adds `HTTPError`
  (bare-identifier type constructor) and a new
  `(receiver, method)` pair whitelist shape for
  `request.decode` / `parameters.require`. Predicted 4
  strict-mode silences; measured exactly 4.
- **Macro-form supplement** on this round's doc branch — added a
  `@NonIdempotent`-annotated helper to `TodoController` and
  confirmed byte-identical linter output to the equivalent
  doc-comment form. Ticks completion criterion #3 in
  [`road_test_plan.md`](../road_test_plan.md).

## Answers to the four pre-committed questions

### (a) Did replayable yield match the prediction?

**Yes, and it stayed stable through the subsequent slices.** 4
diagnostics on 3 annotated handlers + 1 helper — the adopter-shape
"POST creates duplicate row" bug the rule suite was designed for,
plus the macro-form attribute catch the supplement added. `list`
still produces zero diagnostics in replayable mode (now via the
Fluent read gate's `idempotent` classification rather than
silent-by-correctness — two mechanisms converging on the same
result).

### (b) Did the diagnostic prose correctly credit the Fluent gate?

**Yes, across both gates.** The non-idempotent catches carry
`from the FluentKit ORM verb <name>` (PR #11 wording); the
read-side catches would have carried `from the FluentKit
query-builder read <name>` but they silence rather than fire in
replayable mode, so the phrase only appears in `inferenceReason`
audit output. Adopters reading any firing diagnostic see the
specific framework that classified the call, which tells them
immediately which whitelist to annotate around if the inference
is wrong.

### (c) What's the strict-mode decomposition?

Post-PR-14: **6 total**, all in `TodoController.create`. 4 are
carried from replayable mode (save/update/delete + the macro-form
`recordAuditEvent` helper) — these are correct catches of real
non-idempotent calls. The remaining 2 are `Todo()` (adopter-owned
constructor; adopter's responsibility, not a linter whitelist) and
one `.init(...)` member-access form (known long-running gap, 1/6
firing rate). See [`trial-findings.md`](trial-findings.md).

### (d) Which adoption gaps are next-slice worthy?

**None on this corpus.** The strict-mode residual has plateaued
at 6; no cluster has the 3-catch-or-more density to motivate a
new slice. Remaining firing shapes are either (i) intentionally
correct catches, (ii) adopter responsibility, or (iii) the
deferred `.init(...)` gap still awaiting cross-adopter evidence.

Further progress against
[`road_test_plan.md`](../road_test_plan.md)'s completion criteria
requires moving to a different adopter — todos-fluent has
delivered what it can.

Macro follow-ons (not adopter-shape-appropriate for todos-fluent,
documented for future round selection):

- `@IdempotencyTests` — needs zero-arg target functions; handlers
  all have args. Purpose-built sample or a different adopter.
- `#assertIdempotent` — needs test fixtures; defer to an adopter
  with the right existing test granularity.
- `IdempotencyKey` + `@ExternallyIdempotent(by:)` — best on a
  payment/webhook adopter where the annotations fit naturally.

## What would have changed the outcome

- **Annotating `TodoController.update`.** Same body shape as
  `create` (calls `todo.update(on:)`); would produce a fourth
  Fluent catch. Unchanged from the initial retrospective — still
  low marginal value given the primary question is already
  answered.
- **Running the initial scan with PR #13 already landed.** Would
  have shown strict mode's actual residual directly instead of
  the 17-then-10 two-step. Git history preserves the intermediate;
  this retrospective doesn't need to.

## Cost summary

- **Initial round** (pre-PR-13): ~25 minutes of model time —
  branch, annotate, scan ×2, write up.
- **Macro-form supplement**: ~15 minutes — adopter dep, helper,
  A/B scan, write up. Separate PR (none — docs-only).
- **PR #13 slice on SwiftProjectLint**: ~20 minutes —
  FrameworkWhitelist extension, inferrer wire-up, 8 tests, PR +
  merge.
- **Re-measurement**: ~10 minutes — re-run both scans, update
  findings/retrospective.

Total across all three passes: ~70 minutes. Less than round-13's
30-minute prediction-only outing (per pre-repo-consolidation
notes) and produces shipped linter slices plus validated adopter
evidence.

## Policy notes

- **Re-measurement overwrites the findings doc in place.** Per
  the road-test plan's "latest measurement only" rule — git
  history is the audit trail. Worked cleanly here; no adopter
  confusion about which numbers are current.
- **Macro-form exercise was worth doing cheaply.** Confirmed
  attribute-form recognition without needing a purpose-built
  sample. One helper, one call site, one `import`. Template-able
  for future rounds.
- **Slice-then-remeasure feedback loop is fast.** PR #13 was
  scoped so tightly (4 test files modified, no architecture
  changes) that it shipped same-session as the measurement that
  motivated it. Worth preserving that tempo.

## Data committed

- `docs/hummingbird-examples/trial-scope.md`
- `docs/hummingbird-examples/trial-findings.md` — updated
- `docs/hummingbird-examples/trial-retrospective.md` — this document
- `docs/hummingbird-examples/macro-form-supplement.md`
- `docs/hummingbird-examples/trial-transcripts/replayable.txt`
- `docs/hummingbird-examples/trial-transcripts/strict-replayable.txt`
- `docs/hummingbird-examples/trial-transcripts/macro-form-attribute.txt`
- `docs/hummingbird-examples/trial-transcripts/macro-form-doccomment.txt`

Adopter-side edits remain on the `trial-fluent-verify` branch
of `hummingbird-examples`, local-only.
