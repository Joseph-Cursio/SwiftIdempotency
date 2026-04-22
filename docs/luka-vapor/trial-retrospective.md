# luka-vapor — Trial Retrospective

## Did the scope hold?

Yes. Single-function annotation, single-package scan, audit
**partially** kept under cap (Run A 4 ≤ 30; Run B 52 > 30 →
decomposed by cluster per plan). No linter changes; no
target-source changes beyond the annotation + banner + tier flip.

## Answers to pre-committed questions

See [`trial-findings.md`](trial-findings.md) §"Answers to
pre-committed questions" for detail. Summary:

1. **Slot-17 fire shape** — bare-name `post` heuristic, receiver-
   agnostic. Slot-17 whitelist follows slot-16's pattern.
2. **`app.get` symmetry** — silent. Slot-17 scope is 4 verbs.
3. **Real-bug catches** — 1 confirmed (`sendEndEvent`) + 1
   structural note (CAS race). 9-for-9 macro-surface coverage.
4. **NIO `.get()` cluster** — 9 fires surfaced; 1-adopter
   candidate, defer.

## What would have changed the outcome

- **Had luka-vapor used post-async-await Redis idioms** (e.g.
  swift-nio-redis's async-await wrapper, or bridged via
  `NIOAsync`-style), the 9 `EventLoopFuture.get()` fires would
  have collapsed to a `(_, `) noop — likely reducing Run B from
  52 to ~43. The scope doc would have matched actual at
  "20-40 strict-only" range exactly.
- **Had `app.get` fired** (e.g. under a stricter prefix-lexicon
  extension of slot 13), slot-17 scope would have matched slot 16
  at 5 verbs. Current asymmetry is actually informative — confirms
  prefix-lexicon and framework-whitelist precedence interact
  correctly.
- **Had the adopter used `RouteCollection` binding** (like every
  other Vapor adopter sampled in the scout), slot 17 would have
  had zero shape evidence from this round. The scout-filter
  on "inline-closure shape present" was load-bearing.

## Cost summary

Estimated: 1 session. Actual: < 1 session (fork provision to
findings commit in ~30 minutes elapsed). Smaller than
myfavquotes-api or prospero due to 3-closure scope and absence
of a DB layer requiring SQL ground-truth pass.

## Policy notes

Two items surface that deserve a fold into `road_test_plan.md`:

### Prefix-lexicon asymmetry between frameworks

When a routing DSL uses a receiver whose HTTP-method name matches
an idempotent-by-convention prefix (`get`, `find`, `fetch`), the
registration call is **already silent** under replayable context —
no whitelist entry needed for those verbs. This is a scope-narrowing
effect that distinguishes Vapor (`app.get` silent) from Hummingbird
(`router.get` fires). Slice scopes should be calibrated per-
framework, not copy-pasted from the 5-verb Hummingbird shape.

### Scout-filter gate: handler-binding shape

For DSL-noise validation slices (slots 16, 17, and any future
routing-DSL work), scout output must confirm **inline-trailing-
closure shape present**. Pure `RouteCollection` + method-reference
adopters produce zero DSL-noise fires — the linter classifies the
method body, not the registration call site. Add "confirm inline-
closure shape" as a scout-gate item before committing to a round.

Both items to be folded into `road_test_plan.md` when the slot-17
slice ships; parking them here until 2-adopter evidence lands on
HelloVapor.

## Data committed

- `docs/luka-vapor/trial-scope.md`
- `docs/luka-vapor/trial-findings.md`
- `docs/luka-vapor/trial-retrospective.md`
- `docs/luka-vapor/trial-transcripts/replayable.txt`
- `docs/luka-vapor/trial-transcripts/strict-replayable.txt`

Fork state (on `Joseph-Cursio/luka-vapor-idempotency-trial`):
- `trial-luka-vapor` branch at `f2e5d09` (Run B tip,
  strict_replayable). `d2c9e21` is Run A tip (replayable), still
  reachable via git log.
- Default branch switched to `trial-luka-vapor`.
- Fork hardened per recipe.
