# hummingbird-examples / todos-fluent — Trial Findings

## Run A — replayable context

**3 diagnostics / 3 annotated handlers. Yield = 1.00 catches/handler
on non-silent shapes (2/3 handlers produce ≥1 catch; `list` silent
by correctness).**

Transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| Handler | Line | Callee | Rule | Inference reason |
|---|---|---|---|---|
| `create` | 49 | `save` | nonIdempotentInRetryContext | from the FluentKit ORM verb `save` |
| `create` | 52 | `update` | nonIdempotentInRetryContext | from the FluentKit ORM verb `update` |
| `deleteId` | 98 | `delete` | nonIdempotentInRetryContext | from the FluentKit ORM verb `delete` |

Every catch credits the Fluent gate explicitly (the PR #11
`inferenceReason` prose). The bare-name `nonIdempotentNames` path
is structurally unreachable here — these three verbs were deliberately
kept out of the global list; the gate only fires because `TodoController.swift`
imports `FluentKit`.

`list` produces zero diagnostics. Its body (`Todo.query(...).all()`)
has no Fluent mutation verbs; the query-builder reads are not on any
non-idempotent heuristic. Correct silence, matches the pre-commit
prediction.

## Run B — strict_replayable context

**17 diagnostics / 3 annotated handlers. Decomposes into 3 Fluent
catches (unchanged from Run A) + 14 unannotated-callee diagnostics.**

Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

Fluent catches — **carried from Run A**, not new:

| Handler | Line | Callee | Reason |
|---|---|---|---|
| `create` | 49 | `save` | FluentKit ORM verb |
| `create` | 52 | `update` | FluentKit ORM verb |
| `deleteId` | 98 | `delete` | FluentKit ORM verb |

Strict-only diagnostics (`UnannotatedInStrictReplayableContextVisitor`
— fires on any callee whose effect is neither declared nor
inferable):

| Handler | Line | Callee | Adoption-fix verdict |
|---|---|---|---|
| `list` | 35 | `all` | Fluent query-builder read — future Fluent whitelist (idempotent-read) |
| `list` | 35 | `query` | Fluent query-builder entry — future Fluent whitelist (idempotent-read) |
| `list` | 35 | `db` | Fluent `Fluent.db()` accessor — future Fluent whitelist (idempotent) |
| `create` | 45 | `decode` | `request.decode(...)` — receiver not codec-shaped; future Hummingbird whitelist OR codec-heuristic widening |
| `create` | 46 | `HTTPError` | Hummingbird error constructor — future Hummingbird whitelist |
| `create` | 47 | `Todo` | adopter-owned type constructor — adopter should annotate `@Idempotent` |
| `create` | 48 | `db` | Fluent `Fluent.db()` accessor — same as above |
| `create` | 53 | `init` | `EditedResponse(.init(...))` — Hummingbird response; `.init(...)` member-access form gap (known from round-13-era PR #9) |
| `deleteId` | 89 | `require` | `context.parameters.require(...)` — Hummingbird primitive; future whitelist |
| `deleteId` | 90 | `db` | Fluent `Fluent.db()` accessor — same as above |
| `deleteId` | 92 | `query` | Fluent query-builder entry — same as list |
| `deleteId` | 92 | `filter` | Fluent query-builder filter — future Fluent whitelist (idempotent-read) |
| `deleteId` | 92 | `first` | Fluent query-builder terminal read — future Fluent whitelist (idempotent-read) |
| `deleteId` | 96 | `HTTPError` | Hummingbird error constructor — same as above |

Two named adoption-gap clusters, both at ~5-6 catches:

- **Fluent query-builder read whitelist** (closes ~7/14): `db`,
  `query`, `all`, `first`, `filter` — all pure reads on `FluentKit`'s
  `Database` / `QueryBuilder` surface. Gate on `import FluentKit`,
  classification `idempotent`. Same shape as PR #9 / PR #11.
- **Hummingbird primitive whitelist** (closes ~4/14): `HTTPError`,
  `request.decode`, `parameters.require`. Gate on `import Hummingbird`.
  Hummingbird error/decode/route-parameter surface — adopters hit
  these in every handler.

Residual after both hypothetical slices: `.init(...)` member-access
form (~1 catch) and adopter-owned `Todo()` constructor (~1 catch).
The former is the existing PR-#9 known gap; the latter is genuinely
adopter-responsibility.

## Comparison to pre-slice baseline

The nearest comparable measurement before PR #11 shipped was a
zero-yield result on the same three handlers — `replayable` mode
produced `No issues found` because none of `save`/`update`/`delete`
were in `nonIdempotentNames`. Post-PR-11: 3 catches on the same
three annotations, all on the adopter's canonical "duplicate POST
row" bug shape. **The slice fired as designed.**
