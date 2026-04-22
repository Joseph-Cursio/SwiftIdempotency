# HelloVapor — Trial Retrospective

## Did the scope hold?

Yes. Single-function annotation, single-package scan, audit under
cap on both runs (Run A 5, Run B 25). No linter changes; no
target-source changes beyond annotation + banner + tier flip.
No PR filed.

## Answers to pre-committed questions

See [`trial-findings.md`](trial-findings.md) §"Answers to
pre-committed questions" for detail. All four predictions hit.
Summary:

1. `app.post` fires reproducibly — shape is corpus-independent.
2. `app.get` strict-mode asymmetry reproduces — slot-17 scope
   matches slot 16 at 5 verbs.
3. Acronym save is a correct catch (no `.unique(on:)`). 10-for-10
   macro-surface coverage now.
4. `(app, register)` sibling-pair evidence at 1-adopter. Defer.

## What would have changed the outcome

- **Had HelloVapor used `RouteCollection` method-ref binding** (like try-swift-tokyo,
  HomeAutomation, Digital-Footprint-Tracker, swift-ap-relay from
  the scout), the `app.get/post` registration site noise would be
  zero — slot-17 evidence would have been single-adopter
  (luka-vapor only). HelloVapor's inline-closure shape was the
  load-bearing property.
- **Had `CreateAcronym` declared `.unique(on: "short")`**, the
  Fluent `save` catch would have flipped to defensible-by-design
  — 9-for-10 not 10-for-10 macro coverage. The absence of the
  unique constraint is genuinely an adopter oversight; this
  would be a clean PR to the upstream if engaged.
- **Had the 4 `register` fires not triggered** (e.g. slot 13 not
  shipped), the sibling-pair `(app, register)` candidate wouldn't
  exist and `register(collection:)` would have been silent —
  removing one deferred candidate from the post-round tracker.

## Cost summary

Estimated: ≤ 1 session. Actual: ~20 minutes from fork to findings
commit. Short round — small corpus, small annotation surface,
clear prediction set.

## Policy notes

Three items land cleanly from this round:

### Slot-17 scope calibration: match slot 16 at 5 verbs

luka-vapor findings initially framed slot 17 as 4-verb scope
(`post|put|patch|delete`) because `app.get` was silent under
replayable. HelloVapor's strict-mode evidence (5× `app.get`
fires) corrects this: slot 17 needs the same 5-verb scope as
slot 16. Whitelist entries silence under both tiers; the
replayable vs. strict asymmetry is a property of the heuristic
path, not of whether the entry is needed.

**Fold-back:** Update luka-vapor `trial-findings.md` §"Slot-17
evidence" to reflect 5-verb scope. Re-check analogous earlier
asymmetry claims (Hummingbird's shape is 5-verb by the same
slot-16 reasoning).

### 2-adopter bar: shape consistency, not fire volume

HelloVapor contributed 1 replayable fire + 5 strict fires vs.
luka-vapor's 2 replayable + 1 strict. Asymmetric volume; symmetric
shape. The 2-adopter bar for ship-eligibility is about shape
consistency across independent corpora, not matching fire counts.
This aligns with slot 16's prospero (9) + open-telemetry (3)
ratio — unequal volume, identical shape.

### Controller-scaffolding adopters count as real adopters

HelloVapor is a small tutorial-scaffolding project (Chinese
comments, "HelloVapor" name, 0 stars, Modules/ImageGenerator
suggesting the author is exploring Vapor beyond tutorial scope).
It still surfaced a real-bug catch (Acronym missing unique
constraint). Small-surface-but-real-Fluent-layer adopters can
contribute meaningful evidence without being production-hosted.
Relevant as scout filter: don't exclude small repos from adopter
pool purely on star count if the Swift code is real.

## Data committed

- `docs/hellovapor/trial-scope.md`
- `docs/hellovapor/trial-findings.md`
- `docs/hellovapor/trial-retrospective.md`
- `docs/hellovapor/trial-transcripts/replayable.txt`
- `docs/hellovapor/trial-transcripts/strict-replayable.txt`

Fork state (on `Joseph-Cursio/HelloVapor-idempotency-trial`):
- `trial-hellovapor` branch at `4b2bea2` (Run B tip,
  strict_replayable). `05e5433` is Run A tip.
- Default branch switched to `trial-hellovapor`.
- Fork hardened per recipe.
