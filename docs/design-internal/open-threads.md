# Open threads

Things decided, noticed, or left undone that have **no other home**. Deliberately terse — an
index, not an essay. Anything with a real home lives there instead; this file exists so a
conversation's residue does not evaporate.

> **As of 2026-08-05** · `SwiftInferProperties@e92542a`. Entries here are *not* dated claims
> about code — they are open questions and standing reads. Close them by deleting the row and
> putting the answer where it belongs. Measurements *inside* an entry carry their own date and
> SHA; the suite run in item 0 was taken at `1e0218e` and has not been re-taken since.

<!-- doc-provenance date=2026-08-05 subject=SwiftInferProperties@e92542a4a2f9f0ad9abfd767744d62cc79a5c6e5 observer=SwiftInferProperties@e92542a4a2f9f0ad9abfd767744d62cc79a5c6e5 -->

---

## Next session starts here

The 2026-08-03 list that lived here is **spent** — items 0/1/3/4/5 all closed, and the reasoning
that outlived them is in *Open items* and *Decisions*. Two things from it are worth carrying
forward, and only two:

- **The `predicate` composer stops at 83%, and the number is the argument.** The remaining 22 are
  not composer failures: both compile buckets are ZERO, and what is left is 17 carrier declines
  (14 SwiftSyntax nodes and optionals), 4 traps the gate correctly refuses to call refutations, and
  1 `build-failed` that turned out to be the `Gen<URL>` defect. Nothing on that list improves by changing the
  composer. **The next gain is breadth, not depth** — and the whole-corpus survey agrees from the
  other side: `codable-round-trip`, the one template that never has to guess, is the only one at
  100% yield.
- **Generators for syntax-node carriers** — now item 27, because it is the largest single bucket
  left anywhere in this survey and it is a scope-and-file question rather than a build one.


## Open items

| # | item | where it stands |
|---|---|---|
| 4 | ~~**The attribute-grammar join has no contract test**~~ | **CLOSED 2026-08-05** — the cross-repo half now has a manifest and a test that was watched failing. `fixtures/effect-vocabulary/` records SwiftIdempotency's **`@attached(peer)` public macros** with a provenance SHA, and `EffectVocabularyCrossRepoTests` asserts swift-infer's recognised set **equals** that minus two named exclusions. **Equality, not subset, because the directions fail differently**: a name disappearing is the rename that disarms the veto; a name appearing is a vocabulary nobody reads — **which is item 20 having already happened**, and this shape would have said so the day `@EffectUnknown` landed. The rule is derivable rather than curated (`@attached(peer)` separates the 7 annotations from `IdempotencyTests` and `assertIdempotent` structurally). Three mutants watched firing: rename, addition, stale exclusion. **The honest limit is in the fixture README** — freshness re-derives from `../SwiftIdempotency` only when that checkout exists, so CI alone would not catch an upstream rename; `make docs-drift` is the standing detector. Earlier half: **The names this repo's behaviour is keyed to are now pinned** ([#79](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/79), `EffectVocabularyContractTests`): contents, behaviour (every spelling round-trips through the real scanner), and **the rename simulated** — a near-miss spelling yields `nil`, not a wrong effect. It became urgent when [#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78) made `IdempotenceTemplate` **veto** on these names, so a rename stops suppressing a false law instead of failing loudly. **Still open: the cross-repo half.** swift-infer deliberately does not depend on SwiftIdempotency — the doc-comment spelling needs no dependency and the attribute is matched by NAME — so asserting these equal its *shipped macro names* needs a fixture or a checked-in manifest |
| 7 | ~~**No end-to-end number for the LOOP**~~ | **CLOSED 2026-08-05 — the loop verifies its own output.** `index --seeds` filters the index to what the linter pointed at, reusing `Discover.focus` so it cannot disagree with `discover --seeds` about what a seed selects, and writes **`.swiftinfer/seed-index.json` — never the conventional path**. Sharing one would let a `verify --all-from-index` run silently answer about whichever was written last, which is exactly how the loop came to verify a population its own earlier stage never produced. `toolchain.sh` stage 3 now runs `index --seeds` → `verify --index-path`, and **`--index-path` never auto-rebuilds**, so a stale seed index stays visibly stale. **Proven on a fixture rather than asserted**: `seed-index.json` holds exactly stage 2's 3 suggestions, `index.json` is *absent*, and `verify.stderr` contains **zero** reindex lines. Verify half remains 139 of 281 (`fixtures/whole-corpus-survey/`). **Still open, and smaller**: the loop number has only been taken on a two-function fixture — a real corpus run is now possible and has not been done |
| 8 | **Exit criteria for "the toolchain is in shape"** are unwritten | see *Decisions* → *Road tests were misfiled* |
| 9 | ~~**Driver stages 3–4** (`verify`, kit conformance suites) are declared and unimplemented~~ | **STAGE 3 BUILT, STAGE 4 HALF BUILT, 2026-08-05 — the loop executes a law for the first time.** `toolchain.sh --verify` runs `verify --all-from-index` after the seed hop and reports **laws that RAN**, not entries surveyed: a run where everything declined executed nothing, and reporting the survey size would hide exactly that. Measured end to end on a two-function fixture: *1 law executed — 0 held, 1 refuted*, and the refutation is correct. **Stage 4 emits and does not execute, and says so in the same breath** — `scaffold-kit-suites --output` writes into the run dir, never the target tree, because a driver that generated files into a repo it was pointed at would break the standing never-modifies line; running them needs a synthesized test target that does not exist. **New `skipped` status**, distinct from `not-implemented`: once a stage is built, reporting it as *not built* understates the gap in the other direction. **The closing line is now DERIVED** — it said *"stages 3-5 did NOT"* as a fixed string and would have kept saying it after stage 3 shipped. Original note: `scripts/toolchain.sh`. Until they exist, **no run of the loop executes a law** — the driver says so every run rather than implying otherwise |
| 10 | ~~**The two ends of the lint→infer hop take different inputs**~~ | **CLOSED 2026-08-05 — the fix belongs in `discover`, and the open question is answered.** `discover` with neither flag now infers scope and **says what it inferred**, so the documented hop no longer fails on a reader's first attempt. **The no-confident-zero rule is kept, not traded**: inference fires only where the layout is unambiguous. One module under `Sources/` → that target; **several → the whole tree, never a pick**, because naming one would silently scan a fraction of the package while scanning everything cannot be a *narrower* wrong answer; **no `Sources/` at all → still a loud error** naming `--sources`, which is the Xcode case where guessing produces exactly the confident zero. **Scoped to `discover` deliberately** — the other five scanning commands keep the strict resolver, because none of them is the second half of a documented two-tool pipeline. **A test caught a real bug in the fix**: the single-module path called `resolve(_:)`, which applies `Sources/<target>` to the PROCESS working directory, so an injected root was ignored — it worked in production only because cwd and package root coincide |
| 12 | ~~**Neither binary can state its own build identity**~~ | **CLOSED 2026-08-05 for swift-infer.** `BuildIdentity.commit` ships as **`unattributable`**, and the refusal is the design: a plain `swift build` cannot know its own commit — dirty tree, detached checkout, not a git repo — so reporting anything else would be a **confident zero wearing provenance**. `scripts/stamp_build_identity.sh` is the deliberate act that earns it (writes the SHA, builds, restores), and a dirty tree stamps `sha+dirty` rather than pretending. **A SwiftPM prebuild plugin was rejected**: sandboxed, `git` from one is unreliable across toolchains, and a mechanism that silently fails would reintroduce exactly the false attribution this prevents. **The driver now CROSS-CHECKS** tree SHA against `--version` and fails stage 0 when they disagree — its own border claim, closed. **One defect found by running it**: the first restore used `git checkout -- <file> || true`, which cannot restore an *untracked* file and swallowed the failure, so the first stamped build left the constant baked into the tree while reporting success — a `|| true` on a restore is how a guard fires never. Now restores from a copy. **Still open: SwiftProjectLint and the other three packages**, which have the same gap; this is the pattern for them |
| 13 | ~~**Speculative refactoring** — mutate a copy, verify, propose a patch only when the law ran~~ | **TIER 1 BUILT 2026-08-05.** `suggest-refactors --speculative` snapshots the package, widens one `private`/`fileprivate` declaration, diffs the discovered identities, verifies what was gained, and emits **a diff, a law and a verdict** — never prose, because a verdict about an edit the reader did not make does not transfer. Gated and `--max-candidates`-capped: one snapshot plus one verify workdir per candidate. Only `.notVisibleToTests` is a candidate — widening a `.nestedLocal` is the **no-op the design named as the trap**. `SpeculativeVerdict` is its own vocabulary rather than `measured-defaultFails`, which would dishonestly mean *the property is false of your program*; the copy carries a source digest, since it is a border claim. **Non-recommendations are reported, not hidden** — 14 of 20 widenings gained nothing in the 2026-08-04 sample, and suppressing that would flatter the command. **One defect only an end-to-end run could find**: the first version matched `runPipeline`'s prose for `"bothPass"`, a word it never emits, so the headline verdict was unreachable and every candidate read `not-runnable` — now routed through `SurveyOutcome`, and the seam is filed as [#116](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/116). **Tiers 2–4 remain**: closure extraction, kernel extraction (needs differential testing before *"we know it would work"* is earned), and primitive→domain type, which is out. Design: designed 2026-08-03, **unbuilt**, and **re-measured 2026-08-04 with laws that RUN**. The 2026-08-03 funnel (20 → 8 proposed → 2 composer-supported) was a ceiling nobody had executed. Executed: **0 of 6 ran on the pre-composer binary, 3 of 6 on HEAD** — 1 holds, **2 refute**, and both refutations are false laws rather than bugs. The blocker was never the composer; it was the cross-module import (item 16). See *Decisions* → *Access widening, re-measured* |
| 17 | ~~**The idempotency vocabulary is split across two packages, and this one reads neither half it owns**~~ | **CLOSED 2026-08-05 — all three steps done, in the order the trap required.** Step 1 (#78) made swift-infer read the vocabulary; step 3 is item 4's contract test; step 2 lands here: `CheckPropertyKind.idempotent` is **deprecated, not deleted**. Deleting would take a working test generator from users and point them at a package they may not depend on — and **the replacement is not a relabel**: swift-infer *reading* `@Idempotent` corroborates a law, it does not generate a test, so migrating means `@Idempotent` **with** `@IdempotencyTests`. `.roundTrip` and `.preservesInvariant` stay; SwiftIdempotency has no equivalent. **Watching it fire found a live defect the deprecation created**: `roundTripRequiresDistinctTypes` told users *"For T -> T use @CheckProperty(.idempotent)"* — the tool steering people onto the API it had just deprecated. Both diagnostics now name the owner. Original survey: surveyed 2026-08-04, **undecided by choice** — see *Decisions* → *Idempotency vocabulary*. Not a naming clash: two packages independently **generate idempotency tests from an annotation**, and swift-infer uses `EffectAnnotationParser` at exactly **three call sites, all `isClockDeterministic`**. Ordering matters — retiring `.idempotent` before swift-infer *reads* `@Idempotent` reproduces item 4's failure mode by hand. **Step 1 SHIPPED** ([#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78)): swift-infer reads the effect vocabulary — `@Idempotent` corroborates, `@NonIdempotent`/`@ExternallyIdempotent` veto. **Dogfooding it found two defects** ([#81](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/81)): the annotation was paid for **twice** (the `@lint.effect` line is a doc comment, so `DocstringPropertyCorroborator` also credited it), and **+40 was keyed to the wrong definition** — the owner defines `@Idempotent` as re-invocation stability, not composition, so it is now +15. **Steps 2 and 3 remain**: retire `.idempotent` from `CheckPropertyKind`, and the cross-repo contract test (item 4). **Folded in**: whether `@ClockDeterministic` belongs in SwiftIdempotency — it does **not** belong to the effect lattice (four pre-existing fences say so) but probably does belong to the package; the actionable part is that it is the one annotation neither configurable nor contract-tested, which is item 4 |
| 20 | ~~**Nothing reads `@EffectUnknown`.**~~ | **CLOSED 2026-08-05 — the chain is complete.** Link 1 shipped in [SEI#3](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/3): `declaresUnknownEffect` reads both grammars with its own predicate, since `unknown` is incomparable to `non_idempotent` and admitting it to a linear five-tier `Effect` would force a Hasse-diagram join. **The gap it closed is precise**: `parseEffect` returned `nil` for `@lint.effect unknown` — the same answer as for an unannotated declaration *and* for a misspelled tier. Links 2 and 3 followed here: pin bumped to `6f45139`, and `IdempotenceTemplate` emits a **caveat, not a signal**. **Score-neutral by design and pinned as such** — `@NonIdempotent` vetoes because it *denies this law*; `unknown` denies nothing, so vetoing would suppress possibly-true laws on the strength of an author's uncertainty, and corroborating would treat uncertainty as evidence. It earns a line, not points — the `StdlibAnchor` / kit-passed posture. Measured end to end: two identical functions, one annotated, **both score 35, only one carries the caveat**. Original framing: SwiftIdempotency ships the marker as of [#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3) (2026-08-04); no tool distinguishes it from an unannotated declaration | **Unblocked 2026-08-04.** Item 1 is fixed and the pin now sits at `bfcf0e3`, so links 2 and 3 of the chain are clear. What remains is **link 1: SEI must learn to read the marker** — and it belongs there, not here, because swift-infer re-implementing the `@lint.effect` grammar is exactly what SEI exists to prevent. See *Decisions* → *The `@EffectUnknown` dependency chain* |
| 27 | ~~**Generators for syntax-node carriers**~~ | **SCOPED AND FILED 2026-08-05, and the measurement inverted the priority.** This row called syntax nodes *"the largest single decline bucket in the whole-corpus survey"*. **They are 11 of 105 (10%)**, across 9 carriers. The largest is **`FunctionSummary` at 32 (30%)** — nearly 3× the whole syntax bucket. The old figure was true *within `predicate`*; it was carried over to corpus scope without recounting. **`FunctionSummary` declines for two STACKED reasons**, which is why *"record cross-module shapes"* is not the fix: its `Effect?` and `PurityVerdict` parameters are declared in SwiftEffectInference and **zero of the index's 745 recorded types come from outside this package**; and even given a shape, `Effect` is **not `CaseIterable`** and cannot be, since `externallyIdempotent(keyParameter:)` carries an associated value — so the strategist's `allCases` route does not apply. Fixing only the first moves the failure. Filed as [#118](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/118) (this repo — shapes are the index's job) and [SwiftPropertyLaws#7](https://github.com/Joseph-Cursio/SwiftPropertyLaws/issues/7) (the strategist question, both halves). **The syntax-node half is filed expecting a documented NO** — a syntax node is a parse of source text, not a value with a domain, and a decline with a reason stops downstream counting these as a reach gap. Original framing: **Scope-and-file, not build.** 14 of `predicate`'s 22 non-running rows, and the largest single decline bucket in the whole-corpus survey (`no generator for carrier` is 105 of 281 corpus-wide). The design decision *"generator inference delegates to SwiftPropertyLaws"* says the answer is probably **not here** — so the deliverable is a scoped question for `DerivationStrategist`, not a generator in this repo |

---

## Decisions taken in conversation

Recorded because the reasoning is the useful part and it exists nowhere else.

### One package for the survey, not one per suggestion (2026-08-05, built)

`verify --all-from-index` built a complete SwiftPM package **per suggestion** — resolve,
fetch, compile four dependencies, link — around a stub that is a ~113-line `main.swift`.
Measured on `fixtures/cycle27-surface` (53 entries): **13m 30s, 24 GB, 464 MB per
workdir**. The shared form is **100s / 1.6 GB cold and 45s warm**, verdicts **53/53
identical** against the frozen v1.134.0 answer key — reconfirmed 2026-08-05 at
v1.148.0, 0 mismatches over an intersection of 53.

**Cold vs warm is not a footnote — omitting it manufactured a contradiction.** This
entry said `103s`; the source comments said `54s`; both were true and neither named
its cache state, so for a day they read as two irreconcilable measurements of one
run. Re-measured back to back on one binary: **cold** (no `verify-workdir`) 100s /
1596 MB, **warm** (reusing that `.build`) 45s / 1596 MB. Same shape as the
denominator lesson below — **a number is evidence only with the conditions it was
taken under**, and wall-clock's condition is the cache.

**The rationale was real and was read too widely.** `VerifierWorkdir`'s doc says one
directory per hash *"so concurrent verify calls against different suggestions don't stomp
on each other's `.build/`"* — a claim about two **concurrent** runs. It was taken to
license 53 **sequential** entries each owning a dependency graph. Three properties were
conflated under it, and only the third needed a separate package:

| property | still required | how it survives |
|---|---|---|
| a trapping law takes one law, not the batch | yes — `predicate` fails by trap | each target is its own executable, run as its own process |
| `build-failed` lands on one entry | yes | `swift build --product <target>` |
| two concurrent runs don't share a `.build/` | only for single-entry callers | they keep their hash-keyed root |

**`--product` is load-bearing and was measured, not assumed.** With one deliberately
broken stub among 53: a whole-package `swift build` exits 1 and produces **zero**
binaries — one bad emission would blank an entire survey — while `--product` builds 52
and fails exactly the broken one. **`--target` is the wrong flag and lies**: exit 0, no
binary, only an entitlement plist, so a caller keying on its exit code reports "built"
for something that does not exist.

**`--max-parallel` now schedules nothing.** The concurrency existed to overlap dependency
builds that no longer happen; serial-over-one-`.build` is **8.1× faster cold** (810s →
100s) and 18× warm than 4-way-over-53.
Whether per-product builds are safe *in parallel* against one `.build` is **not
established** — arm C and the shipped run were both serial. Left unmeasured on purpose:
the flag is kept because it is a documented interface and because the *run* phase could
still use it.

**The comparison nearly reported a false green.** The frozen key writes `identityHash`
without the `0x` prefix the JSONL stream carries, so the first diff found 53 rows on each
side, an **empty intersection**, and "0 mismatches" — a loop over nothing. Printing the
size of the compared set, not just the mismatch count, is what caught it. Same shape as
the cycle27 rerun that compared against a file it had itself overwritten
([#129](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/129)); the general
form is that **a zero is only evidence when the denominator is printed beside it.**

### Road tests were misfiled, not mistimed (2026-08-03)

They were premature **as scorecards** and exactly on time **as development instruments**. The
distinction matters because the conclusion "stop road-testing" does not follow.

- The 0-of-3 run is what *found* five confident zeros. You cannot find a confident zero by reading
  code — by definition it looks like success.
- `roadtest-self-dogfood.md` has every measurement withdrawn and **19 live source sites still cite
  its diagnoses**. That is a high yield for a "premature" exercise.
- **What went wrong was publishing scores from a tool that was still changing.** The repo already
  has *"a tool may not grade its own homework"* (about answer-key contamination). The missing
  sibling: **a tool may not grade itself while it is still changing** — every score taken during
  active development is a score of a binary that no longer exists. That is §10.3's A/B rule
  (two binaries, same day, same corpora) generalised past templates.

**Backtests are not the same instrument and should not be deferred with road tests.** Their oracle
is a public fix commit that predates the tools and cannot be contaminated; they are cheap to re-run
and survive tool churn. In-repo record agrees: road-test scorecards withdrawn twice, backtests
standing (`backtest-apple-libraries.md`, and `kit-suite-backtest-plan.md` Arm 1 a clean hit).

**The trap in the position:** *"not ready to measure yet"* is unfalsifiable — the confident zero of
project planning, always defensible, forever. Write the exit criteria while inclined to be strict.
Candidates: composer reach past 38%, the 5 dead templates diagnosed, the instrument-error class
closed (Pass 2 was the big one, fixed), `--sources` no longer gating app code out of measured
verify.

### Speculative refactoring — shape and build order (2026-08-03, designed not built)

**The idea.** `swift-infer` copies the target, applies a refactor the linter suggested, derives a
law from the *refactored* shape, verifies it, and surfaces the refactor **only if the law ran**.
Output stops being advice and becomes a **patch + a law + a verdict**.

This is `prove-then-show`'s inversion — *"the test-then-surface inversion of the hide-Possible
default"* — applied to `suggest-refactors`' domain. Both commands already exist; what is missing is
the copy, the mutation, and the join between them.

**Why it is worth doing at all.** Today the linter says *"extract this kernel"* and the reader takes
it on faith; `extractable-kernel` seeds explicitly do not focus discovery, and `swift-infer` reports
"work a human must do before any tool can help" and stops. This lets it say instead: *extract this,
and here are the laws you get.* The value is **refactors that actually get done**, not more
suggestions.

**Emit a diff, not advice.** If the output is prose, the verdict does not transfer — you verified
*your* extraction and they will write a different one, and choosing the parameters is where the
design work lives. If the output is the exact code that was compiled, the claim is precise and
checkable: *paste this, and this law held over 100 trials.*

**"A patch we know would work" means two different things.** Conflating them is how the kernel tier
would over-claim:

| tier | what makes the **patch** safe | what the property test proves |
|---|---|---|
| access widening | the compiler — a visibility change cannot alter behaviour | that the **law** holds |
| kernel extraction | **nothing yet** — the extraction may not preserve behaviour | that the law holds **of that extraction** |

A passing law on an extracted function says nothing about whether the extraction preserved the
original. You can extract wrongly, get a clean law, and propose a patch that changes the program.

**Build order, by how much the PATCH needs proving** — not by how valuable the law is:

1. **Access widening.** Patch free, law proven, and **extraction ambiguity is zero**: same symbol,
   same body, one keyword. A verdict on the copy is a verdict on their code. `restricted-function`
   is 316 of 468 analysable seeds on SwiftProjectLint's own repo. **Start here** — it also builds the
   copy-mutate-verify machinery the later tiers reuse.
2. **Extract closure to a named function.** Nearly mechanical; the risk is captures and the signature.
3. **Kernel extraction.** Needs a *second* property — that the original method and the refactored one
   **agree**. That is differential/oracle testing, already in this repo's vocabulary
   (`parsing-catalog-gap.md`, holes 8/9/12). Without it, "we know it would work" is not earned.
4. **Primitive → domain type.** A redesign. No property makes that patch safe. Out.

**The linter side needs one thing, and it is not a new seed kind.** `PBTSeedsFormatter.effectiveKind`
already demotes to `restricted-function` on `TestReachability.unreachable`, so the seed ships today.
What it collapses is *why*: that case covers `private`/`fileprivate` **and** "nested inside a type
that is", and the remedies differ — for a nested member, widening the member is a **no-op**, and a
generator that got it wrong would emit a patch that unblocks nothing and then fail verification for
a reason unrelated to the law. Add a `reason`, not a kind.

**Three costs to price first.** Build cost multiplies (every candidate is its own SwiftPM workdir;
an 85-entry survey already leaves 3.4 GB) so it must be hard-gated and opt-in. A **disproven**
speculative law is ambiguous in a way a real one is not — it indicts either the code or the
extraction, and reusing `measured-defaultFails` would be dishonest, since that name means *the
property is false of your program*. And the copy is a [border claim](glossary.md#border-claim):
verify against a snapshot and report on the original, and a moved source silently invalidates the
verdict — record the source hash the way `run.json` records tool SHAs.

**The safety line survives, and reads better.** `swift-infer` still never modifies your tree; it
mutates a copy and proposes a patch, which is what every refactoring tool does.

#### Measured before building — and it changed the plan (2026-08-03)

The prerequisite shipped first (SwiftProjectLint#64: `TestRestriction`, so a patch generator can
tell "widen this declaration" from "widening it is a no-op"). Then a probe, because the population
figure answers the wrong question.

**Sampling.** 20 of the 641 `declaration`-restricted seeds on this repo — every 32nd, sorted by
`file:line`, **frozen before any was read**. Widened by line number in a throwaway worktree, then
the same `swift-infer` binary run over four targets, before and after.

| stage | count |
|---|---:|
| widened | **20** |
| gained a proposed law | **8** (256 → 264 suggestions) |
| law is **composer-supported**, i.e. `verify` can attempt it | **2** |

The two runnable are both `idempotence`. The other six are `predicate` ×3, `filter-subset`,
`comparator` — none of which has a composer, so they would be proposed, scored, rendered, and then
decline `unsupported-template`. Six of the seven distinct laws are `Possible`, hidden by default.

**Access is not the binding constraint.** Widening it moves a function from *invisible* to
*proposed-but-unrunnable*; the binding constraint is the composer set. The probe's contribution is
showing the access population lands in **the same bucket** the decline census already described.

**The first reading of this was wrong, and the error is the instructive part.** Extrapolating 10%
over 641 seeds gives ~60 runnable laws, which was written up as a disappointment — by comparing 60
against **641 seeds**, the denominator this repo explicitly warns against (*"a seed is not a
suggestion"*, glossary). Nobody had measured what 60 would be added *to*. Measured, over the same
four targets:

| | suggestions | **runnable** |
|---|---:|---:|
| default tier | 180 | 28 |
| with `--include-possible` | 256 | **100** |

So +60 is a **60% increase in the executable population**, not a rounding error. Anchoring on the
seed count made a substantial gain read as a small one.

**What each lever might be worth — CEILINGS, not predictions.** Same corpus, same binary. 156 laws
are non-runnable today and **126 of them are `predicate`**:

| lever | attemptable after | change | needs |
|---|---:|---|---|
| today | 100 | — | — |
| `predicate` composer | ≤226 | **≤+126** | no new machinery |
| access widening (item 13) | ≤160 | **≤+60** | copy-mutate-verify |

Both are **composer-supported counts**, obtained by grouping declines by template name. That makes
them comparable *to each other* and to nothing else. Composer support is **necessary, not
sufficient** — the glossary says so — so every row still has to resolve a generator for its carrier,
compile, and not trap. That attrition is unmeasured. Neither number is a count of laws that would
run, still less of laws that would *hold*.

**The ordering claim is NOT established, and the reason is worth more than the claim.** These levers
were ranked by **count**, in a repo whose standing rule is *score refutability, not suggestion
count*. A totality law over a function that never traps passes every time, and 126 new green results
that cannot fail is the [Daikon trap](glossary.md#daikon-trap) wearing a composer — *"a wall of
green unrefutable passes is the Daikon trap in a new costume."*

The counter-argument is real and also unmeasured: `predicate`/totality is **role-entailed**, a law a
*correct* implementation cannot fail, which is the combination a law wants. A green pass there is a
guard against future change rather than noise. Both readings are available and nothing here decides
between them.

**What is actually known:** `predicate` is the largest blocked population, and `predicate` +
access widening compose — after a composer the probe's own 8 proposals go from 2 attemptable to 5,
so the composer makes item 13 better rather than redundant. **What is not known:** whether unblocking
`predicate` yields refutable laws or a wall of green. That is cheap to settle — take a handful of
the 126, hand-write the totality law, and ask whether any plausible wrong implementation traps.
Do that before committing to the order.

The probe cost about twenty minutes. Recorded because the habit is worth more than the result, and
the record now has **two** corrections stacked on one measurement: the extrapolation was first read
against the wrong denominator, and then the corrected reading was used to rank two options by a unit
this project explicitly rejects. Neither error was in the measuring.

#### Are `predicate` laws refutable, or a wall of green? — answered (2026-08-03)

**Not a wall of green.** Two independent readings of the same 126:

- **Measured, all 126:** **35 (27%)** already contain an explicit totality-shaped guard — 17 count
  bounds, 12 `isEmpty` checks, 8 optional-`first` guards, 2 index-domain aware. An author had to
  think about emptiness or bounds in a quarter of these functions.
- **Judged, a 20-sample** (every 6th, sorted by `file:line`, frozen before reading): roughly **half**
  operate on domains where a plausible implementation traps — string index walking, positional
  collection access, force-unwrapped `first`. `looksLikeMobiusNext` is the clean case: total as
  written, and `returnType.firstIndex(of: ",")!` is an entirely natural way to write it.

**The concrete framing.** For those 35, the totality law is a **regression test on a guard that has
none**. `isOptional`'s `type.count > 1` does no classifying work — it is there so the function is
total — and deleting it turns nothing red today.

**Limits, because both numbers are soft in different directions.** 27% is a *lower-bound proxy*: a
guard proves the author hit the issue, its absence does not prove safety, since totality is often
implicit in the operations chosen. The ~50% is judgement over 20 functions, not a measurement.
Neither says the law would *fail* on shipped code — it will not; refutability asks whether a **wrong**
implementation would be caught.

**A method note worth more than the result.** The first pass classified by regex — force unwraps,
subscripts, division — and returned **1 of 20**, with that one a false positive (`/` inside a
comment). The regex asked *"does this implementation trap?"* when refutability asks *"would a
plausible implementation be rejected?"* Different questions; the cheap proxy answered the wrong one,
which is the fourth instance today of measuring through a proxy that does not cover the claim.

**What it settles:** the wall-of-green objection to the `predicate` composer is gone. **What it does not:** the
precise ranking of 14 against 13 — refutability was measured for `predicate` and not for access
widening's output, though that output's 2 runnable rows were both `idempotence`, a conjecture
template a wrong implementation can fail by construction.

### Signature, not carrier — the largest measured blocker to running laws (2026-08-03, scoped not built)

**The finding.** `verify --all-from-index --template predicate` over this repo, after the
`--target` derivation fix, resolves 126 entries into:

| outcome | count |
|---|---:|
| ran and held | **54** |
| compile: type not in scope (cross-module) | 37 |
| compile: n-ary predicate | 19 |
| no generator for carrier (SwiftSyntax nodes) | 11 |
| trapped — declined as domain evidence, correctly | 4 |
| other | 1 |

Two error buckets dominate, and they are **not two defects**. `SemanticIndexEntry` records
`carrierTypeName` — **singular** — and `primaryFunctionName` carries argument *labels* only
(`matches(typeName:inheritedTypeNames:)`). So:

- a predicate taking `(A, B)` cannot be composed, because nothing says what `B` is — **19 rows**;
- a predicate over a type declared in another module cannot be imported, because nothing records
  which module any type lives in — **37 rows**, of which **31 are `FunctionSummary` alone**.

One missing fact, two symptoms, **56 of the 72 non-running rows (78%)**.

**The data already exists and is dropped.** `FunctionSummary.parameters[].typeText` carries every
parameter type at scan time, and `FunctionSummary.location.file` carries the file;
`TypeShapeBuilder` reads `decl.location.file` too. Neither survives projection into the index.

**Where it must NOT go.** `Discover.PipelineResult.typeShapesByName` is
`[String: PropertyLawCore.TypeShape]` — the **kit's** type, owned by SwiftPropertyLaws. Putting a
module or source path on it is a cross-repo change plus a pin bump, for a fact the kit has no use
for. The established alternative is a **sidecar map keyed by type name**, and this would be the
third: `inheritedTypesByName` exists because the shape merges same-file extensions only, and
`genericParametersByName` exists because — in its own words — *"`TypeShape` does not carry them …
which is why `scaffold-kit-suites` wrote `Deque.self`"*. Same shape of gap, same remedy.

**The change, in five pieces.**

| # | what | where |
|---|---|---|
| 1 | `sourceFileByTypeName: [String: String]` | `Discover.PipelineResult` — third sidecar map, no kit change |
| 2 | `parameterTypeNames: [String]?` on the entry | `SemanticIndexEntry` + the projection; straight pass-through from the summary |
| 3 | persist the sidecar beside `typeShapes` | `IndexStore` / `IndexCommand` |
| 4 | import set = union of modules over every type the recipe touches | the stub emitter, via **`VerifyTargetInference.module(forLocation:)` — already shipped**, so no new concept |
| 5 | draw one value per parameter, not one per law | `composePredicatePass` |

**Rollout is graceful and needs no schema bump.** `SemanticIndexEntry` has a hand-written
`init(from decoder:)` using `decodeIfPresent`, so an added optional decodes as `nil` from an
existing index and verify falls back to today's behaviour. `reindexIfNeeded` then repopulates it on
the next stale read, which shipping the code itself triggers.

**≤+56 is a CEILING, not a prediction** — the same discipline items 13/14 are held to. Composer
support is necessary, not sufficient: an n-ary predicate still needs a resolvable generator for
*each* parameter carrier, and the 11 SwiftSyntax declines are evidence that some will land exactly
there. The honest claim is *up to* 110 of 126 (87%), with the attrition inside that unmeasured.

**Two known limitations, stated rather than discovered later.** The sidecar is keyed by **bare type
name**, so two modules declaring the same type name collide — an existing limitation of
`typeShapesByName` that this inherits rather than introduces. And a stub importing N modules builds
more than one importing one; this survey already costs ~35 min and ~72 GB for 126 entries.

**How to measure it.** Re-run the identical command — `verify --all-from-index --template predicate
--max-parallel 4` — per §10.3: two binaries, same day, same corpus, never against a remembered
count. **The run above IS the before-binary measurement**, taken 2026-08-03 at `1d39745` plus the
`--target` derivation. Do not substitute a recollection of it.

### Signature, not carrier — the measured close (2026-08-03)

Three binaries, same 126 entries, same afternoon — the §10.3 shape, and the reason the numbers are
comparable at all.

| bucket | A: `--target` | B: `+signature` | C: `+fixes` |
|---|---:|---:|---:|
| **ran and held** | 54 | 94 | **104** |
| compile: type not in scope | 37 | 0 | **0** |
| compile: arity | 19 | 7 | **0** |
| no generator for carrier | 11 | 20 | 17 |
| trapped — domain evidence | 4 | 4 | 4 |
| other | 1 | 1 | 1 |

**Both compile buckets closed. `≤+56` realised as +50**, and the 6 it fell short by are visible
rather than unexplained: carrier declines rose 11 → 17. Those entries did not get worse — they
stopped failing at compile and started failing earlier, at generator resolution, which is where
they were always going to fail. `DefaultFileSystemReader` was never generatable; saying so beats
reporting a missing argument count.

**Three defects sat between "written" and "runs" for the `predicate` composer** — it was
unreachable at gate 2, then never-composing because a compile-time value escaped as a
runtime one — and every one was invisible to the unit tests that call the composer
directly. That is the general shape: a composer's unit tests exercise the composer, and
these defects were all in what reaches it.

**Two further defects that only running it could find**, both invisible to those tests:

1. **The receiver is an implicit parameter.** `receiverCallExpression` renders `{ $0.method($1) }`,
   so an instance method's closure takes `parameters + 1` values. Exactly 7 entries, and all 7 had
   been failing on a missing type first — *a refuter that fires first hides every refuter behind
   it*, which is a design decision in this repo and turned out to describe its own measurement.
2. **The n-ary path dropped the resolver.** `emit` builds a `GeneratorResolver` from `allShapes`;
   the totality composer re-resolved per parameter without it, so nested custom types could not
   derive. Five `FunctionSummary` laws declined for a type that derives fine on the unary path —
   which never noticed, because it is handed an already-resolved recipe. **Anything that
   re-resolves must re-resolve with the same resolver.**

**What remains is a different kind of problem.** Of 22 non-passing, **17 are carrier declines** and
14 of those are SwiftSyntax nodes or optionals — nothing derives generators for those, and it is
not more plumbing. Plus `[String: TypeShape]` ×2 and `[TypeDecl]` (containers of custom types),
4 traps the carrier gate correctly refuses to call refutations, and 1 undiagnosed build failure.

**And 104 laws holding is not 104 findings.** Zero refutations across all three runs. These are
executable regression guards on code that is currently correct — the refutability prediction, and what
*score refutability, not suggestion count* requires be said out loud.

### Access widening, re-measured — the read was right about the cause and wrong about the lever (2026-08-04)

Item 3 asked for a **pre-check**: do the widened functions' parameter types land in the same
carrier-decline bucket the residual 17 do? Then it asked for the re-measurement. Both were run,
in that order, and the pre-check turned out to answer a *narrower* question than it was asked.

**Apparatus, stated first because one detail invalidated the first attempt.** 641
`declaration`-restricted seeds (the identical figure to 2026-08-03), sorted by `file:line`, every
32nd — indices 31, 63, … 639, exactly 20 — **frozen to a file before any body was read**. Two
worktrees at `1e0218e`, pristine and widened. Two binaries, **same day, same trees**, per §10.3:
**A** = `7e7a633` (the last commit before the `predicate` composer) and **B** = `1e0218e`. The
index — not `discover`'s prose — is the instrument, because it is JSON, it defaults to
`--include-possible`, and it is the artifact `verify --all-from-index` actually consumes.

> ⚠ **These are not the same 20 functions as 2026-08-03.** That list was never recorded — only
> the aggregate was. The sampling *rule* is reproduced exactly and the seed population is
> identical (641), but function-level comparison to the old run is not available. Read the old
> `20 → 8 → 2` as context, never as this table's before-column; the before-column is binary A.

**The funnel, executed.**

| stage | A (`7e7a633`) | B (`1e0218e`) |
|---|---:|---:|
| widened | 20 | 20 |
| index entries, pristine → widened | 249 → 255 | 249 → 255 |
| **gained a proposed law** | 6 | 6 |
| composer-supported | 4 | 6 |
| **ran a law** | **0** | **3** |
| held | 0 | 1 |
| refuted | 0 | 2 |

**The recorded read is refuted, and not by the lever it was filed under.** *"Widening moves a
function from invisible to proposed-but-unrunnable"* was true of binary A and is false of HEAD.
But the `predicate` composer is **not** what changed it — the composer moved 2 rows from
`unsupported-template: predicate` to `unsupported-carrier: FunctionDeclSyntax` /
`InheritanceClauseSyntax?`, which is a **more honest decline and still zero laws run**. What made
laws run was the signature-not-carrier cross-module import fix: all three `idempotence` rows failed under A with
`build-failed: cannot find 'LiftedTestEmitter' in scope` (and `IdempotenceStubEmitter`,
`Suggestion`) and execute under B. **The two levers were ranked against each other; the one that
mattered here was neither.**

**The pre-check was right, and it was answering a smaller question than it was asked.** It
predicted 3 of 20 SwiftSyntax carriers against 14 of 17 in the residual list, i.e. *not the same
bucket*. Measured: the two rows that reach a carrier decline are **exactly** rows 10 and 20 of
the pre-check, declining on `FunctionDeclSyntax` and `InheritanceClauseSyntax?` — the residual
bucket named verbatim. So the bucket prediction held **per row**. What it could not predict is
**which functions gain a law at all**: 6 of 20 did, and two of the five all-primitive rows
(`source`, `manifest`) gained nothing, because the template gate — not the carrier — decides
whether a law is proposed. Parameter types predict whether a proposed law can *run*; they say
nothing about whether one is *proposed*. The pre-check conflated the two, cheaply and recoverably.

**3 ran is not 3 wins, and this is the first time that was visible.** One is a real regression
guard (`sanitizeKeyPathForIdentifier` — strips a leading `\.`, then `.`→`_`; genuinely
idempotent, `measured-bothPass` at 100 + 100 trials). **Two are false laws refuted at trial 0**:
`complexDoubleEdgePass` is a source-*template* emitter, so applying it twice embeds the block
twice, and `rebuildWithCounterSignal` **appends** a signal and a caveat per call, so `f(f(s))`
carries the counter-signal twice and scores −50 instead of −25. Neither is a bug; both are
`idempotence` firing on a `T -> T` shape that is not idempotent. Both sit at `Possible` (score
35), hidden without `--include-possible`. **The 2026-08-03 funnel could not see this at all** —
nothing ran, so precision was unmeasurable, and *"2 composer-supported"* silently read as
2 prospective wins. Against *score refutability, not suggestion count*: the honest yield of
this sample is **1 guard, 2 false proposals, 3 declines**.

**A trap that cost a full run, and it is the one item 13's design already warned about from a
different direction.** The first widening rewrote `private ` → `internal `, which is the obvious
spelling of "widen access". It gained **exactly nothing**: 249 → 249, *identical* identityHash
set. `FunctionScanner` skips explicit `internal` too (cycle 148, Lever A) — it reads the token as
deliberate SPI, and Swift's default access carries **no token**, which is the shape the scanner
accepts. So a patch generator that emits `internal` produces a patch that compiles, changes
nothing, and then fails verification for a reason unrelated to the law — the exact failure item
13 anticipated for members nested inside a `private` type, arriving from a second, unrelated
cause. **The patch must delete the modifier, not replace it.** Measured, not argued.

**What this does to the ordering.** Item 13 no longer produces unrunnable output, so the reason
to defer it is gone. But the case *for* it is now smaller and better-founded than the ceiling
suggested: 20 widenings → 6 laws → 3 executions → **1 correct law**. Extrapolated over 641 seeds
that is roughly 32 correct laws and 64 false proposals — a real gain and a real precision cost,
where before there was only a count. The widened tree **compiles clean**, so the access tier's
"the compiler makes the patch safe" claim is confirmed rather than assumed.

### Idempotency vocabulary — surveyed, not yet decided (2026-08-04)

Raised while scoping speculative *annotation* (item 13's cousin: add an annotation to a copy,
verify, propose it only when the law ran). Recorded as a survey because the decision is the
user's and the facts were not written down anywhere.

**The first read of this was WRONG and the correction is the useful part.** I claimed the
SwiftIdempotency and swift-infer vocabularies "don't meet, with nothing asserting they match."
The second half is item 4 and is true. The first half is false: **`EffectAnnotationParser` in
SwiftEffectInference already parses the entire SwiftIdempotency family**, bilingually — attribute
form (`@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)`, `@Pure`)
*and* doc-comment form (`/// @lint.effect …`, `@lint.determinism clock_deterministic`) — with the
names configurable through `AttributeRecognition`. swift-infer already depends on it. The join
exists; it is simply almost unused.

**Three vocabularies, three genuinely different jobs. That part is healthy.**

| package | ships | job |
|---|---|---|
| SwiftIdempotency | `@Idempotent` `@NonIdempotent` `@Observational` `@ExternallyIdempotent(by:)` `@Pure` `@ClockDeterministic` | *what this function does* |
| SwiftPropertyLaws | `@Discoverable(group:)` `@PropertyLawSuite` `@ValueSemanticTests` … | *what to discover / generate suites for* |
| **this repo** | `@CheckProperty(.idempotent / .roundTrip(pairedWith:) / .preservesInvariant(_:))` | *which law to check* |

**The real inconsistency is one row of overlap, and it is duplicated FUNCTION, not spelling.**
`@CheckProperty(.idempotent)` expands into a peer `@Test func` (`CheckPropertyMacro`, M5.2);
SwiftIdempotency's `@Idempotent` + `@IdempotencyTests` does the same job. Two packages generating
idempotency tests from an annotation.

**And this repo reads neither half it owns.** `AttributeScanner` reads only the
`.preservesInvariant` arm — its own comment says `.idempotent` and `.roundTrip` "are ignored
here." `EffectAnnotationParser` is called at exactly **three sites, all `isClockDeterministic`**
(`FunctionScannerVisitor+Summary`, `ViewModelDiscoveryVisitor`, `ReducerDiscoverer`). Everything
else in the effect vocabulary is parsed by a linked dependency and consumed by nothing.

**Two defects found while checking, both small and both real:**

- `AttributeScanner`'s doc comment says it recognises `@CheckProperty` and that "SwiftInferProperties
  does not take a runtime dependency on **`PropertyLawMacro`**'s definitions". But `@CheckProperty`
  is **this repo's own macro** (`Sources/SwiftInferMacro/CheckProperty.swift`) — the comment
  attributes a local macro to another package. House failure mode, again.
- **`@ClockDeterministic` is deliberately OUTSIDE `AttributeRecognition`** and hardcoded — SEI's own
  comment says so in as many words. So the one annotation swift-infer depends on for admitting
  `async` is the single name that is neither configurable nor contract-tested. That is item 4's
  precise bite, now with a named target instead of a general worry.

**The order that was proposed, and the trap in reversing it.**

1. **Make swift-infer READ the effect vocabulary.** No cross-repo change — the parser is already a
   dependency. `@Idempotent` as corroboration; **`@NonIdempotent` / `@Observational` as vetoes**.
   This lands on the same afternoon's false-positive work: an author-declared `@NonIdempotent` is
   exactly the signal that kills a shape-only score-35 candidate, and SwiftIdempotency has
   spellings for the negative and conditional cases (`@ExternallyIdempotent(by:)`) that this repo
   cannot express at all. It also gives SwiftIdempotency its first stage in the toolchain.
2. **Then** converge authoring — retire `.idempotent` from `CheckPropertyKind`, keep `.roundTrip`
   and `.preservesInvariant` (no SwiftIdempotency equivalent).
3. **Then** the item-4 contract test, against the hardcoded `@ClockDeterministic` name.

**Doing 2 before 1 is the worst order**: it removes a working test generator and replaces it with
an annotation the tool cannot see — a rename that fails as a *missing* annotation, which is item
4's failure mode reproduced by hand. Same shape as the `private` → explicit `internal` no-op
measured the same day.

**Step 1 shipped the same day** ([#78](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/78)), with one caveat against the framing that sold it — and dogfooding it then corrected the weight from +40 to +15 (see below). This
repo carries **zero** effect annotations in its own sources — the `@lint.effect` hits are all code
*about* the annotation — and SwiftIdempotency is not a dependency here. So a `@NonIdempotent` veto
would affect **0 of the 13 false positives measured the same day** (the `idempotence` survey). It is a
**capability, not a fix**: it gives an author a way to kill a false law, it does not kill one.
The shape-based work and the annotation-reading work attack the same class from opposite ends,
and only one of them helps a codebase that has annotated nothing — they should not be scored
against each other. What does hold up is the dependency-free part: the doc-comment spelling
`/// @lint.effect idempotent` needs no package dependency, so the veto is usable without adopting
SwiftIdempotency. And the tool **already speaks this vocabulary outbound** —
`discover --effect-annotations` recommends `/// @lint.effect pure` lines
(`EffectAnnotationAdvice` / `EffectAnnotationRenderer`) — and reads none back. One tool talking to
itself in English, which is the *consumer keeps asking the producer* observation with both ends in
the same repo.

#### Does `@ClockDeterministic` belong in SwiftIdempotency? (folded in 2026-08-04)

Raised as *"I think it was bolted on later for the infer-properties work"*. **The timing claim is
exactly right** — `@Idempotent` dates from 2026-05-19; `@ClockDeterministic` and `@Pure` both
landed 2026-07-10, the latter committed as *"closing the recognizer-first gap"*: the recognizer
existed first and the macro was shipped afterwards so the attribute spelling would compile.

**Two questions, and merging them is the trap.**

**Does it belong to the idempotency LATTICE? No — and four fences already say so**, none of them
added by this conversation:

1. Its own doc header: *"Not an effect tier … attaching it grants no lattice trust — it makes a
   **determinism** claim."*
2. A different doc-comment namespace — `@lint.determinism`, where every other marker is
   `@lint.effect <tier>`.
3. SEI **excludes it from `AttributeRecognition`**; the configurable set is
   pure / idempotent / nonIdempotent / observational / externallyIdempotent, and this one gets a
   bespoke `isClockDeterministic(declaration:)`.
4. `Effect` has five ordered tiers. `@lint.determinism` has **exactly one legal value**
   (`clock_deterministic`) — a singleton namespace beside an ordered lattice.

**Does it belong in the PACKAGE? Probably yes, and the two arguments that look decisive both
fail.** *"SwiftIdempotency does not consume it"* is true — and true of **all five markers**, which
are `EmptyPeerMacro {}` and expand to nothing; the whole family is vocabulary, so this does not
separate it. *"It landed late"* fails too: `@Pure` shipped the **same day** for the **same**
recognizer-first reason and is uncontroversially the lattice bottom. And every alternative home is
worse — moving it to swift-infer would have **SEI (upstream, shared with SwiftProjectLint)
recognising a name owned by a downstream package**; SwiftPropertyLaws is a real candidate since it
ships the law that falsifies the claim (`TimedAsyncSequence.debounceIsDeterministicUnderTestClock`),
but its macro vocabulary is suite generation, not claims; a package for one marker is overkill.

**So the problem is not location — it is that the package silently plays two roles** (the
retry-safety lattice, and the toolchain's marker-macro home) and only the first is named.
`@ClockDeterministic` is a tenant of the second, defended by four fences and stated as a structure
nowhere.

**The concrete cost, which is the part worth acting on.** Because it sits outside
`AttributeRecognition`, it is the one annotation in the toolchain that is **neither configurable
nor contract-tested** — and it is the one swift-infer depends on to admit `async` at all. That is
open item 4's target. Either give it a `determinism` field in `AttributeRecognition` (a **separate**
field, not an effect tier — the orthogonality is real and worth keeping) or write the contract
test. Doing neither leaves a rename failing as a *missing* annotation, indistinguishable from
unannotated code.

### The `@EffectUnknown` dependency chain (2026-08-04)

Recorded because the chain is four links long, crosses three repositories, and
its **first** link is an open performance issue — which is not a connection
anyone would guess from either end.

**Where it started.** Item 17's step 1 made swift-infer read the effect
vocabulary, and dogfooding it surfaced a gap: an author who means *"I cannot
guarantee idempotency here"* had no way to say so. `@NonIdempotent` claims
something strictly stronger — SwiftIdempotency defines it as **unconditionally**
non-idempotent, *"re-invocation produces additional observable effects (sending
email, inserting rows, publishing events)"*. The tier that does mean "cannot
determine" is `unknown`, which had been in the reference lattice from the start
and was **inference-only**: no spelling, so no way to write it down.

**Link 0 — shipped.** `@EffectUnknown`
([SwiftIdempotency#3](https://github.com/Joseph-Cursio/SwiftIdempotency/pull/3)),
marker-only, plus `/// @lint.effect unknown`. Also corrected two stale
`REFERENCE.md` claims found while checking — the table gave `pure` no macro and
the prose called `pure`/`unknown` "tiers that need no marker", but `@Pure`
shipped 2026-07-10.

| # | link | state |
|---|---|---|
| 0 | SwiftIdempotency ships the marker | **done** |
| 1 | SEI learns to *read* it | **now the only blocker** |
| 2 | swift-infer bumps the SEI pin | **done 2026-08-04** — `bfcf0e3` |
| 3 | swift-infer suppresses on it | waiting on link 1 |

**Links 2 and 3 came unblocked the same day**, by fixing [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) rather than
working around it — the `~2×` regression that made the pin unbumpable is gone, and
the bump landed past it. What is left is the one link that was never about
performance.

**Why the reader must live in SEI.** swift-infer could parse `@lint.effect`
itself, and that is precisely what `EffectAnnotationParser` exists to prevent —
one grammar, shared by SwiftProjectLint and swift-infer, is the reason the
vocabulary has not already drifted. Re-implementing it downstream would buy
speed now and a second dialect later.

**Why that blocks on a performance issue.** swift-infer pins SEI at
`1f2265a0`; SEI's HEAD is `097181a`, the commit [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) records as a
`~2×` regression on the whole-domain purity path and names as blocking the pin
bump. So the reader cannot ship without either moving past that commit or
branching SEI from the old pin — and a divergent branch is worse than waiting.

**Deliberately NOT in the chain: an `Effect` case.** `unknown` is *incomparable*
to `non_idempotent`, so admitting it to SEI's `Effect` enum would force its
linear five-tier chain into a genuine partial order and replace the rank-only
`lub(_:)` with a Hasse-diagram join — a change SEI declined for exactly this
tier. Link 1 should therefore read it the way `@ClockDeterministic` is read: its
own predicate, outside `AttributeRecognition`, answering its own question. That
keeps the chain to a reader rather than a re-derivation of the core algebra.

**The honest state until then: the marker documents intent and nothing acts on
it.** Which is the very condition it was built to end — a declaration that is
indistinguishable from an unannotated one. Worth saying plainly rather than
letting "shipped" imply "working".

### The `Gen<URL>` defect — fixed, after a wrong diagnosis worth keeping (2026-08-04)

Item 19, closed. Two lines in this repo, no kit change, no version bump. **The first
diagnosis of it, published earlier the same day, was wrong**, and the way it was wrong
is the more useful half.

**What it actually was.** `Gen<T>` comes from `PropertyBased`; the Foundation
generators — `Gen<URL>.url()`, `.uuid()`, `.data()`, `.decimal()` — are **extensions in
`PropertyLawKit`**. The algebraic verify workdir declared `PropertyLawComplex` and not
`PropertyLawKit`, and the strategist stub imported `PropertyBased` alone, so the
expression the kit handed us referenced an extension the file could not see.

**Why the kit is not at fault.** `CompositeMemberParser` omits `PropertyLawKit` from
`requiredImports` **deliberately**, saying these are *"the generators every derivation
consumer already imports"* and naming `GeneratedFileEmitter` / `ScaffoldFileEmitter`.
True of the kit's own emitters. False of a verify stub — which is a
[border claim](glossary.md#border-claim) about a consumer in another repository, and we
were the consumer violating it. `.interaction` and `.valueSemantics` already declared
the product; `.algebraic` was the outlier.

**The wrong turn, recorded because it cost a cross-repo refactor.** The first pass added
the product and the import by hand, ran the binary **directly**, and hit
`dyld: Library not loaded: @rpath/libTesting.dylib`. That was written up as *"the obvious
fix builds and then does not run"*, and a `PropertyLawFoundation` carve-out was built in
SwiftPropertyLaws to move the generators out of a Testing-bound module.

Three things falsified it, in order:

1. A probe importing **only** the new Testing-free target still failed to launch — so
   `PropertyLawKit` was never the source.
2. **`swift-property-based` itself imports `Testing`** (four files). Every verify stub
   ever emitted links it.
3. `VerifierSubprocess` **already injects `DYLD_LIBRARY_PATH` / `DYLD_FRAMEWORK_PATH`**
   for exactly this, and says so — V1.53.A, tracing cycle-49's 12 parse-error picks to
   this same `dyld` message.

So the launch failure was an artefact of running the binary outside the harness that
exists to run it. **The lesson is not "check the harness" but something narrower: a
reproduction that skips the caller is not a reproduction.** The carve-out was reverted
unpushed.

**Measured after the fix**, every `URL`-carrier row on this repo:

| | before | after |
|---|---:|---:|
| execute | 0 | **11 of 13** |
| held | 0 | 2 |
| **refuted** | 0 | **9** |

The 9 refutations are the `defaultPath(for:)` family, and they are **not new bugs** —
they are `appendingPathComponent`, which the `idempotence` frozen classifier flagged as
`extension` (the output extends its input, so it cannot be idempotent). Nine blind
predictions, nine confirmations, on rows that could not run when the prediction was made.
That is the strongest evidence the classifier has, and it arrived from a defect fixed for
an unrelated reason. The 2 remaining non-executing rows are a different class
(`cannot find 'Scaffold' in scope` — the cross-module import fix's residual, not this).

### Adopting `verdict(for:)` — the measurement argued against the obvious version (2026-08-04)

Item 2's last piece, and the A/B ran **before** the build rather than after it.

**The population, measured on 2,500 functions in this repo:** 2,206 `.pure`, **35
`.pureButPartial`** (1.4%), 259 `.refuted`. Those 35 are everything adoption could
newly admit.

**Why the literal reading of "adopt `verdict(for:)`" is wrong.** `isInferredPure` has
exactly **one** consumer — the `/// @lint.effect pure` advisory. It gates no law, no
score, no template. So adopting the verdict *there* would mean advising 35 partial
functions `pure`, and that is false: SEI defines the tier as *"no side effects,
deterministic, **and total**"*, and the lattice has **no tier** for
deterministic-but-partial. There is nothing honest to tell them, so the advisory is
deliberately unchanged.

**What was adopted instead** is the half that is not a lie: `SoundPurity.verdict(for:)`
and `FunctionSummary.purityVerdict`, carrying the state the Bool collapse destroyed.
Before this, `isPure` answered `false` for all **294** non-pure functions alike —
nothing downstream could distinguish *"reads the clock"* from *"raises its own error"*.
The information was being discarded at the scan boundary, which is the same shape as
every other producer→consumer loss in this toolchain.

**The soundness worry is real and does not apply.** Admitting `throws` resembles the
relaxation this project warns about — *"removing the `throws` gate once re-admitted
`Process`/`Pipe`/`FileHandle`/SQLite at once"*. It is not: `.pureButPartial` requires
the body contain **no `try` at all**, so a throw propagated from a dependency still
refutes. Only a function raising its own errors qualifies. Pinned by a test, because
the resemblance is close enough to be worth guarding rather than explaining.

**A/B: 251 → 251 suggestions, and the only 12 differing lines are self-referential** —
the docstring advisory went 139 → 140 because the new `verdict(for:)` is itself a
documented function in the scanned corpus, plus two line-number shifts. The tool
noticed the function just added to it.

**The 35 stay unconsumed on purpose.** They are waiting on a consumer that can narrow a
law's domain to the non-throwing inputs, which is what `PurityVerdict`'s own doc says
the method is for. Filing them as available beats inventing an annotation tier to
justify reading them.

**The regression that made this adoption possible is fully closed, with no second fix to
chase.** [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) was a `~2×` cost on the whole-domain purity path;
[SEI#2](https://github.com/Joseph-Cursio/SwiftEffectInference/pull/2) removed it by
stopping `inferredEffect(for:)` delegating to `verdict(for:)`, which cannot check
`throws` until *after* the body walk. That delegation was the **entire** cost — the
erased-`Syntax` generalisation the issue also suspected contributes nothing measurable —
so SEI performance is not a live thread here.

### Was SwiftProjectLint paying the purity regression? No (2026-08-04)

The suspicion was reasonable: SPL calls `PurityInferrer` from two visitors over every
function *and closure* in a project, so it has more calls into that path than anything
else. It was still wrong, and the way it was wrong is the useful part.

**Measured, §10.3 shape.** Two *release* binaries from one commit differing only in the
three SEI manifest lines, alternating runs over a 564-file corpus:

| run | `097181aa` (regressed) | `bfcf0e3` (fixed) |
|---|---:|---:|
| 1 | 8.15s | 8.16s |
| 2 | 8.23s | 8.40s |
| 3 | 8.42s | 8.42s |

Indistinguishable.

**The mechanism, which matters more than the number.** SPL calls
`PurityInferrer().verdict(for:)` and `PurityInferrer().isPure(accessor:)`. It **never
calls `inferredEffect(for:)`** — and that was the only method [SEI#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1) regressed, by
delegating to `verdict` and inheriting a body walk before the `throws` check. SPL was
already asking the question that legitimately costs the walk, so there was nothing to
inherit. The fix helps swift-infer, which asks the whole-domain question, and is a
genuine no-op here.

**A null result is only worth recording with a mechanism**, otherwise it is
indistinguishable from a measurement too coarse to see the effect. This one has both.

**Incidental, and larger than the thing being measured**: while checking that both arms
produced identical findings, they did not — and neither did the same binary run twice.
**476 of 3,844 findings (12.4%) report a different LINE between identical runs**, 472
of them the two cross-file *could be private* rules. Filed as
[SPL#67](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/67). The `pbt-seeds`
manifest is stable across three runs, so the lint→infer hop does not carry it.

**One method note, because it nearly became a false finding.** A first pass compared
seeds keyed on `(file, symbol)` and reported 238 "moved" seeds. Overloads share that key
— two `merge` functions in one file — so the dictionary collapsed them and the
comparison was meaningless. The multiset comparison on `(file, line, symbol, kind)` is
the correct one, and it says stable. Same shape as the day's other near-misses: the
cheap key answered a different question from the one being asked.

**SPL#67 is fixed, and verified here rather than read off its state (2026-08-05).**
[SPL#68](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/68) measures a cross-file
finding against its own file instead of the last one walked, and walks the cache in path
order. Re-measured from a binary built at that merge, three runs over this repo: **752
findings each, `(file:line, rule)` multiset identical**, including all 159
`Could Be Private Member` rows — 472 of the original 476. The residual is **order, not
content** (624 of 752 findings change position), filed as
[SPL#69](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/69) and irrelevant to
the hop, since `pbt-seeds` is stable.

### The `idempotence` false-positive rate, and the veto it earned (2026-08-04)

Item 18, closed. Survey of all 72 `idempotence` entries via `--all-from-index` at `1e0218e`:
**55 executed, 13 refuted — a 24% false-law rate**, and **every refutation sits at score 35**, the
shape-only floor (+30 type symmetry, +5 value semantics, no name signal); 0 of 4 at score 55. Read
beside `leaderboard-sort`'s finding that the score is *inverted* inside the 30–45 band — different
corpora, different bands, both measurements stand.

**A classifier frozen before any verdict existed.** Hypothesis: an idempotent function *projects*
onto a normal form, so its result is a **sub-part** of its input; a result that **extends** its
input cannot be idempotent. Recorded to `classification-FROZEN.json` at 0 verdicts, then scored:
**precision 5/6, recall 5/13**, 83% false-law rate in the `extension` class against 9% in
`reduction`.

**The decision turned on where those rows surface, not how many there were.** Score 35 is
`Possible`, **hidden from default output**, so PRD §3.5's *raise thresholds, don't add filters* — an
argument about reader-facing volume — never applied. What false laws actually cost is **index and
verify hygiene**: the index defaults to `--include-possible` by design, and each row burns a full
SwiftPM build in `--all-from-index`. That reframing is what made a tenth veto defensible where a
tenth *filter* would not have been. The precedent is exact: `orderSensitiveCarrier` vetoes because
*"the suggestion is genuinely wrong, not merely low-confidence"*, and a result built **around** its
input applies the construction twice. Falsity, not doubt.

| | before | after |
|---|---:|---:|
| `idempotence` rows | 72 | **54** |
| measured refutations removed | — | **8 of 13**, plus the 9 `defaultPath` rows |
| laws that HELD and were vetoed | — | **none** |

**Read the RETURN expression and nothing else** — the finding, not an implementation detail. A
body-wide scan calls `quoted(_:)` a normalizer (it runs `replacingOccurrences` and *then* wraps) and
calls a dedup an extender (`.append` appears while it filters). Both readings are wrong and both
come from looking in the wrong place. The frozen prototype's single false alarm came from its
body-wide fallback; dropping it cost no recall. *Where* you look beats *what* you look for.

**Three things the measurement forced that reasoning did not.**

1. **SwiftSyntax does not fold operators.** `text + "."` parses as `SequenceExprSyntax`, not
   `InfixOperatorExprSyntax`. The first concatenation check keyed on the folded node, looked
   correct, and fired **never** — the exact failure this classifier exists to catch in others.
2. **A bare `+` rule vetoed two laws that HELD.** `prioritised` is
   `kernels.filter{…} + kernels.filter{…}`; `unwrappingRepetition` is `Array(leading) + loopBody`.
   Both operands derive from the input, so `+` there is a **reordering**, not growth. The rule now
   requires a **literal** operand; both are pinned as regression tests.
3. **`IndexStore.upsert` keeps historical entries**, so the first re-measurement showed the veto
   firing on nothing. Delete the index before an A/B or it reports the union of every run.

**An apparatus bug caught before it became a finding.** Six rows first failed
`cannot find type … in scope`, which reads exactly like a residual of the signature-not-carrier cross-module import
fix. It was mine — the filtered index's `sourceFileByTypeName` pointed into a deleted worktree.
**Third instance in one day of the same shape**, and the standing lesson: *the harness fails in ways
that look precisely like the tool failing.*

**Domain transfer stays unclaimed** — `T -> T` where the output is a different *kind* of thing (a
hash, a rendered name, a seed string), so `f(f(x))` is meaningless though it type-checks. That is
the residual, and what the `_description` and capacity-from-scale vetoes have chased **by name** for
cycles. Not characterised well enough to veto on, and a veto that fires on a guess suppresses true
laws — the failure that cannot be seen from the outside. **Re-measured 2026-08-05** on the
whole-corpus survey: 24% → **10.6%** with the `extendsInput` class producing ZERO refutations, and
all survivors domain transfer. Now [#93](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/93).


### The whole-corpus number, and the "regression" that was not one (2026-08-05)

Item 4, closed. `verify --all-from-index` with **no `--template` filter**, release binary at
`1ef7128`, `--max-parallel 4`. **139 of 281 entries execute a law: 130 hold, 9 refute.**
76 min wall, 7.7 CPU-hours, 107 GB of workdirs, 2.45 GB peak RSS.

| template | n | ran | held | ref | why the rest did not run |
|---|---:|---:|---:|---:|---|
| `predicate` | 129 | 76 | 76 | 0 | 49 no generator · 4 trap |
| `idempotence` | 54 | 47 | 42 | **5** | 4 trap · 1 build-failed · 1 no generator · 1 instance-method shape |
| `round-trip` | 46 | **0** | 0 | 0 | **45 no generator** · 1 build-failed |
| `input-totality` | 11 | 0 | 0 | 0 | 11 no composer |
| `codable-round-trip` | 8 | **8** | 8 | 0 | — |
| `associativity` | 6 | 4 | 4 | 0 | 2 no generator |
| `commutativity` | 5 | 4 | **0** | **4** | 1 no generator |
| `monotonicity` | 4 | 0 | 0 | 0 | 3 no generator · 1 domain not `Comparable` |
| `measure-non-negativity` | 4 | 0 | 0 | 0 | 3 no generator · 1 trap |
| 8 others (≤3 each) | 14 | 0 | 0 | 0 | 13 no composer · 1 no generator |

Corpus-wide: **105 carrier declines (37%)**, 24 no-composer (9%), 11 errors, 2 misc.

**The tier cut is the honest headline, and 139-of-281 is not.** The table above averages a 249-row
recall floor with 27 high-confidence rows, which are different populations asked different questions.

| tier | n | ran | held | ref | no generator | other | err |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Strong** | 3 | **0** | 0 | 0 | 0 | 3 | 0 |
| **Likely** | 27 | 23 (85%) | 19 | **4** | 4 | 0 | 0 |
| **Possible** | 249 | 116 (47%) | 111 | 5 | 101 | 21 | 11 |

**All 4 real bugs are `Likely`. All 5 `Possible` refutations are false laws.** That is a stronger
result for the scoring than any aggregate — the tier predicts whether a refutation is worth reading.
And the **3 `Strong` entries, score 80, are the only tier where NOTHING runs**: all three decline
`unsupported-template` (`differential-equivalence` ×2, `invariant-preservation`). Verify cannot
attempt the suggestions discovery is most confident in.

**Two things `--template predicate` could not have said.**

1. **Refutations concentrate, and `predicate` contributes none.** 0 of 76 `predicate`, 5 of 47
   `idempotence`, **4 of 4 `commutativity`**. The wall-of-green question, answered from the other
   side: `predicate` really is regression-guard work, and the refutable population lives elsewhere.
   Every executed `commutativity` law on this repo is one of the four merges, and every one is false.
2. **`codable-round-trip` is the only template at 100% yield** — 8/8 ran, 8 held. It is also the
   only round-trip family that never has to GUESS an inverse: the inverse is the carrier's own
   `Codable` conformance. That is the comparison the row below turns on.

#### `round-trip`'s zero is NOT carrier reach — that reading was wrong (corrected 2026-08-05)

The first version of this entry called `round-trip` *"the biggest single loss — 46 entries, ZERO
laws, and the binding constraint is carrier reach, not composer support."* The decline census says
45 want a generator, so the census reads that way. It is wrong, and the correction matters more than
the claim.

| scan | round-trip suggestions | same-file | cross-file | cross-type counter fired |
|---|---:|---:|---:|---:|
| `--target <each of 7>` | **1** | 1 | 0 | — |
| `--sources Sources` (what the INDEX does) | **46** | 1 | 45 | **45 of 46** |

The index is built by a whole-`Sources/` scan, which pools functions across module boundaries and
forms 45 cross-module pairs a per-target `discover` never produces. `crossTypeRoundTripCounterSignal`
detects every one and demotes them to `Possible`/score 25, so **nothing false reaches default
output** — discovery is behaving correctly. But they are still written to the index, and
`--all-from-index` then spends a full SwiftPM build on each, rediscovering by compilation what the
counter's own detail line already says: *"property cannot type-check across distinct containing
types."* ~16% of a 76-minute run.

So the real shape of the zero is **45 non-candidates plus exactly one real law**
(`SamplingSeed.derive(fromIdentityHash:)` ↔ `renderHex(_:)`, same file, score 35), and that one is
blocked on a missing `SamplingSeed` generator. Filed as **#97**.

**How the wrong reading happened, because it is the reusable part.** The evidence was a `grep` for
`func <name>(` across `Sources/`, used as a proxy for *where does the paired inverse live*. It
answered a different question. `discover`'s own output was one command away and settles it exactly.
Same failure as the §8.9 regex that returned 1 of 20, and the fourth instance this project has
recorded of a cheap proxy not covering the claim.

Five defects filed. **#92** (merge fold non-commutative ×4) and **#95** (unqualified nested
carriers) are FIXED in [#98](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/98).
**#93** (domain-transfer class), **#94** (round-trip receiver slot), **#97** (the survey builds
entries the counter already flagged) stay open, plus **#99**, which #95's fix uncovered. Items 21–26.

**Three of the five were re-reports of things this repo already knew**, and each was corrected in
place rather than quietly closed: #92 was pinned by `MergeAlgebraPropertyTests` over an injected
clock (all four logs, the associativity split, the stale docstrings, and a mutation test on
`>=` vs `>`); #93's class is named verbatim in `IdempotenceReturnShapeClassifier`'s doc, which
declines to veto it *on purpose*; #97's counter exists and fires. The tool's OUTPUT was new every
time; the diagnosis was not. **Search `Tests/` and the type's own doc before filing** — all three
would have been caught by one grep of the repo rather than of the corpus.

#### The 106 does not reproduce — and the flag raised over it is WITHDRAWN

The survey's first write-up flagged a top follow-up: `predicate` ran **76** where the stored
evidence recorded **106**, with carrier declines at 49 against 17. That was reported as a
discrepancy needing an A/B rather than as a regression, which was the right call, because the
A/B says **there was no regression and HEAD is better by 2**.

Two binaries, same day, same machine, **same 129 entries from the same index file** — the §10.3
shape, with the corpus held at HEAD so only the binary moves:

| bucket | BEFORE `2f65f92` | HEAD `1ef7128` | delta |
|---|---:|---:|---:|
| ran and held | 74 | **76** | **+2** |
| no generator for carrier | 49 | 49 | 0 |
| error: trap/parse | 4 | 4 | 0 |
| error: build-failed | 2 | **0** | **−2** |

**2 disagreements in 129, both the same direction**: `isDirectory(_:)` and
`isStale(indexPath:packageRoot:)` go `build-failed → ran and held`. That is the `Gen<URL>`
fix landing on exactly the row that motivated it. The carrier bucket is **49 in both arms**, so
the "17" was never a property of any binary in this range.

**The cheap half of the A/B was worth more than the expensive half.** Before running either
verify arm, both binaries built an index over the same sources: the predicate index is
**identical** — 129 entries, all 129 identities shared, 814 type shapes and 745 source-file
entries matching exactly. That is a five-second check and it eliminated the discover side
outright, including the two leading hypotheses (the purity-verdict change, the SEI pin bump).
The only index delta anywhere is `idempotence` 72 → 54, which is #78 doing its job.

**What the 106 was cannot be recovered, and that is itself the finding.** The survey's own
`persistSurveyBatch` overwrote `.swiftinfer/verify-evidence.json`, so the figure now exists only
as a reading taken mid-session. The evidence log upserts by identity and **keeps historical
entries** — the `idempotence` veto A/B already recorded that trap in the other direction — so the likeliest reading
is an accumulation across runs rather than one survey's output. Which is exactly why §10.3 says
never to compare against a stored count. **Third instance of a "measured drift" that was an
artefact of the comparison**, after the census's `SwiftInferCore` 96-vs-80 (`--include-possible`)
and this one's own two halves.

**A measurement whose artifact its own run destroys is not re-checkable.** Nothing was designed
to prevent that; the survey persists over the file it is being compared against. Worth fixing
before the next survey, or worth copying the evidence file first and saying so.

### The veto that was never asked, and the surface that would have hidden it (2026-08-05)

Item 26, closed ([#102](https://github.com/Joseph-Cursio/SwiftInferProperties/pull/102)).
`isUnaryEndomorphism` gated `idempotenceReturnShape` on exact
`parameter.type == returnType`; `IdempotenceTemplate+OptionalNarrowing` admits `T? -> T` as well.
The two gates disagreed and **nothing could notice**, because `returnShapeVeto` returns `nil` both
when the shape was never computed and when it was computed and cleared. Same shape as
`CuratedEntryRole` guarding the wrong join: a guard checking something narrower than the thing it
protects looks green while the hole stays open.

`Scaffold.defaultOutputURL(packageRoot: URL?) -> URL` returns
`(packageRoot ?? …).appendingPathComponent(…)`, and `appendingPathComponent` is the **first entry**
in the classifier's own `extensionCalls`. It would have returned `.extendsInput` unmodified. It was
never asked, so the law was proposed, ran, and refuted at trial 0.

**A/B, two binaries the same afternoon, index deleted between arms** (`IndexStore.upsert` keeps
historical entries — the `idempotence` veto A/B learned that the hard way):

| | before | after |
|---|---:|---:|
| index entries | 283 | **282** |
| `idempotence` | 54 | **53** |
| removed | — | **the witness, and only the witness** |
| added | — | **0** |

**Three things worth keeping.**

1. **The surface decided the answer.** Per-target `discover` and whole-`Sources/` `discover` both
   showed **zero** delta — the witness exists only in the **index**, which is built by a different
   pipeline. Measuring the convenient surface would have reported "no change" and proved nothing.
   Third time in two days that picking the wrong surface would have produced a confident wrong
   number.
2. **Three defects were stacked on one entry, each hiding the next**: a scope error (#95) hid a
   false law, which hid this veto gap. Only fixing the first made the second visible, and only
   running the second exposed the third. *A refuter that fires first hides every refuter behind it*
   — at the level of a single index row.
3. **A false law in the wrong bucket flatters the bucket.** This witness was briefly filed under
   #93's domain-transfer class, which it is not. Domain transfer stays at **5** witnesses; a class
   that absorbs anything unexplained stops being a characterisation.

**Unexplained and NOT chased**: the absolute index count moved from 281 earlier the same day to 283
in both arms. It cannot affect a same-day two-binary comparison, but **do not cite 281 as current**
until someone works out why.

### The census that pointed at the wrong constraint (2026-08-05)

Item 25, closed. All 45 cross-module `round-trip` pairs were filed as
`unsupported-carrier: <Carrier>` — *no generator derives this carrier*. They are not that. The
inverse half lives on a different type in a different module, so **even a perfect generator would
not make the call resolve**; `crossTypeRoundTripCounterSignal` had already said so at discovery
time, in a detail string that states the conclusion outright.

**The cost is demonstrated, not hypothetical: that label is what produced the claim "round-trip's
zero is carrier reach" in the survey write-up, and a proposal to spend effort on generators.** A
census that misattributes 45 rows to reach points work at the wrong constraint — the same failure
`verify-carrier-reach-census.md` records for a different cause (*"a census that forgets to thread
`allShapes` invents a carrier problem two-thirds of which is the harness"*), reached by a second
route.

| `round-trip` census | before | after |
|---|---|---|
| | 45 blocked-on-carrier + 1 error | **45 not-a-candidate + 1 blocked-on-carrier** |

The remaining 1 is `SamplingSeed.derive(fromIdentityHash:)` — the repo's **one** real round-trip
pair, genuinely waiting on a generator. That is the honest denominator.

**This issue was wrong three times, and the pattern is the lesson.** Wrong about the mechanism (the
counter does fire — 45 of 46, no misses); wrong about the population (discovery is correct, it is
the whole-`Sources/` *index scan* that pools modules); wrong about the cost (**nothing builds** —
`buildStubBundle` throws before `runSwiftBuild`, so the 45 already declined for free). Each error was
**claiming without measuring something one command would settle**, and each was caught only by
finally running it.

**The one true cost claim is smaller and more specific than the one I invented.** A single
cross-type entry *did* have a derivable carrier, reached the compiler and failed there — **46.0s of
the round-trip arm's 46.5s**. So the saving is real and comes from exactly one row. That row was
also [#94](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/94)'s only
witness, which is why closing it followed immediately — as **real-but-unwitnessed**, since
the `composeRoundTripPass` receiver defect is a correct code reading with nothing left to
exercise it. Its reopen condition is checkable from the index without running anything:
a `round-trip` entry that is an instance method, non-mutating, non-nullary, and carries no
structural blocker. **Zero matches today**, verified rather than assumed.

**`StructuralBlocker`'s bar, stated because it will be tempting to widen**: the signal must make the
law *unstatable as paired*, not merely improbable. A counter meaning "probably wrong" belongs in the
score, where a reader can overrule it. One member today, and it carries the counter's own `detail`
rather than a re-spelling, so the two cannot drift.

### Domain transfer, scored — a rule that cannot be built is a finding (2026-08-05)

Item 22 closed. `IdempotenceReturnShapeClassifier` declines to veto its documented miss class on the
grounds that it is *"not characterised well enough, and a veto that fires on a guess suppresses true
laws"*. This is the number behind that sentence.

**Method, fixed before the answer existed.** The candidate rule and its *predicted failure* were
committed in `5a6cff0`, before the scorer was written — git order is the proof, the same posture as
`q2-answer-key.json`. Scored against the 47 `idempotence` rows that EXECUTED in the whole-corpus
survey: 5 refuted, **42 held**.

Rule: **the parameter does not appear in the returned expression.**

| | count | |
|---|---:|---|
| flagged, genuinely the class | **4** | `markovSynthesized`, `regressionFileHash`, `seedString`, `seedTuple` |
| flagged, but a law that **HELD** | **8** | incl. `dedupedByStateAndAction`, `unwrappingRepetition` |
| the class, missed | **1** | `codableRoundTripGenerator` |

**Recall 80%, precision 33%** — two true laws suppressed for every false one removed.

**Why it fails, and the reason generalises.** *"The parameter is absent from the return expression"*
is true of **every function that binds a local and returns it** — a coding style, not a semantic
property. `seedString` hashes its input and returns a rendering of the digest, so the input is gone;
`normalisedTypeName` binds a trimmed copy and returns it, so the input is right there. **Those are
the same shape.** No return-expression rule separates them, so the signal is **dataflow** — whether
the parameter's value survives into the result or merely seeds something that replaces it. That is
strictly more expensive than anything this classifier performs.

**The prediction was right on both halves**, which is what makes it a test of the idea rather than a
description of an outcome: recall 4 of 5 *naming the miss*, precision below 50% *naming the suspect*.

**The transferable practice — score a veto against the laws that HELD, not against the class it
targets.** Recall on the target class is easy and says almost nothing; the 42 held rows are where a
veto's cost lives, and they are the only reason this failure was visible. It is also why
`unwrappingRepetition` appears here after the `idempotence` veto's first bare-`+` rule had already mis-vetoed it: **a
handful of functions keep tripping every cheap heuristic aimed at this template**, and that set is
worth naming before the next one is proposed.

Closed as **measured-not-buildable**, not *no signal exists*. A dataflow proposal would likely work;
reopen with one and score it against the same 47 rows. Artifacts:
`fixtures/domain-transfer-signal/` and `DomainTransferSignalExperimentTests`, whose numbers are
**asserted rather than described** so they cannot drift.

### The measurement artifacts are frozen now, because the run destroyed its own (2026-08-05)

`fixtures/whole-corpus-survey/` holds the raw `verify --all-from-index` streams behind every number
in *The whole-corpus number* — 281 records, plus the 129-record `predicate` A/B before-arm and the
bucketing script. 132 KB.

**The reason is not tidiness.** That survey's own `persistSurveyBatch` overwrote
`.swiftinfer/verify-evidence.json`, which is gitignored, so the figure it was being compared against
**no longer existed anywhere** by the time the comparison was questioned. The SHAs and commands were
recorded and both binaries rebuild from git, so the *method* was always reproducible — but the raw
evidence lived in a session temp directory and would have gone with the session.

Two caveats live in that directory's README rather than here, because that is where someone re-running
will look: delete the index before an A/B, and **do not diff a fresh run against these files** — §10.3
wants both arms taken the same day, so these are evidence of what was measured, not a baseline.

### Doc staleness: automate the trigger, not the habit (2026-08-03)

The rejected alternative was *"check the design-internal docs whenever we merge."* Two problems:
the **trigger is wrong** (a merge here does not correlate with a sibling moving — the gap between
sessions does), and **"check the docs" has no pass/fail**, so a skipped check looks exactly like a
passed one. Shipped instead: provenance trailers + `make docs-drift` + a `SessionStart` hook, with
claims split by perishability — counts and measurements rot, diagnoses do not. See PRs #55/#56 and
`scripts/docs_drift.sh`'s header.

---

## Standing observations

Toolchain-level reads with no single owning package. Not tasks; not measurements.

### The consumer keeps asking the producer for things, in English

Three times the downstream tool discovered it needed something upstream already knew, and each was
bolted on differently:

- `role` on a seed — added **because `discover` was already printing** *"the manifest SHOULD have
  named it: this is a LINTER gap."*
- `KitEvidence` — the kit's verdicts were the only *executed* evidence anywhere and fed nothing back.
- The rescue warnings — `swift-infer` prints prose **addressed at the linter**, to a human, hoping
  they act.

Not three coincidences. The pipeline is one-way by design and has needed backflow three times.
Worth deciding deliberately: is one-way load-bearing, or just how it started? **When a tool's best
diagnostic output is a sentence addressed to another tool, that is a missing channel.**

### The middle is thin where it should be thick

Volume and value point opposite directions at the lint → infer boundary: ~664 candidate findings →
1,657 seeds → **21 default-tier picks**. Meanwhile the *refactoring* half — extract this kernel,
make this domain type — **does not seed at all** (`PBTSeedsFormatter.seedKinds` maps four rules,
all testability/idempotency). The highest-value handoff is human-only; the highest-volume one is
nearly all noise. `CandidateInventory` fixed the reader-facing symptom by collapsing the census;
the manifest still carries the flood and not the insight.

### "Toolchain" claims more than the code backs — *now half-addressed*

**Was:** two of five packages had no automated relationship to anything, and no command ran the
loop, so every claim about "the loop" described a sequence nobody had automated.

**Now:** `scripts/toolchain.sh` runs **stages 0–2** (locate → lint → `discover --seeds`) and
declares 3–5 as not-implemented on every run. What that changes and what it does not:

- **Closed:** the sequence is executable and attributable. `run.json` records tool SHAs, so two
  runs are comparable — the precondition for any end-to-end number.
- **Still open:** stages 3–4 do not exist, so **no run executes a law** (item 9). Stage 5 never
  will — hardening is a human's job, and the driver says `not-a-command` rather than pretend.
- **SwiftIdempotency is still attached by one word** (`@ClockDeterministic`, via SEI) and appears
  in no stage. That half of the observation is untouched.

**Two facts that only surfaced by writing it**, and they say more than the observation did:

1. **`.pbt/seeds.json` had never existed anywhere on this machine.** Both repos document that
   path — the formatter writes it, `discover --seeds` reads it — and the hop had no instance until
   2026-08-03. A documented handoff with zero instances is not a handoff.
2. **The loop's entry point could not be invoked** — SwiftProjectLint ships no installed binary
   and is not on `PATH`, so "run the linter" meant knowing to type `swift run CLI` from the right
   directory. **Fixed 2026-08-03** by `scripts/bin/swiftprojectlint` (add `scripts/bin` to `PATH`).

   The reason it stayed broken is worth keeping, because it was a *good* instinct producing a bad
   outcome: binaries were never installed because the code was always changing, and recompiling
   was the safe choice. That is correct — **an installed binary is a remembered build**, the same
   hazard the A/B rule exists to prevent. The wrappers keep that property (they build through
   SwiftPM every invocation, so the binary is always the working tree) while removing the friction,
   which was never the compile — it was the missing command.

### The measurements are all withdrawn; the diagnoses survive

`roadtest-self-dogfood.md` voided, `leaderboard-sort`'s scorecards voided,
`PBT_TOOLCHAIN_FIX_PLAN.md` scored against a frozen fixture. **There is no current number for
"does a reader following the loop reach the bugs?"** — the one row the road test says should be
the only row that matters. That is open item 7, and it is downstream of *"toolchain claims more
than the code backs"*: you cannot cheaply re-measure a loop you cannot cheaply run.

**Partly unblocked as of 2026-08-03.** `scripts/toolchain.sh` makes stages 0–2 re-runnable and
writes a comparable `run.json`, so a *seed-and-suggestion* number is now cheap. A **refutation**
number still is not, because that needs stage 3, which does not exist (item 9). Worth being exact
about which number is back: the loop's own headline row — *would a reader reach the bugs?* —
remains unmeasured.

### Two ways to manufacture a defect that is not there

Both nearly produced a filed bug on 2026-08-05, verifying someone else's fix.

**An unsorted `diff` of two runs conflates ORDER with CONTENT.** Comparing two lint runs
reported ~541 differing lines and read as *the fix did not work*. Sorting first showed the
findings and their line numbers were identical and only the sequence moved — a different,
lesser defect. Separate the two before concluding anything about determinism.

**Capturing with `2>&1` merges two unsynchronised streams.** A trailing banner written to
stderr spliced into the middle of a stdout finding line, at a different byte offset each
run, in every run. That looks exactly like a real output defect and is purely the
redirection; re-running with the streams separated showed one clean line. It was one
command from being filed.

Same family as the `(file, symbol)` seed key and the §8.9 regex: **the cheap capture
answered a different question from the one being asked.**

### A doc that characterises a set by a property its newest member lacks

It does not go out of date — it **argues against the code**. `PBTSeed.role`'s comment said *"every
rule but the two **candidate** rules"*, and `extractablePureKernel` is a kernel rule, so a reader
checking the sentence against the classifier would have read the correct behaviour they found there
as a bug. The count was stale *and* the wording ruled the third out by name, which is why it was not
a one-line fix ([SPL#65](https://github.com/Joseph-Cursio/SwiftProjectLint/pull/65)). Name the
members individually rather than counting them.

### Every guard here was a retrofit

`VerifierWorkdirKitPinTests`, `SeedRoleContractTests`, `KitCoverageLawLevelTests`,
`SubprocessBatchCoverageTests` — all added *after* the incident. Not one
[border claim](glossary.md#border-claim) was guarded when written.

The 2026-08-05 addition sharpens the diagnosis, because its claim was written **twice**
and enforced neither time: the Makefile says *"Keep every regex-matched suite in exactly
one batch"* and CLAUDE.md restates it as a standing instruction. Nine suites drifted
through both. So restating a rule in a second prose location does not approximate a
guard — **it produces the feeling of having one**, which is worse than a single
unenforced comment, since the reader now finds agreement wherever they check.

Worse still, that Makefile comment is not a general warning but a **tally**: it names
BATCH5, BATCH6 and BATCH7 as batches added *because* suites had already been orphaned
this way. The rule was therefore written at the site of the mistake, by someone who had
just made it, three times, and it did not prevent the fourth. **A comment that records
its own recurrences is a guard's worth of evidence being spent on prose.**
The question is not "which guard is missing" but **what makes writing one feel like it needs no
test** — and the answer looks like: it is expressed where prose is normally decorative, its failure
is an absence, and the author is the only person who ever held both repos at once.
