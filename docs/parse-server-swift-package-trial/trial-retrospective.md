# parse-server-swift — trial retrospective

## Did the scope hold?

Yes. Source change envelope held: one
`/// @lint.context replayable` doc-comment line on
`exampleRoutes`, plus a non-contribution README banner. No logic
edits. Audit cap held: Run A had nothing to audit (0 fires); Run
B was decomposed by cluster (49 > 30, follows the cap rule). No
SQL ground-truth pass needed (no DB-write callees).

Trial fork is `Joseph-Cursio/parse-server-swift-idempotency-trial`,
default branch `trial-parse`, hardened.

## Pre-committed questions

### 1. Run A yield matches prediction?

**Yes.** Predicted 0 catches across 9 handlers; got 0. The
awslabs-shape pattern reproduces cleanly on Parse: demo-shaped
handler bodies don't exercise the failure modes the linter is
built to find. Confirmed silence on the `Date()` value-
construction in `beforeFind` (line 146-149) is a small positive-
control signal — the inferrer recognized non-equality `Date()`
as pure value construction, didn't fire the
`tuple-equality-with-unstable-components` rule.

### 2. Annotation pattern ergonomics

**Works correctly on the single-`exampleRoutes` shape.** The
single `/// @lint.context replayable` line on `exampleRoutes`'s
`func` decl propagated to all 9 inline trailing closures within;
all 9 closures are in scope under the same context. This
confirms the road_test_plan §103-117 pattern works for the
single-helper-with-many-closures shape, not just the multi-helper
case (prospero) confirmed previously.

### 3. ParseSwift framework-whitelist cluster shape

**24 fires, three sub-shapes.** Composition:

- Value-typed initializers (17): `ParseHookResponse` ×11,
  `ParseError` ×4, `GameScore` ×2 — all should classify as
  idempotent.
- Query reads (4): `findAll` ×2, `information` ×1, `options` ×1
  — should classify as idempotent (read effects).
- User-read helper (3): `hydrateUser` — should classify as
  idempotent.

This is the inaugural ParseSwift evidence. A whitelist addition
is feasible but **not justified at 1-adopter** per the
methodology's "resist 1-adopter ships" rule. Park the
ParseSwift cluster at 1-adopter; revisit if a second Parse
adopter surfaces.

### 4. Retry-semantics documentation gap

**Confirmed.** No authoritative source documents parse-server's
hook retry behavior on 5xx:

- `parse-server-swift` README: silent on retry semantics.
- `parse-server-swift` DocC tutorials: silent.
- parse-server wiki Cloud-Code-Hooks page: failed to load via
  WebFetch (visible page-error placeholders, not loadable
  content).
- parse-server `cloudcode/guide/`: content truncated; the loaded
  portion did not address retry.

The default inference (from common knowledge of parse-server's
HTTP `request`-based hook calls) is that parse-server does *not*
retry hook 5xx — making `@lint.context once` (single-delivery)
arguably the right tier, not `replayable` (at-least-once).

This round used `replayable` as scoped, on the conservative
reading that *clients* may retry the operation that triggered
the hook (e.g. a Parse SDK client calling `save()` again after a
timeout) → the hook fires twice. That's at-least-once from the
hook's perspective, even if parse-server doesn't itself retry.

This subtlety is **the round's most useful methodology
finding**: Parse hook adopters need to think about *which retry
loop they're modeling* — server-side parse-server retry (none)
or client-side application retry (yes). The two require
different `@lint.context` tiers, and the package documentation
doesn't disambiguate.

## Counterfactuals

- **If a write-bearing Parse handler had been in scope**, Run A
  would have produced ≥1 catch (typical `try await
  someObject.save()` → non-idempotent inferred from `save`
  callee name). The round's 0-yield is a property of the demo
  corpus, not of the linter's Parse coverage.
- **If parse-server's hook retry behavior were documented**, the
  scope's `@lint.context replayable` choice would either be
  validated (server retries) or replaced with `once` (server
  does not). This would shift a future write-bearing Parse round
  from "we picked `replayable`" to "we picked the documented
  tier".
- **If a Vapor whitelist addition for `req.headers.first` had
  been pre-shipped**, the `checkHeaders` cluster (10 fires)
  would collapse to 0 by re-enabling helper body inference. Run
  B's 49 → 39, decomposed across two clusters instead of three.
  Useful as evidence for Vapor whitelist priorities even though
  not slice-promotable here.

## Cost summary

- Estimated: ~half a round (zero Run A means audit is brief, no
  SQL pass).
- Actual: roughly tracking estimate. The recon pass took longer
  than usual because the package's example-shape was not
  immediately obvious from `Sources/` listing — required reading
  `routes.swift` end-to-end + the README to confirm "this is a
  template, not an in-production server". Pre-flight cost ~15
  minutes; scope/scan/findings ~30 minutes.
- One small friction: `WebFetch` could not load parse-server's
  Cloud-Code-Hooks wiki page (visible page-load errors). Did not
  pursue further; the documentation-gap finding stands on the
  visible-evidence portion.

## Policy notes

**`@lint.context tier choice depends on which retry loop is
modeled, not on which framework hosts the handler.** The
road_test_plan's per-framework annotation guidance currently
maps frameworks to default tiers (Hummingbird → replayable,
Vapor → replayable, AWS Lambda → replayable). Parse complicates
this: the framework hosts the handler, but the *retry loop* is
upstream (Parse SDK clients), and that loop's behavior isn't
parse-server's responsibility.

For Parse handlers specifically, scope docs should commit to
which retry loop justifies the chosen tier. Suggested
annotation:

> Parse hook handlers run in a `@lint.context replayable` tier
> only on the conservative reading that *application clients*
> may retry the operation that fired the hook. parse-server
> itself does not (per documentation gap) retry hooks on 5xx,
> so a hook annotated `replayable` is making a claim about the
> client retry loop, not the server.

This is a small enough refinement that folding it into
`road_test_plan.md` is overkill — recording here as policy
guidance for future Parse-shape rounds.

## Data committed

Under `docs/parse-server-swift-package-trial/`:

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md` — this document.
- `trial-transcripts/replayable.txt` — Run A raw output, 4 lines
  ("No issues found.").
- `trial-transcripts/strict-replayable.txt` — Run B raw output,
  ~110 lines.

Trial fork: `Joseph-Cursio/parse-server-swift-idempotency-trial`,
SHA `dd19da9a`, branch `trial-parse` (default).
