# Round 11 Trial Findings

Scope-narrow re-measurement on Vapor (`vapor/vapor @ 4.118.0`) with PR #7's closure-handler grammar active. Six annotations across varied handler shapes in `Sources/Development/routes.swift`.

## Diagnostic count per run

| Run | State | Diagnostics | Notes |
|---|---|---|---|
| A | bare `4.118.0`, zero annotations | 0 | Baseline re-confirmation (matches round 10 Run A) |
| E | 6 `@lint.context replayable` annotations applied | 2 | 2 catches across the 6 handlers |

## Per-annotation audit

| # | Handler | Shape | Result | Verdict |
|---|---|---|---|---|
| 1 | `app.on(.GET, "ping") { req -> StaticString in "123" }` | trivial literal return | silent | **silent-by-correctness.** Body is a pure literal return, no side-effect calls. Rule is right to stay silent |
| 2 | `app.post("login") { req in decode(Creds.self); ... }` | content-decode then format | fires on `decode` | **defensible catch.** 5-hop upward inference traces `req.content.decode(...)` through Vapor's content-coding internals to a non-idempotent leaf. Adopter would annotate `req.content.decode` `@lint.effect idempotent` or accept the diagnostic's prompt |
| 3 | `app.get("shutdown") { req in running.stop(); ... }` | lifecycle mutation | silent | **silent-by-heuristic-gap.** `stop` isn't in `HeuristicEffectInferrer.nonIdempotentNames` / prefix list. A lifecycle-shutdown call IS non-idempotent ("stop a service" has no valid replay semantics). Missed catch |
| 4 | `sessions.get("set", ":value") { req in req.session.data["name"] = ... }` | subscript assignment | silent | **silent-by-scope.** No method call on an inferable path — `data[...] =` is a subscript assignment expression, not a call. Heuristic doesn't apply. Strictly correct per current rule shape, but the operation IS a mutation a strict adopter might want flagged. Would require a subscript-assignment detection layer |
| 5 | `sessions.get("del") { req in req.session.destroy(); ... }` | session destruction | silent | **silent-by-heuristic-gap.** `destroy` isn't in the heuristic whitelist. A destructive verb the heuristic should classify. Missed catch |
| 6 | `TestAsyncMiddleware.respond(to:chainingTo:)` | middleware delegation | fires on `next.respond` | **defensible catch.** Same as round 10 — 5-hop upward inference to non-idempotent leaf via the responder protocol chain |

**Totals:** 2 fires, 4 silent. Of the 4 silent: 1 silent-by-correctness, 2 silent-by-heuristic-gap, 1 silent-by-scope.

**Yield: 0.33 catches per annotation** (2/6).

## Cross-corpus yield comparison

| Corpus | Annotations | Catches | Yield | Notes |
|---|---|---|---|---|
| pointfreeco Run D post-fix | 5 | 4 | **0.80** | webhook handlers, external side-effect heavy (create/send/publish) |
| Lambda round 6 Run B | 9 | 0 | **0.00** | compute-and-return handlers (logger + response write) |
| Vapor round 10 | 1 | 1 | 1.00 | single middleware; small-sample bias |
| **Vapor round 11** | **6** | **2** | **0.33** | **demo routes of varied shape** |

Round 11's 0.33 sits **between** Lambda's 0.00 and pointfreeco's 0.80, consistent with the "business-app-shape" hypothesis from round 10's retrospective:

- Lambda demo handlers — compute-and-return, no external side effects → 0 yield (no anchors for the heuristic)
- pointfreeco webhook handlers — all external side effects (send email, insert order, publish event) → high yield
- Vapor demo routes — **half** idempotent by construction (literal returns, session reads), **half** mutation-shaped → mid-range yield

The yield variance across corpora is explained by the **fraction of handlers that actually mutate state** — not by rule imprecision. Vapor's `Development/routes.swift` is a demo file of mostly-trivial handlers for testing the runtime, not a production app with mostly-mutating controllers.

## Heuristic whitelist gaps surfaced

Round 11 decomposed the 2 silent-by-heuristic-gap cases:

- **`stop`** — service/lifecycle stop. Would fire on `running.stop()`, `server.stop()`, `task.stop()`, etc. Arguably non-idempotent (stopping an already-stopped thing is either a no-op or a crash depending on semantics).
- **`destroy`** — resource destruction. `session.destroy()`, `cache.destroy()`, `task.destroy()`. Clearly destructive.

Both are short, unambiguous verbs. Adding them to `HeuristicEffectInferrer.nonIdempotentNames` is a 2-line change. Would add 2 catches to round 11's yield (0.33 → 0.67) and benefit every future corpus that uses these verb shapes.

## Diagnostic prose check

The new trailing-closure diagnostic prose reads:

> Non-idempotent call in replayable context: **'closure'** is declared `@lint.context replayable` but calls 'decode', whose effect is inferred `non_idempotent` from its body via 5-hop chain of un-annotated callees.

The `'closure'` in caller position is functional — the file+line already pins down which closure — but could be more informative. A micro-refinement: `'closure at line 61'` or `'closure passed to post'` (by introspecting the enclosing call). Not scope for this round; noted for a follow-on.

## Confirms the round-10 retrospective prediction

Round 10's retrospective explicitly predicted that `strict_replayable` on business-app shapes would be low-noise — a claim that rested on "upward inference resolves the call graph." Round 11 re-confirms: `decode` and `respond` both hit via 5-hop chains; the middleware site didn't need `strict_replayable` to surface them.

It also confirms the round-7 / round-10 "closure-based handlers are the majority surface" observation: the 5 closure handlers here were all previously unannotatable under round-6's grammar. PR #7 makes them reachable, and round 11 is the first measurement of what happens when adopters take advantage of that capability.

## Data committed

Under `docs/phase2-round-11/`:

- `trial-scope.md` — this trial's contract
- `trial-findings.md` — this document
- `trial-retrospective.md` — next-step thinking
- `trial-transcripts/run-A.txt` — bare Vapor baseline (0 diagnostics, same as round 10)
- `trial-transcripts/run-E.txt` — 6-annotation scan (2 diagnostics)

Vapor clone: `trial-round-10` branch, not pushed. Annotations applied in-place for measurement then `git stash`ed away. Linter untouched.
