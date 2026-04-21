# isowords — Trial Retrospective

## Did the scope hold?

Yes, cleanly.

- Annotation count: 5 planned, 5 delivered.
- Source edits: 5 one-line annotations + 1 README banner.
  Within the committed source-edit ceiling.
- Audit cap: Run A 5 diagnostics ≤ 30 (full audit). Run B 162 >
  30 (decomposed by cluster per the template).
- No unplanned slices opened during the round. Two new slice
  entries (13, 14) are written up in `trial-findings.md` but were
  not executed — captured for the next-steps doc.

One **template-gap finding** (see Policy notes): the road-test
template assumes `git clone <target>` works on the default
toolchain. isowords uses git-lfs for asset files, and the
pre-installed shell has no `git-lfs` binary. Clone required
`-c filter.lfs.{smudge,clean,process}= -c filter.lfs.required=false`
to bypass the filter driver. Not a blocker — Swift sources aren't
LFS-tracked — but other adopters with LFS will hit this too.
Captured below.

## Answers to pre-committed questions

### Q1 — Does yield generalise?

**Yes, with nuance — see the full answer in
[`trial-findings.md` §Pre-committed question answers — Q1].**

Headline: the linter's *precision* generalises (real-bug catches
are real-bug-shaped in both rounds), but *absolute yield* is
codebase-dependent. isowords' pervasive upsert SQL makes most
of the Swift-surface-looking "writes" retry-safe by design.
The useful cross-adopter metric is **macro-surface coverage** —
`IdempotencyKey` / `@ExternallyIdempotent(by:)` covers 6/6 real-
bug shapes across two production rounds.

### Q2 — HttpPipeline shape interaction

**No new interaction.** The `public func *Middleware(_ conn:
Conn<...>) -> IO<Conn<...>>` shape walks identically to Vapor /
Lambda `func handle(_:)`. Closure-property resolution (PR #19)
works on `DatabaseClient`'s closure properties. The prior
pointfreeco-www round already characterised this stack; isowords
adds no new shape-specific findings.

### Q3 — Do Penny's four bug-shape categories recur?

**1.5 of 4 recur.** Full breakdown in findings. The "duplicate-row
insert without ON CONFLICT" category is universal (fires in both
rounds). The Discord-bot-specific categories (error-path
notification dup, webhook redelivery) don't appear in a mobile-
app backend. Single-use-token replay is *present* (Apple receipts)
but defused at the DB layer.

This is a meaningful finding: **Penny's high yield reflected
Penny's shape mix, not a linter truth.** Other production shapes
will surface fewer or different categories.

### Q4 — Adoption-gap slices

**One new slice surfaced (slot 13 — prefix-lexicon gap) and one
new cross-framework candidate accumulated evidence (slot 14 —
HttpPipeline whitelist).**

Slot 13 is the valuable finding. The current non-idempotent-prefix
lexicon (`create|insert|update|delete`) is narrower than the
verbs production server apps actually use (`submit|start|complete|
send|register`). isowords missed a real bug in Run A because of
this gap; strict mode recovers it, but strict mode isn't the
recommended default tier.

## What would have changed the outcome

Three counterfactuals:

1. **If isowords had used raw INSERTs like Penny.** Yield would
   jump from 1 Run A catch to ~5 (every SQL write is a fresh row).
   The actual difference isn't linter behavior, it's target
   schema design.

2. **If the prefix lexicon covered `start*` / `submit*` / `complete*`
   at Run A.** `startDailyChallenge` (the missed real bug) would
   fire in Run A instead of Run B, raising Run A yield to 2/5
   handlers with real catches and eliminating the silent handler.
   `submitLeaderboardScore` + `completeDailyChallenge` would also
   fire — both defensible, adding 2 defensible diagnostics. Net:
   same set of real bugs found, louder defensible-noise floor.
   Slot 13 is the right fix — add prefixes to surface the real
   misses even if defensible noise goes up slightly.

3. **If adopter annotation were applied to the `DatabaseClient`
   closure properties.** `fetch*` properties annotated `@lint.effect
   idempotent` (they're closure-property decls; PR #19 picks them
   up) would eliminate 5 Run B `fetch*` diagnostics. Upsert-backed
   writes annotated `@lint.effect idempotent` would eliminate
   another 4 Run B `insertPushToken` / `updateAppleReceipt` /
   `submitLeaderboardScore` / `completeDailyChallenge`. Combined
   Run B would drop from 162 to ~150 — still cluster-dominated by
   stdlib higher-order helpers. The residual cluster distribution
   is what needs attention, not individual annotations.

## Cost summary

| Phase | Estimated | Actual | Delta |
|---|---|---|---|
| Pre-flight (fork, clone, pin) | 15 min | ~20 min | +5 min (LFS filter workaround) |
| Annotate 5 handlers | 15 min | ~10 min | −5 min |
| Run A + Run B scans (incl. push-pull cycle) | 15 min | ~25 min | +10 min (scan takes ~10 min on 285-file corpus; first push to new fork required default-branch flip) |
| Audit + write docs | 60 min | ~75 min | +15 min (SQL ground-truth verification against `DatabaseLive.swift` added a pass) |
| **Total** | **~105 min** | **~130 min** | **+25 min** |

The SQL-verification pass was the unplanned add; it's also the
round's most valuable artifact. Without it, Run A would have been
scored as "3 real-bug catches" — visibly wrong after reading the
SQL. Future rounds targeting DB-heavy adopters should bake this
pass into the audit template. See Policy notes.

## Policy notes (fold into template if applicable)

### 1. SQL ground-truth verification should be a standard audit pass

For DB-write-heavy adopters, a Swift-surface audit ("this looks
like an insert, so it's non-idempotent") is insufficient. The SQL
the adopter actually runs — `ON CONFLICT ... DO UPDATE`, `WHERE
... IS NULL`, unique-index-backed upserts — determines whether a
retry is observationally safe. Penny's audit didn't need this
pass because Penny's DynamoDB access uses bare `createCoinEntry`
patterns without server-side dedup. isowords' PostgreSQL access
is pervasively upsert-guarded, so Swift-surface reading misleads.

**Proposed template update** (`road_test_plan.md`, under "Audit"):
> For adopters with a DB layer: after the initial Swift-surface
> audit, locate the concrete SQL / query statements (commonly in
> `*DatabaseLive.swift` or equivalent). Each write-style call's
> verdict should be confirmed against the actual SQL. An `ON
> CONFLICT DO UPDATE` or a `WHERE col IS NULL` guard flips a
> "correct catch" into "defensible by design." This pass matters
> especially for Vapor / PostgreSQL / Fluent adopters.

### 2. Template pre-flight should mention git-lfs

The `road_test_plan.md` "Pre-flight" section says "verify the
target clone is clean and on a known SHA" — assumes `git clone`
Just Works. It doesn't, for LFS-using adopters, on a base shell
without `git-lfs` installed.

**Proposed template update** (`road_test_plan.md`, under
"Pre-flight"):
> If the target uses git-lfs (checked by `grep "filter=lfs"
> .gitattributes` after a dry-run clone) and the local machine
> lacks `git-lfs`, clone with
> `git -c filter.lfs.smudge= -c filter.lfs.required=false
> -c filter.lfs.clean= -c filter.lfs.process= clone <url>`. The
> linter doesn't need LFS-tracked assets (which are binary, not
> Swift sources).

Both are captured in this retrospective; folding into the template
is a next-session housekeeping item, not a blocker for this round.

## Data committed

Under `docs/isowords/`:

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md` (this file)
- `trial-transcripts/replayable.txt` (Run A; 5 diagnostics)
- `trial-transcripts/strict-replayable.txt` (Run B; 162 diagnostics)

On `Joseph-Cursio/isowords-idempotency-trial` (public, hardened):

- `trial-isowords` branch, tips `a71c993` (Run A) and `4e3cc83`
  (Run B). Default branch switched to `trial-isowords`. Fork
  banner in `README.md`.
