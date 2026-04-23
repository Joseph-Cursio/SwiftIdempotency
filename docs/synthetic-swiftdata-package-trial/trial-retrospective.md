# Synthetic SwiftData Target — Package Integration Trial Retrospective

Session-end summary for the synthetic SwiftData trial. See
[`trial-findings.md`](trial-findings.md) for the empirical
record; this document is the "what went differently than
expected + what ships next" layer.

## Did the scope hold?

**Mostly.** The research question resolved cleanly: the
`IdempotencyKey(fromEntity:)` `CustomStringConvertible`
constraint is **Fluent-specific**. The decision-lever the
trial turns has its answer, and the v0.1.0 post-release API
plan pivots from "relax the global constraint" to "add a
Fluent-shaped constructor."

**What scoped-in unexpectedly:** Finding 4 — the tuple-wrapping
workaround for `#assertIdempotent` on non-Equatable Model
returns doesn't compile, contradicting both the hellovapor
trial's findings.md and the README's "Using with Fluent ORM"
section. This is a P0 doc error the synthetic trial caught
because it was the first trial to actually execute the pattern.

**What scoped-out:** the AmpFin real-adopter signal. The trial
was originally scoped as a real-adopter run on `rasmuslos/AmpFin`
per the test plan's preference for real adopters. The AmpFin
attempt hit ~30 min of Swift-6.3 baseline toolchain drift
(`@Model` + `let`-property regression, missing AppKit branch
for `PlatformImage`) that did not inform the
`SwiftIdempotency` API question. The pivot to synthetic
resolved the API question in the remaining session budget.
External-adoption signal for SwiftData stays at zero for now;
a later session against a current-toolchain SwiftData adopter
(TeymiaHabit pushed 2026-04-19 is the current best candidate)
can fill that gap.

## What would have changed the outcome — counterfactuals

### "If AmpFin had been pushed after Swift 6.3's `@Model` changes"

Most likely, AmpFin would have built cleanly on the first
attempt. The `let` → `var` regression and the `PlatformImage`
AppKit-branch miss are both fixes that any maintained SwiftData
codebase has already absorbed since Q1 2026. The trial would
have stayed on the real-adopter track, and the AmpFin
`OfflineManager.download(album:)` migration would have been
the artifact. The findings would have been identical on the
API-reachability axis (same types, same shape); the build-time
delta and adopter-refactor-cost numbers would have been real
measurements rather than synthetic ones.

### "If the hellovapor trial had actually executed `#assertIdempotent` with a tuple"

Finding 4 would have landed in the hellovapor trial itself
rather than here. The README would never have shipped the
incorrect "tuples of Equatable types are synthesised-Equatable"
claim. Two trials later, here we are rediscovering it. The
retrospective-actionable policy note is below.

### "If a fresh-toolchain SwiftData adopter (TeymiaHabit, vreader) had been picked first"

Lower chance of baseline-friction blocking the trial; higher
likelihood of xcodebuild methodology cost (simulator
destination, scheme management) that the Vapor-shaped trials
haven't had to absorb. Net: probably a similar session budget
to the AmpFin+synthetic combined — the real-adopter signal
would be preserved but the trial would have taken longer.

## Recommendations for the package API

Prioritised, highest value first.

### P0 — fix the README's "Using with Fluent ORM" tuple claim

**Evidence:** Finding 4. The current section at lines 394-418
of `README.md` recommends a compile-error pattern.

**Recommended edit:**

- Rename subheading from "`#assertIdempotent` on Model returns
  needs a tuple" to "`#assertIdempotent` on Model returns needs
  an Equatable projection."
- Replace the tuple example with a dedicated-struct example
  matching `examples/swiftdata-sample/Tests/SwiftDataSampleTests/DownloadHandlerTests.swift`'s
  `AlbumProjection`.
- Add a compiler-error excerpt block quoting the exact
  diagnostic, so a reader who started with the old claim can
  match the error they'd see.
- Cite this trial as the post-trial correction.

**Ship vector:** direct-to-main (per the `workflow_direct_to_main`
memory note — docs and simple tweaks go straight to main on
the SwiftIdempotency repo). SwiftIdempotency v0.1.0 release
blocker.

### P1 — correct the hellovapor trial-findings.md

**Evidence:** hellovapor's trial-findings.md at question 1
claims the tuple workaround works. Finding 4 disproves it.

**Recommended edit:** in-place correction note at the claim
site. Preserve the original claim verbatim (archaeological
trail) and append a post-publication correction pointing at
this trial's Finding 4 and the README fix.

**Ship vector:** direct-to-main. Docs-only.

### P2 — design `init(fromFluentID:)` or `init(fromFluentModel:)`

**Evidence:** Finding 1 shows non-Fluent Identifiable works
cleanly. The Fluent-only gap documented in the hellovapor
trial remains open. A dedicated Fluent-shaped constructor
reaches Fluent Models without adapter code.

**Design considerations (not in this trial's scope):**

- Which parameter label? `fromFluentModel:` mirrors
  `fromEntity:` shape but the `Fluent` branding is explicit;
  `fromFluentID:` is one level narrower (takes the ID
  directly, not the Model). A strawman — `init<M>(fromFluentModel
  model: M) where M: Fluent.Model` — would route through
  `FluentKit` as a weak dep (like the TCA closure-property
  shape). Needs validation against the FluentKit API surface.
- Alternative: keep the global `fromEntity:` and add a free
  function `IdempotencyKey.from(fluentID: UUID?)` or similar.
  Avoids the per-adopter conditional-import gymnastics.
- Must not break existing `fromEntity:` callers — the
  relaxation path (drop `CustomStringConvertible`) is what
  this trial rules out; the additive path is what this slot
  proposes.

**Ship vector:** slot on the `SwiftIdempotency` repo,
post-v0.1.0. Requires a FluentKit real-adopter validation
(hellovapor re-run) before merging.

### P3 — schedule a current-toolchain SwiftData real-adopter trial

**Evidence:** external-adoption signal for SwiftData is zero.
Three candidates pre-validated: `amangeldybaiserkeev/TeymiaHabit`
(pushed 2026-04-19), `lllyys/vreader` (pushed 2026-04-04),
`gahntpo/SnippetBox-SwiftData` (older, pushed 2023-10). All
are Xcode-project only (no `Package.swift`), so xcodebuild +
simulator destination is required.

**Ship vector:** next slice-driven round for the package-trial
workstream, post-v0.1.0 release. Not release-blocking per the
test plan (which requires one integration, not three, for
pre-release).

## Policy notes for this plan

Fold into `package_adoption_test_plan.md` §"Per-trial protocol"
/ §"Pick target + feature combination":

1. **Candidate-freshness filter for SwiftData adopters.** Any
   SwiftData-backed adopter with `pushedAt < 2026-02-01`
   likely carries the `@Model` + `let`-property regression on
   current toolchain. Filter to `pushedAt > 2026-02-01` (or
   spot-check the last-commit date) before forking. AmpFin
   (Nov 2025) would have been filtered out by this check.

2. **Claim-verification discipline.** Any adopter-facing
   recommendation in a trial's findings.md must be
   supported by a passing test in that trial's migration.
   "Documented via a comment" is not "verified to compile."
   The hellovapor tuple claim slipped through because the
   test file only verified the outer property
   (`tupleA != tupleB`) and left the `#assertIdempotent {
   ... return tuple }` pattern as a comment. Future trials
   should include the exact recommended pattern as a passing
   test, or drop the recommendation.

3. **Synthetic-as-pivot option is legitimate.** Per the test
   plan, synthetic is option #3 with "zero external-adoption
   signal" as its drawback. This trial establishes that
   synthetic is a valid pivot when a real-adopter attempt
   hits baseline friction unrelated to the API under test.
   The pivot cost is captured: ~30 min on AmpFin baseline +
   ~45 min on synthetic = ~75 min total, vs. the original
   1.5-2hr AmpFin budget. Acceptable trade, better signal-to-
   time ratio on the API-constraint question.

## Follow-ups on what we found

### The tuple-workaround correction (Finding 4) cross-artifact list

Three documents carry the incorrect claim or rely on it:

1. `README.md` §"Using with Fluent ORM" / §"`#assertIdempotent`
   on Model returns needs a tuple" (lines 394-418). **Must fix
   before v0.1.0.**
2. `docs/hellovapor-package-trial/trial-findings.md` §"Pre-
   committed questions — answers" / question 1. **Post-
   publication correction note.**
3. `docs/hellovapor-package-trial/migration.diff` at lines
   238-290. The tuple test is a comment, not executed — no
   fix needed to the migration.diff itself, but the comment
   should note the claim was later falsified.

All three edits are direct-to-main docs per the workflow
memory.

### Cross-adopter shape-coverage count update

Previously: "10 real-bug shapes across six production adopters,
10-for-10 `IdempotencyKey` / `@ExternallyIdempotent(by:)`
surface coverage." The synthetic is not a "real-bug" shape
(no real bug to catch in synthesised code), so this count is
unchanged. **But** the macro-surface validation count extends:

- Pre-synthetic: three consumer samples (webhook-handler,
  idempotency-tests, assert-idempotent) in `examples/`,
  exercising `IdempotencyKey`, `@IdempotencyTests`, and
  `#assertIdempotent` respectively.
- Post-synthetic: **four** consumer samples. The new
  `swiftdata-sample` is the first example crossing
  SwiftIdempotency with a persistence layer (`SwiftData`),
  exercising the deep interaction between `@ExternallyIdempotent`
  and `@Model` that wasn't covered by the existing three
  samples.

Suggest mentioning this in the next README update alongside
the tuple-correction. The README currently says "ships three
consumer samples"; post-synthetic, it ships four.

## Open questions this trial did NOT answer

- **Does the `@ExternallyIdempotent` macro correctly flow the
  key parameter through to a real linter parity check?** Not
  exercised on the synthetic — the synthetic has no
  SwiftProjectLint configuration. Deferred to the next
  real-adopter SwiftData trial.
- **What happens when `OfflineAlbum` is declared without a
  user-provided `id: String` — relying purely on SwiftData's
  `persistentModelID`?** Not tested. Likely the
  `IdempotencyKey(fromEntity:)` call fails at compile time
  (`PersistentIdentifier` is not `CustomStringConvertible`).
  Interesting for future documentation coverage but not
  affecting the v0.1.0 API decision.
- **How does `@ExternallyIdempotent` interact with SwiftData's
  actor isolation under Swift 6 strict concurrency?** Not
  probed; the synthetic's handler uses `throws ->` rather
  than `async throws ->`. A follow-up test would cover the
  async+actor path.

None of these are release-blockers for v0.1.0. They can be
folded into the next SwiftData real-adopter trial's scope.
