# pointfreeco — Trial Retrospective

First Vapor-ecosystem adopter round. Notable for being the first
round where the annotated context is **factually retry-exposed**
(Stripe documents its webhook retry schedule) rather than
conceptually retry-exposed.

## Did the scope hold?

**Yes.** Four annotations, two scans, no linter edits, no scope
creep. No cross-module annotation campaign despite the strict-
mode surface's largely-adopter-local shape.

## Answers to the four pre-committed questions

### (a) Did the `send*` prefix heuristic fire correctly?

**Yes, twice directly and twice via body inference.** Two
`sendEmail` sites in `handleFailedPayment` were flagged via the
camelCase prefix match (`send` + uppercase next char). Two more
(`sendGiftEmail`, `sendPastDueEmail`) were flagged via body
inference — the linter traced into each callee's body and
discovered they eventually call `sendEmail`. The 2-hop chain on
`sendGiftEmail` exercises the multi-hop inference machinery.

### (b) What does `fireAndForget { ... }` look like under inference?

The **inner call still fires**; the wrapper does not silence
the catch. That's semantically correct: `fireAndForget` does not
deduplicate retries. All four email-send sites are wrapped in
`fireAndForget` and all four fire. In strict mode, `fireAndForget`
itself also fires as an unannotated callee (4 times).

This means adopters who want to use `fireAndForget` legitimately
need to annotate either the wrapper (as observational if the
intent is "doesn't alter response") or the inner call (as
idempotent if the inner call truly is). **The linter is not
wrong here** — the duplicate-email bug is real under Stripe
retry — but the diagnostic density on a pattern with legitimate
uses is worth noting.

### (c) Did body-based upward inference reach conclusions through the private-helper chain?

**Yes, to a useful depth.** `sendGiftEmail` was classified via
"2-hop chain of un-annotated callees" — the linter descended
into its body, found another un-annotated callee, descended
again, found a non-idempotent call, and propagated the
classification back up. This is the inference feature working
on real Vapor webhook code, not unit fixtures.

`sendPastDueEmail` classified via 1-hop (calls `sendEmail`
directly in its body).

### (d) What do the strict-mode adoption gaps look like?

Decomposes into **adopter-local patterns**, not
framework-generalisable ones:

- 12 HttpPipeline DSL calls (pointfreeco's custom response builder)
- 5 Stripe-hook-specific helpers (pointfreeco-local)
- 4 `fireAndForget` wrappers (pointfreeco's escape pattern)
- 13 residual (DB via swift-dependencies, Prelude helpers, cross-handler calls)

None of these support a linter-side framework whitelist in the
PR #11 / PR #13 / PR #14 shape — pointfreeco is sufficiently
distinct in its architecture that its surface is not shared
with other adopters. See [`trial-findings.md`](trial-findings.md)
for per-cluster fix verdicts.

Two cross-adopter patterns DID surface as potentially slice-worthy:

1. **`update*` prefix for non-Fluent DB surfaces.** pointfreeco's
   `database.updateGiftStatus(...)` and `updateStripeSubscription(...)`
   are genuinely non-idempotent but not caught in replayable mode
   — the Fluent gate (PR #11) doesn't apply (no `import FluentKit`).
   The camelCase prefix-match list excludes `update` specifically
   because of Fluent-motivated ambiguity concerns, but non-Fluent
   adopters see the gap as missing signal.
2. **Escape-wrapper recognition** (`fireAndForget` and cousins).
   The pattern exists across ecosystems under different names;
   a per-framework whitelist of known escape wrappers could
   reduce strict-mode noise without false silencing.

Both are named in the findings doc's "Next-slice candidates"
section. Neither is pointfreeco-specific.

## What would have changed the outcome

- **Scanning scoped to `Sources/PointFree/Webhooks/` only.** The
  current scan runs against 918 files; only 4 produce diagnostics
  because only 4 have annotations. Scan time is ~3 minutes; would
  be ~30 seconds on a scoped path. Not wrong, just wasteful.
  Worth adding a `--scope` flag to the CLI if future pointfreeco
  rounds want per-module measurements.
- **Annotating `removeBetaAccess`.** It's called inside
  `handleFailedPayment` via `fireAndForget`. Its body makes
  GitHub API mutations; annotating it `@NonIdempotent` would
  produce an extra carried catch and exercise cross-handler
  body inference more directly.

## Cost summary

- **Estimated:** 30 minutes per the road-test plan.
- **Actual:** ~35 minutes end-to-end (pre-flight + reset + 4
  annotations + 2 scans + per-diagnostic decomposition + write-up).
- **Biggest time sink:** decomposing 38 strict-mode diagnostics
  into the 4-cluster-plus-residual structure in
  [`trial-findings.md`](trial-findings.md). ~15 minutes of the 35.

## Policy notes

- **First "retry-is-real" adopter round.** Stripe's retry schedule
  is documented; the `replayable` annotation is not hypothetical.
  Future rounds on webhook-receiving adopters carry more weight
  than generic HTTP-handler rounds where "could be retried" is
  notional.
- **Adopter-local vs. framework-shared decomposition matters.**
  todos-fluent's strict-mode surface was 100% framework-shared
  (Hummingbird + FluentKit) and sliced cleanly. pointfreeco's is
  ~70% adopter-local and wouldn't benefit from linter slices.
  The road-test plan's completion criterion #2 ("one adopter per
  framework") isn't a coverage target where every adopter reveals
  a new linter slice — it's a coverage check that the rule suite
  behaves predictably across adopter shapes.
- **The `update*` prefix finding is genuine cross-adopter signal.**
  Non-Fluent database surfaces are common; today's prefix list
  misses them. Worth a focused slice.

## Toward completion criteria

Per [`../road_test_plan.md`](../road_test_plan.md):

- **Framework coverage** (criterion #2) — Vapor ecosystem now
  covered via pointfreeco. todos-fluent covered Hummingbird +
  Fluent earlier. Remaining: SwiftNIO (tier 3 per targets doc;
  probably not adopter-shaped), Point-Free packages themselves
  (TCA / swift-dependencies — but pointfreeco *uses* swift-
  dependencies, so arguably covered).
- **Adoption-gap stability** (criterion #1) — this round named
  **two new cross-adopter slice candidates** (`update*` prefix,
  escape-wrapper recognition). That's non-zero new slice
  candidates, so the three-round-plateau clock restarts here.
- **Macro-form** (criterion #3) — ticked on todos-fluent (supplement);
  not exercised here.

## Data committed

- `docs/pointfreeco/trial-scope.md`
- `docs/pointfreeco/trial-findings.md`
- `docs/pointfreeco/trial-retrospective.md` — this document
- `docs/pointfreeco/trial-transcripts/replayable.txt`
- `docs/pointfreeco/trial-transcripts/strict-replayable.txt`

Adopter-side edits remain on the `trial-vapor-pointfreeco` branch
of `pointfreeco`, local-only.
