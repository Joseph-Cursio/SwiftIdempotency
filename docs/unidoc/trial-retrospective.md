# Unidoc — Trial Retrospective

Reflective notes after running the eighteenth adopter round. See
[`trial-scope.md`](trial-scope.md) and
[`trial-findings.md`](trial-findings.md) for measurements.

## Did the scope hold?

Mostly yes. Two scope-adjacent observations:

- **Source-edit ceiling held.** 6 doc-comment insertions across 4
  files. No imports, no logic edits.
- **Audit cap held for Run A** (5 < 30); Run B exceeded the cap
  (39 fires) → decomposed into 6 named clusters per the template.
- **Enum-case-pattern false positive surfaced.** Not predicted in
  the scope doc. Surfaced as A1 — a separate linter bug that
  happens to be triggered by switch-dispatch shapes whose case
  names match non-idempotent prefixes. Tracked in findings as a
  1-adopter slice candidate.

## Pre-committed questions

### Q1. Switch-dispatch deep-chain (`load(with:)` silent)

**Hypothesis: NO — `load` silent.** **Actual: MIXED — `load` fires
for the wrong reason.**

`load(with:)` does fire (Run A diagnostic A1), but on the
`case .create(let event):` enum-case-pattern false positive — not
on the deep-chain path through to the `handle(installation:...)`
or `handle(create:...)` calls inside the switch case bodies.

**The slot 23 silent miss IS confirmed** — the correct-cause
deep-chain path is silent. The round produced an incidental fire
from a separate bug (enum-pattern walking).

**With a switch whose case names didn't accidentally match
non-idempotent prefixes** — as in tinyfaces' round 17, where the
switch was on `(event.type, event.data?.object)` with cases
named `.checkoutSessionCompleted`, `.invoice`, `.subscription` —
the dispatcher would be cleanly silent. tinyfaces was the cleaner
test; unidoc is a confirmation with masking.

**Slot 23 promotion: 2-adopter slice-ready.** Filing this
finding back to next_steps.md.

### Q2. Sub-handler direct annotation

**Hypothesis: yes — both fire.** **Actual: yes** (A2, A3, A4).

`handle(installation:at:in:)` fires on `db.users.update` (A2);
`handle(create:at:in:)` fires twice — on `updateWebhook` (A3) and
`insert` (A4). Confirms the inner methods ARE inferred
non-idempotent. The slot 23 gap is purely the upward propagation
through the switch in `load(with:)`.

This is the strongest part of the slot 23 evidence: when the
sub-handlers are directly annotated, the linter's existing
inference machinery correctly identifies the non-idempotent calls.
The walking of those bodies works. What's missing is the
`switch-case-arm → callee` edge.

### Q3. Mongo upsert defensibility

**Hypothesis: linter fires on `upsert`, audit flips to defensible.**
**Actual: linter is silent.**

`db.packageAliases.upsert(alias:of:)` doesn't fire because
`upsert` isn't on the linter's bare-name non-idempotent list. The
semantically-correct answer is "defensible" but the linter
reaches it by not noticing the call, not by emitting + audit.

This is a coverage gap in the heuristic — `upsert` is a
deliberately-idempotent verb, but should the linter fire on it
and let audit silence it, or should it stay silent? Argument
for firing: the prefix-match design pattern would suggest
treating any `upsert*` callee as "looks like a write." Argument
for not firing: the verb is *named* for its idempotency — the
adopter has explicitly chosen the safe operation.

**No action needed** — the linter's current behaviour
(silent on `upsert`) is the right one. Just noting that the audit
methodology has to change for adopters using upsert-aware DB
verbs.

### Q4. Pure-render correctness signal

**Hypothesis: silent.** **Actual: silent** ✓.

`LoginOperation.load(with:)` returns
`.ok(page.resource(format: context.format))` with no DB calls
and no external API calls. Stays silent under replayable —
correctness signal confirmed.

## Counterfactuals — what would have changed the outcome

1. **If unidoc's webhook switch had used different enum case
   names** (e.g. `.installation` matches no prefix; `.create`
   matches the non-idempotent verb list), `load(with:)` would
   have been cleanly silent like tinyfaces. The round would have
   produced 4 catches / 6 handlers (no A1 fire). The slot 23
   evidence would have been stronger because the enum-pattern
   false positive wouldn't have masked the silent-miss. As it
   is, the evidence is still 2-adopter, just slightly noisier.

2. **If `RepoFeed` weren't a capped collection,** A4's verdict
   would be HIGH-impact (unbounded duplicate feed entries) rather
   than low-impact (bounded by the 16-doc cap). The cap is the
   data-layer-design decision that limits the consequence; without
   it, the same retry shape produces an unbounded log.

3. **If GitHub's OAuth API allowed code reuse,** A5's UI
   inconsistency wouldn't surface — both replays would succeed
   identically. The single-use semantics of OAuth codes are what
   create the asymmetric replay shape.

## Cost summary

- **Estimated:** 1.5-2 hours per the road-test template.
- **Actual:** ~1 hour. Mongo data-layer audit was lighter than
  expected because the relevant DB layer (`UnidocDB`) is well-
  organised — finding `Mongo.Upserting` in the upsert path took
  one grep. Capped-collection semantics on `RepoFeed` were
  documented inline (`/// 1 MB ought to be enough for anybody.`).

## Policy notes

1. **Mongo data-layer audit pattern.** The Postgres/Fluent
   `.unique(on:)` shortcut translates to Mongo's
   `static var indexes: [Mongo.CollectionIndex]` and
   `Mongo.Upserting<...>` / `Mongo.FindAndModify<...>` typing.
   The audit methodology is similar but the artefacts are
   different. Worth folding into `road_test_plan.md` §"SQL
   ground-truth pass" so future Mongo adopters get the same
   guidance.

2. **Capped collections need their own audit dimension.**
   `Mongo.CollectionModel.capacity` (`(bytes:, count:)`) bounds
   the impact of duplicate-on-retry — a real bug shape that
   would be high-impact on uncapped collections becomes
   low-impact on capped ones. Worth noting in the road-test
   plan as a Mongo-specific consideration.

3. **Enum-case-pattern false positive.** Not a slot-23 issue;
   a separate linter bug. Cross-cuts independently of the
   webhook-shape evidence. Worth tracking as its own 1-adopter
   slice candidate in `next_steps.md` so a future adopter
   exhibition triggers slice work.

## Data committed

- [`trial-scope.md`](trial-scope.md) — research question, pinned
  context, annotation plan.
- [`trial-findings.md`](trial-findings.md) — Run A per-diagnostic
  table, Run B 6-cluster decomposition, real-bug filing queue,
  slice candidates.
- [`trial-retrospective.md`](trial-retrospective.md) — this file.
- [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt)
  — Run A linter output.
- [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt)
  — Run B linter output.

Trial fork: `Joseph-Cursio/unidoc-idempotency-trial` @
`trial-unidoc` branch (current tip `7559a761`).
