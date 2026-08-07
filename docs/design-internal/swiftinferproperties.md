# SwiftInferProperties — the inference engine

**Repo:** this one (`github.com/Joseph-Cursio/SwiftInferProperties`, binary `swift-infer`) ·
**Book home:** Chapters 16–18; the interaction families of 23–24; `verify-value-semantics` in
Chapter 9; `known-properties` in Appendix A.

> **As of 2026-08-03** · subject **is** the observer: `SwiftInferProperties@2722975` (`v1.63.0`+923).
>
> Counts and measurements here are **dated and will rot** — this is the doc most exposed to that,
> since its file counts and stage order change with ordinary work. Diagnoses, design rationale, and
> the reasons a decision was made **do not expire**. Re-verify the numbers; don't re-litigate the
> prose.

<!-- doc-provenance date=2026-08-03 subject=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 observer=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
   seeds                 discover + stubs        run the laws         retry-safety
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle) ────┘
```

**The most-connected node in the graph** — it consumes the kit (to emit runnable stubs), the effect
lattice (as its purity veto), and the linter's manifest (to focus), and it produces stubs the kit
runs. Reads your code, proposes properties, **never applies anything**.

## What this file is for

Three docs already describe this repo and none of them describes its *shape*:

- **`CLAUDE.md`** is a pointer-only index — where the reasoning for each shipped decision lives.
- **`glossary.md`** is vocabulary keyed to code, alphabetical within stage.
- **the four sibling docs** in this directory describe the boundary *from the other side*.

This one is the **architecture**: the targets, the stage order a suggestion actually travels, the
extension points, and the invariants that govern the whole thing. It deliberately does not restate
the narrative history — `git log` and `docs/archive/claude-md-narrative-history.md` own that.

---

## Shape

**v1.146.0** · 8 source targets · ~85,400 lines of Swift · ~4,400 tests.

| target | files | what it owns |
|---|---|---|
| `SwiftInferCore` | 137 | value types, scanners, scoring, the index, purity |
| `SwiftInferTemplates` | 148 (**89 `*Template*`**) | the catalog — every law shape that can fire |
| `SwiftInferCLI` | 225 | 25 subcommands, the verify workdir, every emitter |
| `SwiftInferTestLifter` | 41 | reads existing tests to *corroborate*, never to propose |
| `SwiftInferMacro` / `Impl` | 1 / 3 | the macro surface |
| `SwiftInferKitEvidence` | 1 | the kit-verdict feedback channel |

Dependencies: `swift-syntax` (exact `602.0.0`), `SwiftPropertyLaws` (`from: 3.26.0`),
`SwiftEffectInference` (revision — **see the pin note in `swifteffectinference.md`**),
`swift-argument-parser`.

**The CLI is the biggest target, and that is not an accident.** Most of the hard-won behaviour in
this repo is about *what to show a reader and when* — the tier cut, the seed focus, the rescues, the
warning text. The catalog proposes; the CLI decides whether proposing was honest.

---

## Two disjoint surfaces

Both go discovered → surfaced → verified → promoted end to end, and they run over different carrier
populations. Conflating them is the commonest reading error.

**Algebraic** — pure-function laws from signatures, cross-function pairs, and lifted test bodies.
The v1 corpus (`fixtures/cycle27-surface/`) is **100% measured** (53/53, cycle 151 — epic complete;
zero false positives, zero coverage-pending). Further movement needs *new public algebraic API*, not
filters or recipes.

**Interaction** — five families (idempotence / cardinality / biconditional / referential-integrity /
conservation) over reducer carriers (TCA, Elm, ReSwift, Mobius, Workflow, generic) and SwiftUI MVVM
carriers. All five have a demonstrated measured-verify path; idempotence promotes `.likely →
.verified` on measured execution, the rest default `.possible` behind `--include-possible`.

Async is admitted only via the `@ClockDeterministic` claim. Bare `async` keeps a clean rejection that
says how to make the claim.

---

## The stage order

`Discover.collectVisibleSuggestions` → `combineAndFilter` is the spine, and **the order is
load-bearing at four points**. Reading it top to bottom:

```
1  resolvePipelineSetup      target roots, flags, --sources shim
2  TestLifter.discover       scan TESTS for corroboration slices
3  TemplateRegistry.…        scan SOURCE — the catalog fires here
4  LiftedSuggestionPipeline  promote lifted rows, share the generator pass
5  skip-marker filter        `// swiftinfer: skip <hash>`
6  counter-signal filter     the user's explicit negative is dispositive
7  dedupedByIdentity         collapse the same law about the same function
8  VerifyEvidenceScoring     fold verify outcomes into the grade
9  KitEvidenceScoring        then the kit's verdicts  ← order matters
10 emitEvidenceDiagnostics   BEFORE the cut  ← order matters
11 drop .suppressed          checked-and-refuted, never resurrectable
12 the visibility cut        tier ∨ role-entailed rescue  ← order matters
13 strongestFirst            ordering, not hiding  ← the whole fix
```

**Why 8 before 9.** The kit's demotion applies to whatever verify concluded, because *a pick verify
lifted to `bothPass` is still unusable if the `==` it was compared with has been measured broken.*

**Why 10 before 12.** A `−45` kit demotion on a 70-point pick lands at 25, below the cut. Reporting
the diagnosis on *survivors* would guarantee silence in exactly the case worth reporting. **The
suggestion loses visibility; the diagnosis must not.**

**Why 11 is not 12.** `.suppressed` is a law we **checked and refuted**, not one we failed to show —
so it is excluded from `hiddenRefutable` too, and the final-answer guard must never resurrect it.
An earlier `includePossible || isVisibleByDefault` filter leaked verify-disproven picks through
under `--include-possible`.

**Why 12 has an escape hatch.** `Refutability.isWorthSurfacingBelowCut` surfaces a **role-entailed**
law on a default run even at `.possible` — a law a *correct* implementation cannot fail. It does not
leak conjectures: `monotonicity`, `idempotence` and `round-trip` are refutable but not role-entailed,
so correct-but-honestly-named code could fail them. Deliberately **not** gated by
`--require-corroboration`: "the code owes this" is a different justification from "one signal fired"
and does not need a second channel.

**Why 13 exists at all.** 88% of default output on some corpora was `predicate`, and a reader
scrolled past 56 score-20 rows to reach the first score-80 finding. Two right decisions were in
contradiction — `PredicateTemplate` says totality is hidden below the cut; `3e38e34` says a law the
code OWES is never hidden. Fixed by **ordering**, not hiding. See `SwiftInferProperties/docs/design/predicate-display-order.md`.

---

## The four extension points

**1. A template** (`SwiftInferTemplates/*Template*.swift`) decides *whether it fires* and *what score
it assigns*, and ships the "why suggested / why this might be wrong" pair. 89 files.

> **Before adding one, run the §10 census A/B** — two binaries from the before/after commits, run on
> **the same day over the same corpora**. Never today's run against a remembered count: a remembered
> count carries no record of the flags it was taken with, and tier visibility moves the headline
> number by 20%. **15% of templates are dead** (6 of 39 never fire) and a dead template looks exactly
> like a correctly-silent one.

**2. A veto** suppresses a firing a template would otherwise make. **Vetoes have been the
highest-yield work in this repo** — the stream-consumption veto took 53 false `likely` claims on
`SwiftParser` to 1; the result-builder veto took SwiftSyntaxBuilder 23 → 2. Additions have moved
single-digit row counts.

**3. A composer** (`StrategistDispatchEmitter+Templates.swift`) renders the stub source for one
template, as a pure `(Inputs, GeneratorRecipe) -> String`. **This set — not the catalog — is what
bounds verify reach**: 13 templates, and 62% of index entries decline `unsupported-template`.

**4. A signal** (`Signal+Kind.swift`) contributes weighted score. The file is capped at 400 lines and
`Signal.Kind` is one enum Swift will not split across files, so it grows monotonically with the
catalogue. **If a new signal will not fit, move the next-longest rationale to
`SwiftInferProperties/docs/design/signal-kind-rationales.md`** — do not trim the new one. Every comment left inline records a
measurement, and several are the only surviving record of why a veto exists.

---

## The standing invariants

These are decisions to follow rather than re-litigate. The full list is in `CLAUDE.md`; these are the
ones that shape the architecture.

- **Conservative inference — high precision, low recall** (PRD §3.5). When in doubt, fewer.
- **Avoid the Daikon trap.** Too much output → **raise thresholds, don't pile on filters.** Filters
  add surface area where the one law that mattered gets eaten — which is what `Rescue` exists to
  catch, and it has fired.
- **A rescue is a bug report, not a feature.** Every firing means an upstream stage has a blind spot,
  and callers must say so loudly.
- **Score refutability, not suggestion count.** `f(x) == f(x)` passes "did discovery return > 0" and
  can never fail.
- **A tool may not grade its own homework.** On a scored road test, anything found that the frozen
  answer key missed is recorded **unscored**.
- **Explainability is a first-class output** — every suggestion ships both halves (PRD §4.5).
- **Generator inference delegates to `DerivationStrategist`.** Don't reimplement (PRD §11).
- **Purity gates must not relax to reach a target.** Removing the `throws` gate once re-admitted
  `Process`/`Pipe`/`FileHandle`/SQLite at a stroke, with a subprocess-spawning function judged pure.
- **A refuter that fires first hides every refuter behind it.** Reading the code cannot tell you how
  many are queued — measure after each fix. Three passes each named "the remaining blocker" for
  `serialize`, each wrong.
- **`measured-bothPass` means "no counterexample in the generated domain,"** not "the property
  holds." Collision-dependent laws are invisible to a generator drawing from a realistic domain.
- **Nothing auto-executes.** No discovery path compiles or runs anything, which is why `discover` on
  a hostile corpus is safe. `verify` is opt-in, always.

---

## What the sibling docs assume about this repo

Each boundary doc leaves an obligation on this side. Collected, because they are easy to break from
in here without noticing:

| sibling | what it assumes holds here |
|---|---|
| `swiftprojectlint.md` | `SeedRole` keeps `comparator`/`predicate`/`partition` in `Refutability.roleEntailedTemplates`. Demote one and the producer's `impliesEntailedLaw` becomes a lie — pinned by `SeedRoleContractTests`. Also: a seed focus never hides a law the code owes. |
| `swifteffectinference.md` | `SoundPurity` takes the **meet** of `ReducerPurityAnalyzer` and `PurityInferrer`. Claiming `.pure` from either alone is unsound. **The SEI pin should equal SwiftProjectLint's and deliberately does not** — the bump was attempted 2026-08-03 and reverted, because `097181aa` costs a measured ~2× regression on the discover path (5 of the §13 budgets fail). Filed as [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1); do not re-apply without reading it. |
| `swiftpropertylaws.md` | `VerifierWorkdir.swiftPropertyLawsRequirement` equals this package's own pin (`VerifierWorkdirKitPinTests`), and `ProtocolCoverageMap`'s claims stay true law-by-law (`KitCoverageLawLevelTests`). |
| `swiftidempotency.md` | `@ClockDeterministic` is the *only* thing that admits async, and the determinism law it earns is what makes the author's claim falsifiable. |

---

## Traps

- **`TemplateName` does not enumerate every template.** ~89 template files against 17 enum cases;
  `predicate`, `input-totality`, `filter-subset` are live in the index and absent from the enum.
  Counting by `allCases` undercounts.
- **The glossary's mode table is one short.** It says "The 24 modes"; `SwiftInferCommand.subcommands`
  has **25** — `scaffold-kit-suites` is missing from the table. Same drift shape the repo has already
  paid for twice (`CuratedEntryRole` guarding the wrong join, `KitCoverageDriftTests` asserting at
  suite rather than law granularity): **a list that must track a registry, with nothing watching it.**
- **Three "reach" numbers get conflated.** Discovery reach (bounded by the catalog), verify reach
  (bounded by the *composer* set), refutation reach (bounded by the generator). `unsupported-carrier`
  reads like the bottleneck and measures at ~4%.
- **Never report a `discover` count alone.** Pair it with PropertyLawKit coverage, in **laws**, not
  carriers. A perfect kit with nothing left to infer would score 0% recall — total success rendered
  as total failure (`fixtures/leaderboard-sort`, whose scorecards are withdrawn for exactly this).
- **A new `*MeasuredTests` suite must be added to a Makefile batch by hand**, or `make test` silently
  skips it. Same orphaning trap for `PERF_RE` suites and `make perf`.
- **`MemoryCeilingPerformanceTests` §13 row 4 flakes under parallel load** — ~150 MB in isolation
  against an 800 MB budget, ~4800 MB when it trips, at the same rate with an unrelated change
  stashed. Rerun before blaming your edit.
- **`verify --all-from-index` leaves one full SwiftPM workdir per suggestion.** An 85-entry survey of
  this repo left **3.4 GB** in `.swiftinfer/verify-workdir/`, gitignored and silent. `make clean-temp`.

---

## Build & test

`swift package clean && swift test` on session start. Then **use the Makefile**:

| command | what |
|---|---|
| `make test-fast` | lint gate + regex-skip fast path, ~6s |
| `make test` | fast suite + sequential subprocess batches, fail-fast — **prefer over bare `swift test`** |
| `make batch1`…`batch7` | the subprocess suites, bounded peak temp-disk |
| `make perf` | the §13 suites, alone and serial — they assert wall-clock and peak-RSS |
| `make clean-temp` | sweep leaked TCA workdirs and `verify-workdir/` |

The fast path is `--skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'` — a **regex against
the test ID**, self-maintaining. Don't enumerate suite names: the old per-name list silently missed
four `VerifyPipeline*` suites and the "fast" command ran ~90 minutes.

`swiftlint lint --quiet --strict` must stay at **zero**.

---

## Where to look

`CLAUDE.md`'s table is the index and every `docs/*.md` is reachable from it. The rows worth knowing
before you touch anything:

| question | file |
|---|---|
| what a word means | `docs/design-internal/glossary.md` |
| the measured-verify design (the whole v2 story) | `SwiftInferProperties/docs/design/measured-verify-architecture.md` — **read first** |
| why `bothPass` used to under-claim | `SwiftInferProperties/docs/design/verify-edge-pass.md` |
| why `verify` declines so much (it is not the carrier) | `SwiftInferProperties/docs/measurements/verify-carrier-reach-census.md` |
| why 88% of default output was `predicate` | `SwiftInferProperties/docs/design/predicate-display-order.md` |
| the catalog health census, and how to A/B a template | findings §10 |
| product scope and success criteria | `docs/SwiftInferProperties PRD v1.0.md` + `v2.0.md` |
| the full shipped-cycle changelog | `docs/archive/claude-md-narrative-history.md` |
| the four sibling packages | `docs/design-internal/swift{projectlint,effectinference,propertylaws,idempotency}.md` |
