# Round 11 Trial Scope

Follow-on to round 10. Scope-narrow measurement of the closure-handler grammar extension (PR #7) against the same Vapor corpus, this time exercising the new capability: annotating closure-based handlers directly.

## Research question

> "With closure-handler annotation now grammatical, what per-annotation yield does Vapor produce across a handful of varied handlers — and does the mid-range yield (between pointfreeco's 0.80 and Lambda's 0.00) match the 'business-app-shape' hypothesis from round 10?"

## Pinned context

- **Linter:** `main` at `cdc34e0` (post-PR-7 tip with closure-handler grammar).
- **Target:** `vapor/vapor @ 4.118.0`. Reused from round 10.
- **Annotation targets (6):** 5 closure-based route handlers from `Sources/Development/routes.swift` + 1 middleware function carried over from round 10.

## Annotation plan

Five newly-annotatable closure handlers spanning different shapes:

1. `app.on(.GET, "ping") { req -> StaticString in "123" }` — trivial idempotent-by-body
2. `app.post("login") { req in decode(Creds.self); ... }` — content-decoding (exercises 5-hop inference from round 10)
3. `app.get("shutdown") { req in running.stop(); ... }` — lifecycle mutation
4. `sessions.get("set", ":value") { req in req.session.data["name"] = ... }` — session write
5. `sessions.get("del") { req in req.session.destroy(); ... }` — session destruction

Plus the round-10 baseline kept intact for continuity:

6. `TestAsyncMiddleware.respond(to:chainingTo:)` — middleware delegation

All six annotated `@lint.context replayable`. No other source edits. Same throwaway branch `trial-round-10`; not pushed.

## Scope commitment

- **Measurement only.** No linter changes this round.
- **Six annotations, one scan.** No campaign beyond that — the purpose is per-annotation yield, not adoption-at-scale.
- **Per-diagnostic audit and per-missed-catch verdict.** Handlers that DON'T produce diagnostics get categorised: silent-by-correctness (truly idempotent), silent-by-heuristic-gap (would fire if the heuristic recognised the verb), silent-by-scope (external-library callee outside the project's inferability).

## Pre-committed questions for the retrospective

1. Does Vapor's closure-handler yield sit between pointfreeco's and Lambda's, as the business-app-shape hypothesis predicts?
2. Which missed catches point at heuristic whitelist gaps worth filling as a micro-slice?
3. Is there anything in the diagnostic prose on trailing-closure sites that reads poorly and should be refined?
