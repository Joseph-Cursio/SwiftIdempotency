# parse-server-swift — trial findings

Transcripts:
[`replayable.txt`](trial-transcripts/replayable.txt) ·
[`strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

All line numbers refer to `Sources/ParseServerSwift/routes.swift`
on the trial branch (fork tip `dd19da9a`).

## Run A — replayable

**0 issues found.** Yield: 0 / 9 = **0.00**. All 9 handlers
silent.

This matches the predicted outcome. Every handler in
`exampleRoutes` is read-only (`GameScore.query.findAll(...)`,
`ParseServer.information()`) or observation-only
(`req.logger.info(...)`); no write-style callees exist. The
linter's body-level inference correctly classifies every closure
as effect-free under `replayable`.

This confirms the awslabs-shape pattern: **demo-shaped corpora
produce zero Run A yield.** The package is a template/library
hybrid where adopters replace `exampleRoutes` with their own
write-bearing handler bodies; the as-shipped contents do not
exercise the failure modes the linter is built to find.

## Run B — strict_replayable

**49 issues, all `Unannotated In Strict Replayable Context`.**
Zero `Non-Idempotent` fires carried from Run A — there are none
to carry. All 49 are strict-only "callee not in framework
whitelist and body inference inconclusive" reports.

Audit cap is 30; per road_test_plan, decomposed by callee-name
cluster instead of per-line.

### Decomposition (49 fires across three clusters)

| Cluster | Count | Sample callees | Verdict |
|---|---:|---|---|
| **ParseSwift framework whitelist gap** | 24 | `ParseHookResponse` ×11, `ParseError` ×4, `hydrateUser` ×3, `GameScore` ×2, `findAll` ×2, `options` ×1, `information` ×1 | adoption gap — first ParseSwift coverage measurement; all are value-typed inits, query reads, or observational helpers |
| **Vapor / Foundation framework whitelist gap** | 13 | `decode` ×10, `Date` ×2, `render` ×1 | adoption gap — same cluster shape as prior Vapor rounds; `req.content.decode` is the dominant fire |
| **Adopter-local helper, body-inference cascade** | 10 | `checkHeaders` ×10 | adoption gap — `checkHeaders` is defined in the same package (`Sources/ParseServerSwift/Utility/Functions.swift:36`) but body inference fails because the helper itself calls `req.headers.first` (Vapor whitelist gap), so uncertainty cascades |
| Misc | 2 | `on`, `init` | adoption gap |

Total: 24 + 13 + 10 + 2 = 49 ✅

### `checkHeaders` cascade — observation worth recording

`checkHeaders` is the round's most fires-per-callee shape (10).
It's the adopter's own helper, defined in the same target as
`exampleRoutes`. Body inference attempts to classify it but
fails: the helper calls `req.headers.first(name:)`, which is
itself in the Vapor whitelist gap. Uncertainty propagates, so
every closure that calls `checkHeaders` registers a fire.

This is **not a new adoption-gap class** — it's the existing
"framework whitelist needs Vapor primitives" gap, amplified by
helper-function indirection. Worth recording because it shows
strict-mode fire counts can multiply when helpers depend on
under-classified primitives. **A single Vapor-side whitelist
addition (`req.headers.first` → idempotent) would collapse the
`checkHeaders` cluster from 10 fires to 0** by re-enabling the
helper's body inference.

### First ParseSwift cluster

This round is the first time the linter has scanned a ParseSwift
adopter. The 24 fires constitute the inaugural ParseSwift
framework-whitelist evidence. By inspection of the callee names,
all fall into already-known categories:

- **Value-typed init**: `ParseHookResponse(...)`, `ParseError(...)`,
  `GameScore(...)` — idempotent by construction.
- **Query read**: `findAll`, `information`, `options` — read
  effects.
- **User read**: `hydrateUser` — fetches the complete user object.

None of these are write-bearing under the surface area scanned.
A ParseSwift whitelist addition is feasible from this single
round but not justified at 1-adopter (per the methodology's
"resist 1-adopter ships" rule).

## Comparison to predicted outcome

The scope doc predicted Run A would be 0 catches. **Confirmed.**
The scope predicted strict mode would surface a new ParseSwift
cluster. **Confirmed**, with size 24 fires.

The scope predicted Run A might still surface something — it did
not. The closest call was `Date()` initialization in `beforeFind`
(line 146-149), which the linter correctly recognized as a
*value-construction* `Date()` call (not `Date()` in tuple-equality
position, which is the `tuple-equality-with-unstable-components`
rule's target). Correct silence on that shape is itself a small
positive-control signal.

## Retry-semantics documentation gap

The fourth pre-committed question is answered in the
retrospective. Summary: **no authoritative documentation states
parse-server's retry behavior on hook 5xx**. Searched: this
package's README + DocC tutorials, parse-server's wiki home page
(linked Cloud-Code-Hooks page failed to load via WebFetch),
parse-server's `cloudcode/guide/` page (content truncated). The
typical inference is that parse-server uses HTTP `request`
without explicit retry — but this is *inferred*, not documented.

Adopters annotating Parse hooks as `@lint.context replayable` are
therefore doing so on an *unverifiable judgement call*. This
matters for the linter's correctness story: if parse-server
*doesn't* retry on hook 5xx, then `replayable` is the wrong
context — the right tier is `once` (no retry, single delivery).
The choice doesn't affect this round's results (0 Run A
catches), but it would matter on a write-bearing Parse
adopter.

## Yield

- Including silent: **0 catches / 9 handlers = 0.00**.
- Excluding silent: undefined (zero non-silent handlers).

Lowest yield to date — same as round 15 (graphiti). The two
zero-yield rounds in this series (graphiti, parse) have a common
cause: handler bodies that the linter correctly classifies as
effect-free or pure under `replayable`. graphiti was DSL-binding
opacity; parse is demo-shaped read/log handlers. Different
mechanism, same result.
