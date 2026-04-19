# Round 11 Trial Retrospective

One page. Third-corpus yield measurement. PR #7 unlocked Vapor's closure-handler surface; round 11 is the first measurement of what happens when the new grammar meets real Vapor routes.

## Did the scope hold?

**Yes, tightly.** Six annotations, two scans, half-hour of work. No in-trial fixes, no linter edits. The round's output is three data points: baseline count, annotated count, and a per-handler audit.

## Answers to the three pre-committed questions

### (a) Does Vapor's closure-handler yield sit between pointfreeco's and Lambda's?

**Yes, confirmed.** 0.33 catches/annotation. Pointfreeco 0.80, Lambda 0.00. Vapor sits in the middle because its demo routes are a mix of trivial and mutation-shaped handlers — neither the all-external-side-effect shape of webhook code nor the all-compute-and-return shape of Lambda handlers.

The cross-corpus picture now:

- **Heavy-mutation surface → 0.80-1.00 yield.** Webhook handlers, ORM wrappers, event publishers.
- **Heavy-compute surface → 0.00 yield.** Request-response handlers that only compute and return values.
- **Mixed surface → 0.30-0.50 yield.** Typical web demo / documentation code.

Per-annotation yield as a metric is **corpus-structure-dependent**, not a rule-precision metric. Precision is what Run A measures (still 0/0 across all three corpora).

### (b) Which missed catches point at heuristic whitelist gaps worth filling?

**Two:** `stop` and `destroy`. Both are short, unambiguous destructive verbs that the existing `HeuristicEffectInferrer.nonIdempotentNames` set doesn't cover. Adding them is a 2-line change + 2 test fixtures. Worth the micro-slice.

A third near-miss: `req.session.data["name"] = ...` is a subscript assignment, which isn't a method call and therefore isn't reachable by any heuristic whose dispatch is on `FunctionCallExprSyntax`. Flagging subscript assignments would need a new mechanism (dispatch on `AssignmentExprSyntax` with a SubscriptExpr left-hand side). Larger slice; not obviously worth it until an adopter asks.

### (c) Does anything in the trailing-closure diagnostic prose read poorly?

**Mildly.** The `'closure'` caller label is terse. Two refinements possible:

- `'closure at line 61'` — explicit positional. Simple but slightly redundant with the file:line already shown.
- `'closure passed to post'` — introspect the enclosing call's method name. More informative ("the closure you passed to `post` is the one the rule's flagging") but requires the visitor to walk to the enclosing `FunctionCallExprSyntax` during site construction.

Neither blocks adoption. Cosmetic.

## Cost summary

- **Estimated:** 0.5 day.
- **Actual:** ~20 minutes of model time. Identical to round 10's cost-per-measurement-round profile.
- **Biggest time sink:** picking handlers to annotate. Ten or so candidates in `routes.swift`; narrowing to six representative shapes took a few minutes of read.

## What would have changed the outcome

- **Broader annotation campaign.** Six annotations is a thin sample. Ten, fifteen, or the full routes file would produce more stable yield numbers. The budget didn't allow; a future "measure Vapor at scale" slice could ship a 30-handler campaign.
- **A handler file from an actual Vapor application, not the framework's demo.** `Development/routes.swift` is Vapor's integration-test surface, not adopter code. A real controller file — payment processors, order creators, email senders — would produce pointfreeco-band yields, not Lambda-band.

## Policy notes

- **Per-annotation yield is now a two-data-point metric per corpus.** Lambda round 6 = 0.00 at 9 annotations. Vapor round 11 = 0.33 at 6 annotations. Cross-corpus yield comparison is more defensible with ≥5 annotations per corpus; round 10's single-annotation yield is noise.
- **PR #7 unlocked a meaningful surface.** Round 10 had 1 annotatable function. Round 11 had 6 annotatable closures + 1 function. 7x increase in reachable annotation surface on the same file. The "closure handlers are ungrammatical" finding from round 6 was a real adoption ceiling; removing it was a worthwhile slice.
- **PR #6 chained-logger fix held up under a second corpus-level campaign.** `request.logger.debug(...)` across the middleware + `req.session.data` accesses in session handlers all stayed silent without user intervention.

## Net output after eleven rounds

- **Rounds 1-6:** linter precision across two corpora.
- **Round 7:** macros-package integration (one mechanism deferred).
- **Round 8:** deferred mechanism closed.
- **Round 9:** `strict_replayable` + two bug fixes.
- **PR #6:** chained-logger heuristic.
- **Round 10:** third-corpus validation, 1 annotation.
- **PR #7:** closure-handler grammar extension.
- **Round 11:** third-corpus re-measurement with closure grammar, 6 annotations.

Three-corpus, multi-annotation yield evidence now exists. Cross-corpus yield variance is understood and traced to handler-shape composition, not rule imprecision.

## Recommended path after round 11

Three directions, ordered:

1. **Heuristic whitelist: add `stop` and `destroy`.** ~1-2 hours. Closes round 11's named gap. Two-line code change + two test fixtures. Low-risk, adopter-visible.
2. **Framework whitelist mechanism** (deferred twice now). Still a valid 1-2 day slice. Would reduce round-9 Lambda noise from 16 → ~8-10 on library-mediated handlers. Now the slice most likely to change adopter experience at the "library-heavy corpus" edge.
3. **Find an adopter application, or run a broader Vapor campaign (30-handler scale).** Still the rate-limiting step for deeper validation.

My pick: **ship (1) and (2) as one PR** (they're in the same file and have similar shape) or **(1) alone as a same-day slice**. The `stop`/`destroy` addition pays for itself immediately in round 11's own data; the framework-whitelist is the larger but still-cheap piece that follows.

If forced to pick one: **(1)**. Smallest slice, immediate yield improvement, benefits every future corpus.

## Data committed

- `docs/phase2-round-11/trial-scope.md` — this trial's contract
- `docs/phase2-round-11/trial-findings.md` — per-annotation audit and cross-corpus yield table
- `docs/phase2-round-11/trial-retrospective.md` — this document
- `docs/phase2-round-11/trial-transcripts/run-A.txt` — bare Vapor baseline
- `docs/phase2-round-11/trial-transcripts/run-E.txt` — 6-annotation scan

No linter changes, no macros changes. Annotations applied in Vapor `trial-round-10` branch in-place, then `git stash`ed. Pure measurement round.
