# hummingbird-examples / todos-fluent — Trial Findings

Current measurement state. Linter at `SwiftProjectLint` main
`040f186` (post-PR #14, the Hummingbird primitive slice). Target
`hummingbird-examples` at `0d0f9bd`, on the `trial-fluent-verify`
branch with three `@lint.context` annotations on
`TodoController.{list,create,deleteId}` plus one adopter helper
`recordAuditEvent` marked `@NonIdempotent` (from the macro-form
supplement).

## Run A — replayable context

**4 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| Handler | Line | Callee | Rule | Source of classification |
|---|---|---|---|---|
| `create` | 60 | `save` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |
| `create` | 63 | `update` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |
| `create` | 64 | `recordAuditEvent` | nonIdempotentInRetryContext | declared `@NonIdempotent` (attribute) |
| `deleteId` | 110 | `delete` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |

Unchanged by PR #14. The Hummingbird slice adds `idempotent`
classifications only — no new diagnostic shape in replayable mode.

## Run B — strict_replayable context

**6 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (4 diagnostics): same `save` / `update` /
`delete` / `recordAuditEvent` catches.

**Strict-only** (2 diagnostics):

| Handler | Line | Callee | Adoption-fix verdict |
|---|---|---|---|
| `create` | 58 | `Todo` | adopter-owned type constructor — adopter should annotate `@Idempotent` on `Todo.init` (no future linter slice will close this) |
| `create` | 65 | `init` | `EditedResponse(.init(...))` — known `.init(...)` member-access form gap. 1/6 here; still below cross-adopter threshold for slicing. |

## Silence accounting — where PR #14 landed

Strict-mode count went from 10 (post-PR-13) to 6 after PR #14:
**4 silences**, matching prediction exactly.

Silenced callees:
- `create:57 HTTPError` (Hummingbird type constructor)
- `create:56 decode` (`request.decode` — Hummingbird primitive pair)
- `deleteId:101 require` (`parameters.require` — Hummingbird primitive pair)
- `deleteId:108 HTTPError` (Hummingbird type constructor, second site)

## Next-slice candidates on this corpus

**None actionable.** The strict-mode residual on todos-fluent
has plateaued at 6:

- 4 catches are intentional non-idempotent classifications
  (real Fluent mutations + the macro-form attribute-declared helper).
  These are correct catches; the adopter's fix is a deduplication
  guard or idempotency key, not a linter change.
- 1 catch is adopter-owned (`Todo()` constructor) — adopter
  responsibility; annotate `@Idempotent` on `Todo.init`.
- 1 catch is the long-running `.init(...)` member-access gap.
  Firing rate on this corpus is 1/6; deferred pending
  cross-adopter evidence.

The **completion criterion** from [`road_test_plan.md`](../road_test_plan.md)
for "adoption-gap stability" requires three consecutive rounds with
zero new named adoption-gap slices. PR #14 closes the slice this
round named. A fresh round on a different adopter is the next move
toward that criterion.
