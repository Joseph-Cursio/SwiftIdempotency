# hummingbird-examples / todos-fluent — Trial Findings

Current measurement state. Linter at `SwiftProjectLint` main
`d85e5dc` (post-PR #13, the Fluent query-builder idempotent-read
slice). Target `hummingbird-examples` at `0d0f9bd`, on the
`trial-fluent-verify` branch with three `@lint.context replayable`
doc-comments on `TodoController.{list,create,deleteId}` plus one
adopter helper `recordAuditEvent` marked `@NonIdempotent` (from
the macro-form supplement).

## Run A — replayable context

**4 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| Handler | Line | Callee | Rule | Source of classification |
|---|---|---|---|---|
| `create` | 60 | `save` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |
| `create` | 63 | `update` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |
| `create` | 64 | `recordAuditEvent` | nonIdempotentInRetryContext | declared `@NonIdempotent` (attribute) |
| `deleteId` | 110 | `delete` | nonIdempotentInRetryContext | inferred — FluentKit ORM verb |

`list` produces zero diagnostics (Fluent reads under the
idempotent gate from PR #13; classification is `idempotent` which
is trusted in `replayable` context).

## Run B — strict_replayable context

**10 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (4 diagnostics): same `save` / `update` /
`delete` / `recordAuditEvent` catches as above. Strict mode is
stricter, not different.

**Strict-only** (6 diagnostics) — fire from
`UnannotatedInStrictReplayableContextVisitor` on callees whose
effect is neither declared nor inferrable:

| Handler | Line | Callee | Adoption-fix verdict |
|---|---|---|---|
| `create` | 56 | `decode` | `request.decode(...)` — receiver `request` not codec-shaped. Future Hummingbird whitelist or codec-receiver widening. |
| `create` | 57 | `HTTPError` | Hummingbird error constructor — future Hummingbird primitive whitelist. |
| `create` | 58 | `Todo` | adopter-owned type constructor — adopter should annotate `@Idempotent` on `Todo.init`. |
| `create` | 65 | `init` | `EditedResponse(.init(...))` — Hummingbird response; known `.init(...)` member-access form gap. |
| `deleteId` | 101 | `require` | `context.parameters.require(...)` — Hummingbird primitive; future whitelist. |
| `deleteId` | 108 | `HTTPError` | Hummingbird error constructor — same as above. |

## Silence accounting — where PR #13 landed

The strict-mode diagnostic count went from 17 (pre-PR-13, per git
history) plus 1 (the `@NonIdempotent` helper added in the macro-form
supplement) = 18 expected pre-slice, down to 10 post-slice. **8
diagnostics silenced** by the Fluent query-builder read whitelist.

Silenced callees, by handler:

- `list` — 3 (all `all`, `query`, `db`)
- `create` — 1 (`db`)
- `deleteId` — 4 (`db`, `query`, `filter`, `first`)

All 5 verbs in the PR #13 whitelist (`db`, `query`, `all`, `first`,
`filter`) fired in at least one position on this corpus. Predicted
silence was ~7; actual 8 (the `create` handler's `db` catch
wasn't itemised in the pre-slice decomposition).

## Next-slice candidates on this corpus

Two remaining clusters in Run B's residual, with firing rates:

1. **Hummingbird primitives** (3/10): `HTTPError` x2 + `require` x1.
   A modest framework whitelist similar in shape to PR #11 / PR #13.
2. **Codec-receiver widening OR Hummingbird request.decode** (1/10):
   `request.decode` fails the codec-receiver shape check because
   `request` doesn't contain "decoder" / "encoder". Two slice
   options: (a) widen the codec-receiver matcher to accept
   `request`-shaped receivers when `Hummingbird` is imported, or
   (b) add `decode` to a Hummingbird method whitelist.
3. **`.init(...)` member-access form** (1/10): `EditedResponse(...)`
   construction. Known gap; 1/10 on this corpus matches the 1/17
   rate observed pre-slice. Cross-adopter evidence still needed
   before slicing.

Truly adopter-responsibility (1/10): the `Todo()` constructor on
line 58. The adopter's own type; fix is an `@Idempotent`
annotation on `Todo.init`, not a linter whitelist.
