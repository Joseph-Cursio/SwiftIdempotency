# Road-Test Plan

How to run a road-test round against a real Swift adopter application,
what to capture, and when to stop. This document is the template the
trial author works from when picking up a new target.

See [`swift_idempotency_targets.md`](swift_idempotency_targets.md) for
the prioritised target list. See
[`hummingbird-examples/`](hummingbird-examples/) for the worked example
this template is abstracted from — if this document conflicts with
what that round actually did, the round is the reference and this
document is wrong.

## When to run a round

- A linter slice has landed that changes an inference heuristic or a
  framework whitelist. Road-test validates the slice on adopter code
  before calling it done.
- An adopter target is added to `swift_idempotency_targets.md` that
  isn't yet covered.
- A bug report or adoption-friction observation names a shape we
  haven't measured. A targeted round scopes the evidence.

Not every linter edit needs a round — rule bugfixes that ship with
fixture tests are self-verifying. Rounds are for **adoption-evidence**,
not unit-test coverage.

## Per-round protocol

### Pick the target

One adopter project per round. Slug the project name with hyphens
(e.g. `todos-fluent`, not `TodosFluent`). Multi-package corpora like
`vapor` or `hummingbird-examples` get one round per package — don't
blend packages in one directory.

### Pre-flight

- Verify the linter is on a known-green tip (`swift test` passes).
  Pin the commit SHA in the scope doc.
- Verify the target clone is clean and on a known SHA or tag. Pin
  both in the scope doc.
- **git-lfs check.** If the target uses git-lfs (check
  `.gitattributes` for `filter=lfs`, typical for adopters with
  image/audio assets like `isowords`) and the local machine lacks
  `git-lfs`, a plain `git clone` aborts midway with "remote helper
  'https' aborted session". Bypass with:

  ```sh
  git -c filter.lfs.smudge= \
      -c filter.lfs.clean= \
      -c filter.lfs.process= \
      -c filter.lfs.required=false \
      clone <url>
  ```

  Safe for idempotency scans — LFS-tracked assets are binary
  (images, audio, archives), never Swift sources, so nothing the
  linter needs is skipped. Install `git-lfs` locally if the
  adopter's build toolchain will be invoked (e.g. `swift build`
  on the target); not required for read-only linter scans.
- Create a `<upstream>-idempotency-trial` fork on your GitHub
  (naming convention, e.g.
  `swift-composable-architecture-idempotency-trial`). Harden it:
  `gh repo edit --enable-issues=false --enable-wiki=false
  --enable-projects=false --description "Validation sandbox for
  SwiftIdempotency road-tests. Not a contribution fork."`, then
  set the trial branch as the default after it's pushed, and
  prepend a README banner flagging the fork as non-contribution.
- Create a `trial-<short-slug>` branch on the fork. **The fork is
  authoritative**; scans are run against a fresh clone of the fork,
  not an ambient local checkout — this guarantees the measurement
  reflects pushed state and survives `/tmp` wipes. The trial
  branch's lifetime is this round; retire the fork or delete the
  branch when the round's findings are superseded.
- Create `docs/<project-slug>/` in `swiftIdempotency`. If the dir
  exists from a prior round, its contents will be overwritten by
  this round — git history is the audit trail, per the
  project-named-dir convention.

### Annotate

- 3-6 handlers, selected for shape diversity (pure read, create/write,
  delete, etc.). Prefer `func` declarations over closure-based
  handlers unless the closure shape is the specific thing under test.
- `/// @lint.context replayable` on each. Matched attribute forms
  (`@lint.context(.replayable)` if the adopter is already consuming
  the macros package) are equivalent.
- No logic edits to the target. If a source change is required to
  make annotations meaningful (e.g. a `by:` parameter on
  `@ExternallyIdempotent`), document it explicitly in the scope
  doc's "source modifications" section.

#### Handler-binding shape determines annotation target

Adopters bind handlers to routes in two structurally distinct
shapes; the annotation target differs:

- **Method-reference (`use:`)** — Hummingbird `RouterGroup.get(":id",
  use: self.show)`, Vapor `routes.get(":id", use: show)`. Annotate
  the *handler method* with `/// @lint.context …` on its `func`
  decl. The doc-comment attaches directly; the inferrer walks the
  method body. Confirmed shape on `myfavquotes-api`.
- **Inline trailing closure** — `router.get("/path") { req, ctx in … }`,
  common in tutorial code and prospero's prod app. The closure
  body has no named decl to attach to. Annotate the *enclosing
  registration function* (`func addXRoutes(to:)`); the inferrer
  walks the closures within. Confirmed shape on `prospero`.

Both produce useful diagnostics. Pick the matching shape for the
adopter — don't try to annotate registration helpers when handlers
are method references (it inflates noise without surfacing real-bug
evidence) and don't try to annotate inline closures directly (you
can't — there's no named decl).

### Scan twice

- **Replayable scan.** `swift run CLI <target-path> --categories
  idempotency --threshold info`. Capture transcript to
  `docs/<slug>/trial-transcripts/replayable.txt`.
- **Strict-replayable scan.** Flip the annotations to
  `strict_replayable`, re-run, capture to
  `trial-transcripts/strict-replayable.txt`.

For larger corpora where more runs are warranted (e.g. a third pass
with different annotation sets), add numbered variants
(`replayable-extended.txt`, etc.).

#### Multi-package corpora

Most Swift-server adopters ship a top-level SPM package plus an
`Examples/` (or `Demos/`) directory whose subfolders are each their
own SPM package with a nested `Package.swift`. Confirmed on
`swift-composable-architecture`, `swift-aws-lambda-runtime`, and
likely `vapor` and `hummingbird-examples` too. **The linter does
not recurse into nested `Package.swift` trees from a top-level
invocation** — a top-level scan on a multi-Example corpus silently
reports "No issues found" while the annotated code sits in an
un-walked subtree.

When the target has this shape, scan each annotated Example
directory separately and concatenate the output into a single
transcript. Shell recipe:

```sh
for ex in <Example1> <Example2> ...; do
  echo "=== <target-root>/Examples/$ex ==="
  swift run CLI "<target-root>/Examples/$ex" \
    --categories idempotency --threshold info
  echo
done > trial-transcripts/replayable.txt
```

Iterate only over the Example directories that actually carry
annotations — scanning unannotated examples just adds noise.
Match the `=== <path> ===` header convention so the transcript
diffs cleanly against prior rounds. See the
`swift-composable-architecture` and `swift-aws-lambda-runtime`
transcripts for worked examples.

### Audit

Every diagnostic gets a one-line verdict:
- **correct catch** — the adopter's code is genuinely non-idempotent
  in a retry context, and this is a real bug shape to fix.
- **defensible** — fires on a pattern that's non-idempotent in some
  readings but the adopter's code is OK by design. Silence by
  annotation.
- **adoption gap** — the heuristic missed a real shape. Name the
  gap and score a future slice.
- **noise** — fires on genuinely idempotent code with no good
  silencer. Log as a precision issue.

Cap the per-round audit at 30 diagnostics. If strict mode exceeds
30, decompose the excess by class in the findings doc without
per-diagnostic verdicts.

#### Structural (non-annotation-gated) rules

Some idempotency rules fire on structural pattern alone, independent
of any `/// @lint.context` annotation — e.g.
`tuple-equality-with-unstable-components`, which flags
`(…, Date()) == (…)` shapes wherever they occur. These surface on
Run A even on unannotated files, and surface on any file during
Run B regardless of handler scope. Audit them with the same four
verdicts (correct catch / defensible / adoption gap / noise); when
they fire, the finding is typically high-confidence by construction
(the rule is narrow on purpose). They don't count toward the
catches/handlers yield metric — there is no handler to attribute a
structural fire to. Record them separately in the findings doc and
note whether they appear in handler code or elsewhere (util, test,
fixture).

#### SQL ground-truth pass (DB-heavy adopters)

For adopters with a DB layer, a Swift-surface audit ("this looks
like an insert, so it's non-idempotent") is insufficient — the
actual SQL determines whether a retry is observationally safe.
After the initial Swift-surface audit, locate the concrete query
sites (commonly `*DatabaseLive.swift`, `*Repository.swift`, Fluent
model extensions, or equivalent) and re-verify each write-style
verdict against the query text.

Flip a "correct catch" to "defensible by design" when the SQL
shows any of:

- `ON CONFLICT (...) DO UPDATE SET ...` — upsert, retry-safe.
- `ON CONFLICT (...) DO NOTHING` — dedup on unique key.
- `UPDATE ... WHERE col IS NULL` — guard clause making retry a
  no-op on already-set rows.
- `INSERT ... RETURNING *` against a table with a unique index on
  the natural key being inserted — DB rejects duplicates before
  the row lands.

For **Fluent adopters specifically**, check the migration
`.unique(on:)` calls before reading SQL — Fluent compiles
`.unique(on:)` to a Postgres `UNIQUE` constraint. If a `create`
handler's model migration declares `.unique(on: <natural-key>)`,
the create-on-retry hits a DB-level dedup just like a raw
`ON CONFLICT (...) DO NOTHING`. This shortcut covers most Fluent
CRUD audits. Confirmed on `myfavquotes-api` (both `Quote` and
`User` migrations declare `.unique(on:)` → both `create` handler
diagnostics flip to defensible-by-design without reading raw SQL).

Evidence from this round's experience: isowords Run A would have
been mis-scored as 3 real-bug catches without this pass (actual:
1 real catch + 3 defensible-by-design upserts). Penny's Run A
didn't need the pass because its DynamoDB access uses bare
`createCoinEntry`-style calls without server-side dedup — so the
pass is adopter-dependent, but cheap enough to run unconditionally
on any adopter whose call graph touches a DB layer. Matters
especially for Vapor / PostgreSQL / Fluent adopters.

## Documents to produce

Four files under `docs/<project-slug>/`. No phase prefix. No round
number. Latest measurement only; re-runs overwrite in place.

### `trial-scope.md`

- Research question (quoted, one sentence)
- Pinned context (linter SHA, target SHA, fork URL, trial-branch name)
- Annotation plan (which handlers, which tier)
- Scope commitment (measurement-only, source-edit ceiling, audit cap)
- Pre-committed questions for the retrospective (3-4)

### `trial-findings.md`

- Run A (replayable) — per-diagnostic table, yield calculation, link
  to transcript
- Run B (strict_replayable) — per-diagnostic table split into
  "carried from Run A" and "strict-only," adoption-gap verdicts,
  decomposition into named slice clusters
- Comparison to prior measurement on this target (if any) or to the
  predicted outcome from the scope doc

### `trial-retrospective.md`

- Did the scope hold? (scope audit)
- Answers to the four pre-committed questions (explicit headers per
  question)
- What would have changed the outcome (counterfactuals — 2-3 bullets)
- Cost summary (estimated vs actual)
- Policy notes (lessons for the template; if any of them apply, fold
  them back into this document)
- Data committed (file list)

### `trial-transcripts/<mode>.txt`

Raw linter output, one file per scan. Strip SPM warnings and build
progress noise. Keep the "Found N issues" footer.

## Yield metric

`catches / annotated handlers` across a single mode. Report per-handler
(showing silent handlers explicitly) and aggregate. Structural-rule
fires (see "Structural (non-annotation-gated) rules" in Audit) sit
outside this metric — they have no handler to attribute to. Count
them separately in the findings doc.

Silent handlers are not failures — they're the correctness signal.
Report yield with + without silent handlers for comparison:
- "3 catches / 3 handlers = 1.00 including silent"
- "3 catches / 2 non-silent handlers = 1.50 excluding silent"

## Macro-form variant

Optional per round. Exercise if:
- The adopter is already consuming the `SwiftIdempotency` package
  for their own reasons (test generation, `IdempotencyKey` type),
  OR
- The round's specific purpose is macro-form validation.

Otherwise skip. Adding a package dependency to a target purely for
a measurement round is more invasive than the round warrants.

When exercised: replace `/// @lint.context replayable` doc-comments
with the equivalent attribute form from the macros package. Re-run
both scans. Note any linter divergence between the two annotation
forms — they are supposed to produce identical results.

## Completion criteria

Road-testing is "done enough to ship" when:

1. **Framework coverage.** One adopter per framework listed in
   `swift_idempotency_targets.md` has been road-tested: Vapor,
   Hummingbird, SwiftNIO, Point-Free.
2. **Adoption-gap stability.** Three consecutive rounds produce
   zero new named adoption-gap slices — the strict-mode residual
   has plateaued into a known set.
3. **Macro-form evidence.** At least one adopter has exercised the
   attribute-form annotations end-to-end and produced identical
   linter output to the doc-comment form.

Not on the list:
- Zero strict-mode diagnostics. Unachievable goal — stdlib and
  framework surface is always partially uninferrable.
- Every adopter in `swift_idempotency_targets.md` road-tested. The
  Tier-3 "random GitHub apps" list is exploratory, not a coverage
  obligation.

Continue the template even after completion criteria are met —
future linter slices still get validated the same way. The plan
stays alive; it just stops blocking on new targets.
