# parse-server-swift — trial scope

## Research question

> Do Parse Cloud Code hook handlers need retry-safety annotation,
> given parse-server's undocumented retry behavior on hook 5xx?
> And does the linter produce useful diagnostics on a demo-shaped
> Parse adopter, or only strict-mode residual like the awslabs
> swift-aws-lambda-runtime corpus?

This is the first Parse-shape adopter probe. The shape is
deliberately demo-shaped — `netreconlab/parse-server-swift` is a
template/library hybrid whose `Sources/ParseServerSwift/routes.swift`
(`exampleRoutes`) demonstrates the Parse hook idiom. The handlers
inside it are read-only or log-only, not write-bearing — yield is
predicted to be 0 catches under Run A, matching the awslabs
pattern flagged in `CLAUDE.md`.

## Pinned context

- SwiftIdempotency: `40b4d40` (`docs: retrospective 2026-05-05 —
  correct email-on-retry slice status`).
  - `swift test` clean: 86 tests / 11 suites + 4 known issues.
- SwiftProjectLint: `5397858` (unchanged from earlier today).
  - `swift test` clean: 2410 tests / 295 suites.
- Target upstream: `netreconlab/parse-server-swift` v1.0.2,
  SHA `0f873f1` ("build(deps): bump swift from 6.2.3-noble to
  6.2.4-noble"). Apache-2.0. Active (last release 2026-02-03).
- Trial fork: `Joseph-Cursio/parse-server-swift-idempotency-trial`,
  branch `trial-parse` (default), tip `dd19da9a`.

## Annotation plan

**One annotation, nine handlers in scope.** All 9 handlers are
inline trailing closures inside
`Sources/ParseServerSwift/routes.swift::exampleRoutes(_:)`. Per
road_test_plan §103-117, annotation goes on the *enclosing
registration function*; the inferrer walks the closures within.

| # | Handler | Path | Trigger | Effect shape (predicted) |
|---:|---|---|---|---|
| 1 | `app.get { … }` | `/` | — | view render (observational) |
| 2 | `app.get("foo") { … }` | `/foo` | — | string return (pure) |
| 3 | `app.post("hello", …)` | `/hello` | Cloud Function | `GameScore.query.findAll` (read) + log |
| 4 | `app.post("version", …)` | `/version` | Cloud Function | `ParseServer.information()` (read) + log |
| 5 | `app.post("score", "save", "before", …, .beforeSave)` | hook | beforeSave on GameScore | `findAll` (read) + log |
| 6 | `app.post("score", "find", "before", …, .beforeFind)` | hook | beforeFind on GameScore | in-memory `GameScore` init + log (pure) |
| 7 | `app.post("user", "login", "after", …, .afterLogin)` | hook | afterLogin on User | log only |
| 8 | `app.on("file", "save", "before", …, .beforeSave)` | hook | beforeSave on ParseFile | log only |
| 9 | `app.post("file", "delete", "before", …, .beforeDelete)` | hook | beforeDelete on ParseFile | log only |
| 10 | `app.post("connect", "before", …, .beforeConnect)` | hook | beforeConnect on LiveQuery | log only |
| 11 | `app.post("score", "subscribe", "before", …, .beforeSubscribe)` | hook | beforeSubscribe on GameScore | log only |
| 12 | `app.post("score", "event", "after", …, .afterEvent)` | hook | afterEvent on GameScore | log only |

Yield denominator is 9 handlers (the two `app.get` routes at the
top are non-Parse-shaped Vapor routes; counting them as in-scope
is honest because the annotation reaches them, but they're called
out separately).

## Scope commitment

- **Measurement only.** Source change is one
  `/// @lint.context replayable` doc-comment line on
  `exampleRoutes` plus a README banner.
- **Audit cap: 30 diagnostics.** Run A predicted at 0; Run B
  expected to exceed 30 given dense Vapor + ParseSwift +
  Foundation surface. Strict-only fires decomposed by callee-name
  cluster.
- **No SQL ground-truth pass needed.** No DB-write callees in any
  handler.

## Pre-committed retrospective questions

1. **Run A yield matches prediction?** Predicted 0 catches across
   9 handlers; matches awslabs shape. If non-zero, what shape
   surfaces?
2. **Annotation pattern ergonomics on single-`exampleRoutes`
   shape.** Does the inline-trailing-closure-via-registration-helper
   pattern reach all 9 closures from the single
   `/// @lint.context replayable` on `exampleRoutes`?
3. **ParseSwift framework-whitelist cluster shape.** Run B will
   surface the first ParseSwift cluster — what's its size and
   composition (`ParseHookResponse`, `ParseError`, query methods,
   etc.)?
4. **Retry-semantics documentation gap.** Is parse-server's hook
   retry behavior on 5xx documentable from any authoritative
   source — parse-server wiki, parse-server-swift README,
   parse-server source — or is it the round's finding that
   adopters annotating Parse hooks are making an unverifiable
   judgement call?
