# Prospero — Trial Retrospective

## Scope audit

Scope held. 4 files edited (README + 3 `Routes/*.swift`), under
the ≤ 5 ceiling. No logic edits. Annotations placed on the
enclosing `addXRoutes` registration functions rather than
individual handlers (necessary given Prospero's trailing-closure
handler shape — see Q2 below).

Two-tier scan ran on merge-tip `2fbb171`. Transcripts captured.
Audit: Run A (10) fully audited; Run B (62) cluster-decomposed.

## Pre-committed question answers

### Q1: Does Hummingbird's `040f186` framework whitelist cover Prospero's call surface?

**No — but not because of a gap. The whitelist targets a
different shape.** `040f186` (and the subsequent slot 10 Lambda
response-writer slice) added receiver-method whitelist entries
for `handle`/`run`-style application entrypoints. Prospero's
handler surface is `router.get/post { ... }` trailing closures,
which is a fundamentally different shape — it's the Hummingbird
routing DSL, not the application/service lifecycle. The
`040f186` whitelist neither helps nor hurts here; it's orthogonal.

The new cluster this round surfaced (14 Run B fires on
`router.get/post`) argues for a **separate** framework whitelist
slice (slot 16 candidate), not an extension of 040f186.

### Q2: Does the enclosing-function annotation workaround work?

**Yes — the key usability finding of this round.** Annotating
`addPatternRoutes(to router:, ...)` with `/// @lint.context replayable`
causes the linter to walk into all 7 trailing-closure handlers
registered inside it, producing diagnostics on their internal
calls. 9 diagnostics emerged from the single annotation on the
pre-flight probe scan.

This **disconfirms** the prediction in
[`ideas/inline-trailing-closure-annotation-gap.md`](../ideas/inline-trailing-closure-annotation-gap.md)
that non-Lambda corpora with the trailing-closure shape would be
"unlikely". Hummingbird's routing DSL is pervasive inline-
trailing-closure. **But** the same idea doc's severity
assessment — that this gap is adoption-blocking — is also
disconfirmed: the enclosing-function workaround is good enough
for coarse-grained annotation.

Caveats (fold into the idea doc):
- **Coarse-grained only.** All closures inside the annotated
  function share the same tier. Adopters wanting per-route tier
  differentiation (e.g. `replayable` POSTs + `observational`
  GET health-checks in one registrar) would need to split into
  separate `addXRoutes` helpers or refactor to named handlers.
- **Body-walk diagnostics aren't trailing-closure-aware in their
  *explanation*.** The linter says "`addPatternRoutes` calls
  `pattern.save`", which is accurate at the call-graph level but
  glosses over the fact that `pattern.save` lives inside a
  trailing closure that only runs on HTTP POST requests. Adopter
  reading diagnostics needs to map the line number to find the
  relevant closure. Not a blocker, just a UX note.

### Q3: Is there a real-bug shape?

**Yes — 1 catch, 7-for-7 shape coverage maintained.**
`ActivityPattern.save` in POST /patterns (create) fires because
the Migration defines no unique constraint on the natural key.
The adopter's one-user UI means the practical severity is low
(user sees two copies of their just-created pattern), but the
**shape is textbook `IdempotencyKey` / `@ExternallyIdempotent(by:)`
material** — identical to isowords' `insertSharedGame` catch and
Penny's `createCoinEntry` catches.

Fix paths, in order of invasiveness:
1. **Migration layer**: add `.unique(on: "user_id", "name")` to
   a new `AddActivityPatternUniqueConstraint` migration.
   Requires rolling over existing patterns (merge duplicates by
   hand, or accept that retry creates dupes until this lands).
2. **Swift layer**: form-level idempotency key (HTML hidden input
   with a UUID generated on form render); `IdempotencyKey(rawValue:)`
   + `@ExternallyIdempotent(by: "idempotencyKey")` on the
   request type; DB-layer dedup by key.
3. **UI workaround**: POST-Redirect-GET pattern already in place,
   so browser back-button won't double-submit — but that only
   covers user-agent retry, not genuine at-least-once replay
   (server restart, proxy retry).

Filing this as an upstream triage issue depends on user
engagement preference (parked in `ideas/` if wanted).

### Q4: Plateau round?

**Yes — advances Completion Criterion #2 to 2/3.** No named
adoption-gap slice added. The slot 16 candidate (Hummingbird
Router DSL whitelist) is one-adopter evidence-accumulating —
same class as slot 14 at its first surfacing, not yet a named
slice.

One more zero-named-slice round satisfies the "adoption-gap
stability" ship criterion.

## Counterfactuals — what would have changed the outcome

- **If the linter didn't walk into trailing closures inside
  annotated functions.** The round would have been a pure
  shape-mismatch finding (no handler-level diagnostics
  possible), and the trailing-closure-annotation-gap idea would
  have been promoted to an urgent active slice. The fact that
  the walk behaviour exists *and works on production code* is a
  quiet but significant validation of the linter's body-walk
  design.
- **If `ActivityPattern` had a unique constraint.** The one real
  catch would be defensible-by-design (like isowords'
  upsert-heavy shapes). Given this adopter's size and phase-2
  shape, the per-round memory's "latent idempotency issues
  survive collective review" prediction would have been a miss
  — but codebase-carefulness did NOT save this adopter, so the
  memory's hypothesis is validated.
- **If Router DSL methods (`get`, `post`, etc.) had been in the
  idempotent-name lexicon.** The 3 Run A false positives on
  `router.post` wouldn't fire; the 11 Run B `router.get` fires
  would be silent. Clean slice, deferred as slot 16 until
  2-adopter evidence accumulates.

## Cost summary

| Activity | Estimated | Actual | Δ |
|---|---|---|---|
| Pre-flight (clone, fork, harden, inventory, probe) | 20 min | ~30 min | +10 min (shape-mismatch investigation + probe scan) |
| Annotate 3 enclosing functions | 5 min | ~5 min | 0 |
| Run A + Run B scans + push cycle | 10 min | ~8 min | −2 min (small corpus, fast scans) |
| SQL ground-truth pass (6 migrations) | 10 min | ~5 min | −5 min (small migration count) |
| Audit + write docs | 50 min | ~55 min | +5 min (extra writeup for trailing-closure idea update) |
| **Total** | **~95 min** | **~105 min** | **+10 min** |

Tiny-corpus rounds are fast. The trailing-closure shape-mismatch
investigation added the only significant overhead; it paid off
as the round's most interesting finding.

## Policy notes

None new. Slot 15 template additions both applied cleanly:

- **SQL ground-truth pass**: executed, produced the definitive
  "no unique constraint on ActivityPattern" finding that
  confirms the real-bug verdict on position 2.
- **git-lfs pre-flight**: prospero has no `.gitattributes`; plain
  clone worked. Not exercised.

**Idea-doc update needed** (handled in the same commit as this
round): update
[`ideas/inline-trailing-closure-annotation-gap.md`](../ideas/inline-trailing-closure-annotation-gap.md)
to:
1. Mark trigger #2 as met (non-Lambda corpus — Hummingbird —
   with inline trailing closures at scale).
2. Add the "enclosing-function annotation walks trailing
   closures" finding, which significantly reduces the adoption-
   blocking severity.
3. Note the caveats (coarse-grained tier, UX of diagnostic line
   numbers).
4. Reclassify the idea from "deferred pending adopter demand" to
   "deferred — workaround viable, but documented".

## Data committed

Under `docs/prospero/`:

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md` (this file)
- `trial-transcripts/replayable.txt` (Run A, 10 diagnostics)
- `trial-transcripts/strict-replayable.txt` (Run B, 62 diagnostics)

Fork: `Joseph-Cursio/prospero-idempotency-trial` (hardened,
default branch `trial-prospero`, README banner present).

Idea-doc update: `ideas/inline-trailing-closure-annotation-gap.md`.
