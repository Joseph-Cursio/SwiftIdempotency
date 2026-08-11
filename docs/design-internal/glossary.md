# Glossary

> **Status:** `reference` · **As of:** 2026-08-06


Vocabulary used across this repo's source, docs, and CLI output. Terms are grouped by the
stage they belong to and **alphabetical within each stage**, because several of them mean
different things at different stages — **"template" in `discover` and "template" in `verify` are
not the same set**, and conflating them is how a reach estimate goes wrong (see [Reach](#reach)).

For the *sequence* rather than the lookup, read the pipeline sketch below; the sections
themselves sort for finding a word, not for learning the order.

Every definition here is keyed to code. Where a term's authority is a specific type or file,
it is named — prefer reading that over trusting this file, which is a map and not the territory.

> **As of 2026-08-06** · `SwiftInferProperties@2c599c0`. The **definitions** here do not expire; the
> **measurements embedded in them do**. Re-verify a number before citing it; the vocabulary around
> it stands.
>
> **All four survey numbers were re-taken on 2026-08-06**, and every one had moved:
>
> | | was | now | how |
> |---|---|---|---|
> | score-20 share, swift-syntax | 738 / 1,115 | **606 / 979** | fresh `discover`, **different corpus revision** — a re-run, *not* a re-verification (see [Score](#score)) |
> | composer-supported / `unsupported-template` | 95 / 156 of 251 | **24 of 281** template, **105** carrier | re-derived from the committed 2026-08-05 survey stream |
> | seeds → default-tier picks | 1,657 → 21 | **2,096 → 180** | fresh linter + `discover` run |
> | template files vs `TemplateName` cases | ~89 / 17 | **~92 / 18** | source count |
>
> **Two of these changed meaning, not just magnitude.** The composer table no longer partitions the
> corpus — the bottleneck moved from *template* reach to *carrier* reach. And the seed funnel
> inverted into a flood: 1,738 rows on a seeded run against 30 `strong`+`likely`.

<!-- doc-provenance date=2026-08-06 subject=SwiftInferProperties@38368c3 observer=SwiftInferProperties@38368c3 -->


---

## The pipeline, in one pass

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
  seeds                discover → index         run the laws          retry-safety
                       → verify → promote
        ▲                      ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

A function's trip: the linter **seeds** it → `discover` matches a **template** and assigns a
**score** → the score maps to a **tier** → `index` persists it as an **entry** → `verify`
resolves a **carrier**, derives a **generator recipe**, composes a **stub**, and runs two
**passes** → the **outcome** may **promote** the tier to `verified`.

### The 25 `swift-infer` modes, by stage

Abstracts are the shipped `--help` text, condensed. `discover` is the default subcommand.
Everything touching interaction invariants is the v2.0 reducer/MVVM surface and is listed
separately because it runs on a different carrier population.

**Find candidates**

| mode | what it does |
|---|---|
| `discover` | Scan a target for inferred property candidates. The entry point; everything else consumes its output. |
| `discover-reducers` | List functions matching the three canonical reducer signatures. Foundation for the interaction surface. |
| `discover-interaction` | Surface candidate interaction invariants on reducer-shaped functions. Ships at `Possible` pending calibration. |
| `known-properties` | List (and optionally verify) known algebraic properties on stdlib types — a provable seed of ground truth. |

**Persist and query**

| mode | what it does |
|---|---|
| `index` | Build/update the SemanticIndex at `.swiftinfer/index.json`, joining discover output with recorded decisions. |
| `query` | Query that index — filter by template, type, tier, decision or score; sorted by score descending. |
| `metrics` | Aggregate `.swiftinfer/decisions.json` into acceptance / rejection / suppression rates. |
| `metrics-interaction` | The same, per invariant family, over `.swiftinfer/interaction-decisions.json`. |

**Run the law**

| mode | what it does |
|---|---|
| `verify` | Compile and run a candidate property test. Opt-in — nothing in `discover`/`drift`/`accept` changes. |
| `verify-value-semantics` | Verify value-semantics candidates and report confirmed leaks (copy-mutate-compare). Spawns real builds. |
| `verify-interaction` | Build and run a verifier against a discovered reducer, checking it does not trap under random action sequences. |
| `prove-then-show` | Verify *every* pick including `Possible` and show what survives: Proven / Disproven / Unverifiable. The test-then-surface inversion of the hide-`Possible` default. |
| `accept-check` | Re-run verify for each accepted suggestion and report which still hold — regression detection. |
| `accept-check-interaction` | The interaction analog of `accept-check`. |

**Record a decision**

| mode | what it does |
|---|---|
| `accept-interaction` | Record a decision against an interaction-invariant identity. Minimal recorder; the triage UI is separate. |
| `accept-bridge` | Record a decision against a `BridgeSuggestion` identity — the scripted analog of `--interactive-bridges`. |
| `drift` | Diff current suggestions against a baseline; warn on new `Strong`-tier candidates. |
| `drift-interaction` | The same against an interaction baseline, non-fatally. |

**Read and act on what is known**

| mode | what it does |
|---|---|
| `report` | One-glance overview of what the tool knows about a project — index + verify evidence + insights. Read-only. |
| `insights` | Cross-type design suggestions from the index (types sharing a monoid/semigroup shape). Read-only, author-facing. |
| `docc` | Generate DocC docs for **verified** properties only. Inferred-but-unverified properties are never documented. |
| `suggest-refactors` | Carrier-aware refactor suggestions from the index. Read-only; never modifies source. |
| `scaffold` | Emit best-effort `gen()` stubs with `<#...#>` placeholders for types that cannot be fully auto-derived. |
| `scaffold-kit-suites` | Emit the PropertyLawKit conformance-law tests your types already owe. Half the carriers emit **commented out** — `DerivationStrategist` reaches 180 of 351 — because a live emission that cannot compile is worse than a disclosed gap. |
| `convert-counterexample` | Turn a property-test counterexample into a focused regression test. |

**Three things the table does not say, and they matter.** Only `discover` accepts
`--seeds`. Only `docc` is gated on *verified* rather than inferred. And the whole
`verify` column is **opt-in** — no discovery path ever compiles or runs anything, which
is why `discover` on a hostile corpus is safe.

---

## Discovery

### Catalog
The whole collection of templates, taken together. "A catalog gap" = no template names the
shape in question. Distinguish from a **reach** gap (a template exists and doesn't fire) and a
**statability** gap (the law is real but cannot be *written down* generically).

### Corroboration
Independent evidence that a proposed law is real — a docstring asserting it
(`DocstringPropertyCorroborator`), or an existing test body doing so (`TestLifter`). It raises
score; it does not by itself propose.

**`TestLifter` only corroborates.** Its detectors are keyed to existing templates, so
hand-rolled random-input property tests and libFuzzer harnesses are invisible to it.

### Lifted
A `mutating` method on a carrier, or a method reachable only through one, re-expressed as the
value-semantic `(T) -> T` shape a template needs. `idempotence-lifted` is the template; the
`+Lifted.swift` extensions are where lifting happens.

### Score
An integer assembled from weighted `Signal`s. Not calibrated in an absolute sense — the
thresholds are documented as "v0.3 defaults, not load-bearing constants."

**Known distribution problem:** scores land on a sparse lattice with a **hole in the middle**, and
on swift-syntax roughly **two-thirds of all suggestions sit at exactly 20** — the `possible` floor.
Moving that cut to 21 deletes two-thirds of the output. Ranking anything by row count without
accounting for the floor will mislead — and it is the [Daikon trap](#daikon-trap) arriving, measured.

| | 2026-07 study | **2026-08-06 re-run** |
|---|---|---|
| suggestions at score 20 | **738 of 1,115 (66%)** | **606 of 979 (62%)** |
| corpus revision | `1b5cd99f` | `9d6e738` |

**Re-run, not re-verified — and the distinction is the point.** The study's corpus revision
`1b5cd99f` is **no longer a reachable object** in `~/GitHub_projects/swift-syntax`, so the original
number cannot be reproduced at all. 606-of-979 is a *new* measurement over a *different* corpus
revision, and it is reported that way rather than substituted for the old one. What it establishes
is that **the phenomenon is stable** (66% → 62% across a corpus move), which is the claim the entry
actually rests on.

Observed lattice on the 2026-08-06 run: `{20, 25, 30, 35, 40, 45, 65, 70, 75}` — the hole is real
and is **45 → 65** on this corpus, wider than the "nothing between 50 and 65" this entry used to
state. No suggestion scored 50, 80 or 85.

> **Method trap, paid in this session.** `discover` over swift-syntax **`SIGBUS`es under the debug
> binary** — reproducibly, in under a second, on `Sources/` alone. That is the stack-depth trap
> `SwiftInferProperties/docs/measurements/parsing-catalog-gap.md` warns about, and the fix is the **release** binary (`swift build -c
> release`), which completes in 105s. A debug-binary run does not produce a smaller number; it
> produces *no* number and an exit code of 138.

### Seed / seed manifest
`{file, line, symbol}` records emitted by SwiftProjectLint's `--format pbt-seeds`, naming
functions worth pointing `discover` at. Kinds include `pure-function`,
`extractable-kernel`, `restricted-function`.

**Producer → consumer.** SwiftProjectLint writes them; `swift-infer discover --seeds`
reads them, and it is the **only** consumer — `scaffold`, `verify`, `index`, `report` and
`insights` do not accept the flag. That one hop is the whole lint → infer link in the
five-package toolchain.

**What a seed does to a run.** It *focuses*, it does not extend: discovery still scans the
entire target, and then the surfaced suggestions are narrowed to functions named in the
manifest. Two consequences worth knowing — a seeded pure function that **no template
matched** still earns the generic determinism law `f(x) == f(x)`, synthesized downstream
of the tier cut; and an empty manifest focuses to zero suggestions rather than to all of
them. A missing or malformed file is an error, not a silent fallback.

**A seed is not a suggestion.** Re-measured 2026-08-06 on this repo, twice the same day — the
second time at `38368c3` with the linter at `SwiftProjectLint@db4be6b6`, both arms from one release
binary over `--sources Sources`:

| | 2026-08-03 | 2026-08-06 (`2c599c0` / `08a4b09`) | **2026-08-06 (`38368c3` / `db4be6b6`)** |
|---|---|---|---|
| seeds emitted | 1,657 | 2,096 | **2,108** |
| default-tier picks, plain `discover` | 21 | 180 | **185** |

The second move is **this repo growing, not the tool changing**: `c14dc7e` and `38368c3` added
~1,600 lines of source, so more pure functions exist to seed.

**The funnel narrowed from ~79:1 to ~11:1, and the reason is not that inference got better.** The
decomposition says so — of those 185, only **3 are `strong` and 29 `likely`**; **151 are `possible`
pulled up by the refutability rescue**, plus 2 advisory. Against the older, stricter reading of
"default tier" as *likely and above*, the number is **32**, not 185. Both are given because the
2026-08-03 figure does not record which reading it used, and 21 → 30 versus 21 → 180 tell different
stories.

**The seeded run is the surprising one.** `discover --seeds` prints **1,746**, *more* than the
unseeded 185 — because a seed does not only focus, it also **vouches**: 659
`restricted-function` seeds rescue **663** access-restricted functions into template analysis that a
plain run never opens (663 > 659 because overloads share a seed). Every one of the extra
1,561 rows is advisory or possible (1,455 · 261). So the headline still holds in the direction it
was written — a seed is not a suggestion — but the modern failure mode is **flood, not funnel**.

**The `strong` + `likely` sets are no longer identical, and the seeded run is the SMALLER one:
32 unseeded, 30 seeded.** That was written as *"identical at 30 in both runs"* on 2026-08-06 and
did not survive the same day. Focusing now costs two `likely` rows. It is not obviously a defect —
the focus exists to narrow, and `keepRoleEntailedLaws` only overrides for laws the code *owes* — but
it is the first time the high-confidence set has moved under focusing at all, and the direction is
the one worth watching: the guard against this is `guardFinalAnswer`, which fires on an answer with
**zero** refutable laws, not on one that quietly lost two. **Not yet diagnosed.**

Seed kinds behind the 2,108: `pure-function` 1,189 · `restricted-function` 659 ·
`extractable-kernel` 257 · `idempotency` 3.

### Template
A named law shape that discovery can recognize from code — `idempotence`, `commutativity`,
`round-trip`, `predicate`. A template decides *whether it fires* and *what score it assigns*,
and ships the "why suggested / why this might be wrong" pair with each firing.

The canonical name vocabulary is `TemplateName` (`SwiftInferProperties/Sources/SwiftInferCore/TemplateName.swift`),
which exists so the several curated subsets ("the verifiable ones", "the v1.46 hardcoded set")
can't drift apart as string literals.

**Trap:** `TemplateName` does *not* enumerate every template discovery can emit. It holds the
verifiable set plus four extras; names like `predicate`, `input-totality`, and `filter-subset`
are live in the index and absent from the enum. Counting templates by `TemplateName.allCases`
undercounts. There are **~92** `*Template*.swift` files against **18** enum cases (2026-08-06; both
figures were 89/17 three days earlier — **the ratio drifts in both terms**, which is why the trap is
stated as a ratio and not as a number to memorise).

### Tier
Visibility band derived from score (`SwiftInferProperties/Sources/SwiftInferCore/Tier.swift`):

| tier | rule | shown by default |
|---|---|---|
| `verified` | `strong` **and** verify reached `measured-bothPass` | yes |
| `strong` | score ≥ 75 | yes |
| `likely` | 40 ≤ score < 75 | yes |
| `possible` | 20 ≤ score < 40 | **no** — needs `--include-possible` |
| `suppressed` | score < 20, or any veto fired | never |
| `advisory` | informational, carries no runnable property | yes |

`verified` and `advisory` are never returned by `Tier(score:)` — the surfacing pipeline sets
them explicitly, because score alone cannot know a verify outcome.

**"Default tier" / "default surface"** in the docs means *what a plain run prints*:
`likely` and above, plus whatever the refutability rescue pulls up.

### Veto
A rule that suppresses a firing the template would otherwise make. Vetoes have been the
highest-yield catalog work in this repo — the stream-consumption veto took 53 false `likely`
claims on `SwiftParser` down to 1; the result-builder veto took SwiftSyntaxBuilder 23 → 2.
Contrast with *additions*, which have moved single-digit row counts.

---

## Refutability

### Refutable
A law some type-correct, plausible implementation would be **rejected** by. The scoring unit
this repo uses instead of suggestion count, because `f(x) == f(x)` passes "did discovery return
> 0" and can never fail.

Authority: `Refutability.isRefutable` (`SwiftInferProperties/Sources/SwiftInferCore/Refutability.swift`).

**Caveat — it is declared, not measured.** The current implementation is set membership against
`tautologicalTemplates`, which contains exactly one name (`determinism`). Everything else is
classified refutable *by template name*, at proposal time. Whether a given law, against a given
generator, could actually have failed is a different question and is not what this API answers.

### Rescue
`Refutability.preservingLastRefutable` — the invariant that no filter may take a run to zero
refutable laws. Fires when the tier cut or the seed focus is about to leave a reader holding
nothing that could ever fail.

**A rescue is a bug report, not a feature.** Every firing means an upstream stage has a blind
spot, and callers are required to say so loudly.

### Role-entailed
A law a **correct** implementation cannot fail — it is owed *by virtue of the role*, not
conjectured from a name. A comparator owes a strict weak ordering; a predicate owes totality.

Orthogonal to refutable: refutable = *a wrong implementation can fail it*; role-entailed = *a
right implementation cannot*. A law wants both. `monotonicity` and `idempotence` are
conjectures and can be false of perfectly correct code.

### Tautology
A law true of every implementation that compiles. `determinism` (`f(x) == f(x)`) is the only
one, and it is what discovery emits for a seeded pure function no template matched — "I have
nothing to offer here," dressed as a finding.

---

## Verify

### Carrier
The type a law is stated over — the `T` in `(T) -> T`. `Int`, `String`, `Decisions`, a reducer's
`State`. `carrierTypeName` on a `SemanticIndexEntry`.

### Composer
A function that renders the stub source for one template —
`composeIdempotencePass`, `composeRoundTripPass`, etc., in
`StrategistDispatchEmitter+Templates.swift`. Composers are pure
`(Inputs, GeneratorRecipe) -> String` and read the generator solely from `recipe.expression`.

**This is the set that determines verify's template reach**, and it is much smaller than the
catalog — see [Reach](#reach).

**A worked pair.** Template `commutativity` → `composeCommutativityPass`. Given a carrier and a
generator expression, it renders the Pass 1 body:

```swift
let defaultGenerator: Generator<Int, some SendableSequenceType> = Gen<Int>.int(in: .min ... .max)

for trial in 0 ..< trials {
    let lhs = defaultGenerator.run(using: &rng)
    let rhs = defaultGenerator.run(using: &rng)
    if merge(lhs, rhs) != merge(rhs, lhs) {
        print("VERIFY_DEFAULT_RESULT: FAIL")
        print("VERIFY_DEFAULT_TRIAL: \(trial)")
        print("VERIFY_DEFAULT_INPUT: (\(lhs), \(rhs))")
        …
    }
}
print("VERIFY_DEFAULT_RESULT: PASS")
```

Three things every composer has and the shape depends on: it **only interpolates**
(`recipe.expression`, the carrier name, the call), it **prints markers rather than returning a
verdict** — `VerifyResultParser` decodes those and nothing else — and its law **fails by
comparison**, so the counterexample is an ordinary value it can print.

**`predicate` → `composePredicatePass` is the exception, and it is the useful one to know.** Totality
has nothing to compare: a predicate that *returns* has satisfied it. Its law fails by **trap**, which
kills the process before any marker is printed — so it prints the input *before* the call and
`VerifyResultParser`'s trap branch reconstructs the verdict from the last marker that survived. That
in turn only works because the stub preamble sets `setvbuf(stdout, nil, _IONBF, 0)`. It is the one
composer for which that preamble is load-bearing rather than a convenience.

### Composer-supported
Said of a template that has a composer, and so of an index **entry** whose template has one —
i.e. the law can be *executed*, whatever the result turns out to be. The complement is exactly
the `unsupported-template` decline.

The set is the `switch` in `StrategistDispatchEmitter.defaultPassSection`, plus the algebraic
laws that dispatch through `algebraicLawPass`, plus `predicate` via `totalityLawPass` —
**fourteen** templates, spelled once as `TemplateName.verifiable`:

```
round-trip · codable-round-trip · idempotence · commutativity · associativity
idempotence-lifted · dual-style-consistency · monotonicity · involution
binary-idempotence · homomorphism · multiplicative-homomorphism · measure-non-negativity
predicate
```

`predicate` joined on 2026-08-03 and routes through its **own** helper, not the algebraic one —
it is in `verifiable` and deliberately excluded from `strategistAlgebraicLaws`, because the
`unsupportedTemplate` error names that set and would otherwise advertise a template it cannot
compose.

Three things it is **not**:

- **Not a claim about the carrier.** A composer-supported template can still decline on
  `unsupported-carrier`, fail to compile, or trap. Composer support is necessary, not sufficient.
- **Not the same as "in the catalog."** Discovery emits template names that have no composer at
  all (`input-totality`, `inverse-pair`, `filter-subset`, …). Those are proposed, scored, tiered,
  and rendered to a reader exactly like any other suggestion — and then cannot be run. Measured on
  this repo's index (2026-08-01): **95 of 251 entries composer-supported (38%)**.

  **Re-measured 2026-08-06, and the estimate was good.** That figure predated `predicate`'s
  composer; the arithmetic guess recorded here was *"~215 of 251 (~86%)"*, explicitly flagged as
  arithmetic rather than a run. The 2026-08-05 whole-corpus stream puts template support at **257 of
  281 (91%)** — the guess was ~5 points low, and low in the safe direction. The hedge was the right
  call and is now discharged: **`unsupported-template` is 24, not 156**, and the live constraint is
  `unsupported-carrier` at 105. See [Reach](#reach) for the full table.
- **Not a quality signal.** It says a stub can be composed. Whether the law could have *failed*
  is [refutation reach](#reach), a different and later question.

The term exists because "supported" alone is ambiguous across three gates — `supportedCarriers`
(Route 1 only), the composer switch, and the strategist's ability to derive a generator — and
attributing a decline to the wrong one is a documented way to build the wrong plan.

### Decline
Verify returning no verdict because it could not build the attempt at all — as distinct from
running and passing. The `VerifyError` cases (`SwiftInferProperties/Sources/SwiftInferCLI/VerifyCommand.swift`):

| decline | meaning |
|---|---|
| `unsupported-template` | **no composer exists for this template.** The law was proposed, scored, and shown; nothing can run it |
| `unsupported-carrier` | the carrier type can't be resolved to a generator |
| `unsupported-pair` | a two-function template's pairing didn't resolve |
| `build-failed` | the stub was composed and did not compile |
| `runner-crashed` | the stub built and trapped |
| `monotonicity-domain-not-comparable` | pre-flight: `a ≤ b ⟹ f(a) ≤ f(b)` needs an ordered domain |

**`unsupported-carrier` is nearly always the wrong suspect.** It reads like the obvious
bottleneck and measures at ~4%. `supportedCarriers` — the constant that looks like the gate —
governs only the v1.46 hardcoded Route 1; everything else derives from `RawType` or an indexed
`TypeShape`. Reading that constant and believing it produced a wrong plan once already.

### Outcome
`VerifyEvidenceOutcome` (`SwiftInferProperties/Sources/SwiftInferCore/VerifyEvidence.swift`):

| outcome | meaning |
|---|---|
| `measured-bothPass` | no counterexample found in the generated domain |
| `measured-defaultFails` | Pass 1 found a counterexample — a **refutation** |
| `measured-edgeCaseAdvisory` | Pass 1 passed, the advisory boundary pass did not |
| `measured-error` | ran, but produced no verdict (build failed, timed out, crashed) |

**`measured-bothPass` does not mean "the property holds."** A derived generator is tuned for
coverage of the *type* and is silently mistuned for coverage of the *law*. Any law whose failure
needs two generated values to **collide** — merge tie-breaks, cache-key collisions, dedup, key
injectivity — is invisible to a generator drawing from a realistic domain.

### Pass 1 / Pass 2 (the edge pass)
Two runs of the same composed law. **Pass 1** uses the strategist's default generator and
**produces the verdict**. **Pass 2** uses a boundary-only recipe and is **advisory** — it
reports separately and cannot retract Pass 1.

The asymmetry is deliberate and load-bearing: boundary values cannot go in the verdict pass,
because `x + 1` traps at `Int.max` and the repo's existing tests depend on that being
unreachable at ~2⁻⁵⁸ per trial. Mixing them in turned three integration tests into
`signal 5` crashes. See `SwiftInferProperties/docs/design/verify-edge-pass.md`.

**Historical trap:** before 2026-07-31 Pass 2 was a hardcoded `print("VERIFY_EDGE_RESULT: PASS")`
with zero trials for every strategist-routed carrier. Any `measured-bothPass` recorded before
that date means *Pass 1 passed and Pass 2 was free*.

### Promotion
`strong` + `measured-bothPass` → `verified`. The only path to the top tier; score alone never
gets there.

### Strategist / generator recipe
`DerivationStrategist` (in SwiftPropertyLaws, **not** this repo) synthesizes a
`Gen<YourType>` per carrier. The result is a `GeneratorRecipe`, whose `expression` is the
generator source as a **string**. This repo calls the strategist and never reimplements it.

`.todo` marks where synthesis stopped and a human takes over.

### Stub
The generated, compilable Swift package that actually runs a law. Built per suggestion in
`.swiftinfer/verify-workdir/`. One full SwiftPM workdir *each* — an 85-entry survey left 3.4 GB
behind, gitignored, accumulating silently. `make clean-temp` sweeps it.

---

## Reach

Three different numbers, routinely conflated. This is the distinction most worth keeping
straight.

**Discovery reach** — of the code scanned, how much gets a law proposed. Bounded by the
catalog. Measured badly by row counts, given the score floor.

**Verify reach** — of the laws proposed, how many can be *executed*. Bounded by the **composer**
set, not the catalog.

**Refutation reach** — of the laws executed, how many could actually have failed. Bounded by the
**generator**, and the newest of the three to be measurable.

**Re-verified 2026-08-06, and the two-row table below is superseded — the bottleneck moved.**
Source: the frozen `fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl` (281 records, one per
index entry, `verify --all-from-index`, subject `1ef7128`). Re-derived rather than re-run: that survey
cost 76 minutes and 107 GB, and its stream is committed precisely so the numbers can be re-taken from
evidence.

| outcome | n | share |
|---|---:|---:|
| `measured-bothPass` | 130 | 46% |
| `architectural-coverage-pending` | 131 | 47% |
| `measured-error` | 11 | 4% |
| `measured-defaultFails` | 9 | 3% |

and the 131 pending split by **why**, which is where the framing changed:

| detail | n | |
|---|---:|---|
| `unsupported-carrier` | **105** | the new bottleneck — no generator for the carrier type |
| `unsupported-template` | **24** | down from 156 |
| `monotonicity-domain-not-comparable` · `instance-method-shape-not-supported` | 1 each | |

**`unsupported-template` collapsed 156 → 24, and `predicate` left the bucket entirely** —
`composePredicatePass` shipped 2026-08-03 and its 120 rows are gone. What remains is led by
`input-totality` (11), then `value-round-trip` and `filter-subset` (3 each).

**So "composer-supported vs `unsupported-template`" no longer partitions the corpus.** The old
two-row table implied one axis with two values summing to 251; today template reach is 24 of 281
(9%) and **carrier reach is 105 (37%)** — a different axis, and the one worth working. That is the
same 105 open-threads item 27 names, arrived at independently.

**Historical — the 2026-08-01 measurement, on a 251-entry index:**

| | entries | share |
|---|---:|---:|
| composer-supported | 95 | 38% |
| `unsupported-template` | **156** | **62%** |

The 156 were not spread evenly: `predicate` **120** (77% of the bucket, since closed),
`inverse-pair` 14, `input-totality` 11, `value-round-trip` 3, `filter-subset` 3,
`differential-equivalence` 2, and `comparator` / `override-precedence` /
`invariant-preservation` 1 each. Net of `predicate` that was **36 entries across 8 templates**, of
which `inverse-pair` + `input-totality` were 25 — *"69% of the actionable gap in two composers"*, a
prediction the 2026-08-05 stream partly bears out: `input-totality` is still the largest remaining
row, while `inverse-pair` cleared entirely.

**Since `predicate` shipped, that residual IS the gap** — the table above describes an index taken
2026-08-01, and the 120 row is now composer-supported. `inverse-pair` (14) and `input-totality`
(11) are the next two, and the same argument that moved `predicate` applies: one composer each,
no new machinery. Re-run the index before quoting any figure in this section.

---

## Method

### Backtest
Point the *finished* tools at real, already-fixed defects in mature public libraries and ask
whether the loop would have caught each one **before** its fix. Stronger than a road test: a
public fix commit predates the tools and was written by someone who never heard of them, so it
removes the last degree of freedom a self-built answer key leaves open.

### Border claim
An assertion **about a repository this one cannot see**, whose failure is an absence. The
compiler is the boundary of automatic verification; a border claim sits one inch past it, is
load-bearing (it gates behaviour), and running the code does not test it — because the claim is
not about the code.

**Why they fail silently, structurally.** The typical *use* of a fact about another repo is to
decide **not** to do something: they cover this law, so suppress it; they parse this grammar, so
don't; they already ran this, so stay quiet. The claim's whole job is to cause an absence, so the
failure mode is inherited from the purpose. [Confident zero](#confident-zero) is not a neighbour
of this term — it is the **shape a border claim takes when it breaks**.

**Four classes, and the class decides what evidence can settle it.** Substituting a cheaper
evidence type is the commonest way one goes wrong:

| class | example | settled only by |
|---|---|---|
| **existence** — that symbol is over there | `AttributeRecognition.default` claims `@Pure` ships in SwiftIdempotency; `ProtocolCoverageMap` claims a kit law runs | a grep of the other repo |
| **version** — we and they are at the same point | `VerifierWorkdir.swiftPropertyLawsRequirement`; the SEI revision pin | comparing two strings |
| **capability** — the consumer can act on this | `PBTSeedKind.isAnalysable` | a contract test (`SeedRoleContractTests` is the working example) |
| **behavioural** — this costs nothing / behaves the same | *"the SEI drift is latent, nothing observable"* | **measurement only** — no static check reaches it |

The version row is the instructive one. Those are the cheapest claims in the toolchain to check
and they drifted furthest — the kit pin by a full **major version**, the SEI pin by **9 commits**.
Difficulty is not the variable; nobody thought of them as claims.

**Measured instances.** `ProtocolCoverageMap` → **13 of 56** `(key, law)` claims false ·
`PBTSeedKind.isAnalysable` → **319 seeds** wrongly suppressed · the SEI pin → a **~2× wall-clock
regression** on the discover path, found only by an A/B · `AttributeRecognition` → unguarded to
this day.

**The trap: a guard at the wrong RESOLUTION certifies the error.** Worse than no guard, because
it converts an open question into a settled one. Three times here a *passing test* pinned a false
border claim — `AssumedKitCoverageTests:224` pinned a real law's suppression **as correct**;
`KitCoverageDriftTests` ran green through all 13 falsehoods because every assertion worked at
**suite** granularity and none opened the `Set<KnownProperty>` on the value side; and the first
road test's five defects were each pinned by a test asserting the buggy behaviour. In every case
the evidence was real, about the right subject, and at the wrong grain — which is also how the
"latent drift" claim went wrong, by settling a *behavioural* question with *existence* evidence
(the method exists at both revisions, so its cost must be unchanged).

**Do not guard all of them.** The filter is *would a false claim here cause a different action?*
The coverage map suppresses a real law — guard it. The pins change what compiles — guard them.
A doc saying "44 kit suites" changes nothing, so it is **dated rather than guarded**
(`make docs-drift`, and the provenance trailer at the top of this file).

Fuller treatment, per package: `docs/design-internal/swift{projectlint,effectinference,propertylaws,idempotency}.md`.

### Confident zero
The tool reporting "nothing here" when there was something. The failure mode this project
treats as worst, because a zero is believed and generates no follow-up. The first five-repo road
test returned **0 of 3** planted bugs this way, and each defect behind it was pinned in place by
a **passing test that asserted the buggy behavior**.

The [Daikon trap](#daikon-trap) is its opposite number: too much output versus falsely no output.
Both end with the tool unread.

**Where they come from.** A [border claim](#border-claim) is the commonest single source — a fact
about another repo is nearly always used to decide *not* to emit something, so when the fact rots
the tool goes quiet rather than wrong.

### Daikon trap
The failure mode this project is designed against, named for
[Daikon](https://plse.cs.washington.edu/daikon/) — the dynamic invariant detector that infers
properties by instrumenting runs, and famously produces *hundreds of true-but-uninteresting
invariants*. The output is not wrong. It is unreadable, so it goes unread, so the tool gets
switched off.

Authority: PRD §3.5 corollary 3. **Defaults must produce a number of suggestions a developer can
read in one sitting** — and the prescribed remedy is specific:

> if benchmark calibration shows we're producing more, the answer is to **raise thresholds, not
> to add filters on top**.

That clause is the whole rule. Piling filters on a flood keeps the flood and adds surface area
where a filter can eat the one law that mattered — which is exactly what [Rescue](#rescue) exists
to catch, and it has fired.

Note the PRD also puts *"full runtime invariant inference (Daikon-style instrumentation)"* out of
scope outright. So "Daikon" names both a rejected **technique** and a rejected **output shape**,
and in this repo it is nearly always the second.

**Spellings in the source.** *Daikon flood* (a template that would fire on every value of a
shape — every endomorphism, every binary predicate, every `Codable` type), *Daikon gate* (the
veto that stops one), *anti-Daikon posture*, *Daikon risk*. All the same idea; they read as
different terms and aren't.

**It generalizes past suggestion count.** From the metamorphic experiment: *"a metamorphic
catalogue that produces hundreds of always-passing picks is the Daikon trap in a new costume."*
A wall of green unrefutable passes is the same failure as a wall of uninteresting suggestions —
see [Refutable](#refutable).

**Live, measured, and unresolved — re-measured 2026-08-06 and still live.** On swift-syntax,
**606 of 979 suggestions sit at exactly score 20** (62%), the `possible` floor — was 738 of 1,115
(66%) on an earlier corpus revision, so the trap survived a corpus move intact. On
`SwiftInferTemplates` the default surface is 88% `predicate`. That is the trap arriving, and the
PRD's remedy would work mechanically — moving the cut from 20 to 21 deletes two-thirds of the output.

**And there is now a second face of it**, from the seed side: `discover --seeds` on this repo prints
**1,738** rows against 30 `strong`+`likely` ones — 1,447 of them advisory. The trap no longer needs a
low threshold to arrive; the rescue path delivers it. See [Seed / seed manifest](#seed--seed-manifest).

It has not been applied, for a documented reason pulling the other way: `3e38e34` established
that **a law the code OWES is never hidden**, earned from a real incident where a reader complied
with the linter and the sharpest law in the run vanished. The resolution so far is *ordering*
rather than hiding (`Discover.strongestFirst`) — which addresses burial but not volume, and
`predicate-display-order.md` lists "is the score-20 volume itself a problem, now that it sorts
last?" as still open, with the honest note that **nobody has asked a reader**.

### Latent
A shipped change verified on synthetic shapes that produces **zero delta on every measured
corpus**. Not a failure — a genuine absence, recorded as such so nobody mistakes "no effect
observed" for "not implemented."

### Mutation corpus
Hand-authored mutants (reversible patches) kept **standing** and re-run whenever the toolchain
changes, to check the tests still catch the bug shapes they were written for. Distinct from the
frozen answer key: corpora are living tooling, deliberately sharpened over time.

The unit a generator should be scored in — `fixtures/integer-division-generator` reports
**2/8 → 8/8 mutants killed** alongside its coverage table, because coverage says boundary values
are *present* and only the mutant table says the test *catches* things it could not before.

### Road test
Point the tools at a subject and score them. Requires a **frozen fixture** (the code before any
property work, pinned to a commit, never merged back into) and a **frozen answer key** (written
by hand, in advance, without consulting the tools).

**A tool may not grade its own homework.** Anything the tools find that the key missed is
recorded **unscored**, never folded in. A key edited in response to tool output stops being
independent the instant it is edited.

### Statability gap
A law that is real, has population, and still cannot be written down generically — a fourth
failure mode beside not-scanned, not-paired, not-templated, and suppressed.

The worked example is the metamorphic family: ~599 carriers across five repos, so population is
not the blocker. The blockers are that type text is a *source spelling*, that locations are
*coordinates reformatting moves* — **"a template cannot tell a coordinate from a fact"** — and
that trivia is semantic inside `"""…"""`.

---

## Neighbours

Terms owned by sibling packages, listed because they appear in this repo's output.

**`@ClockDeterministic`** — the claim that admits async code to verification. Bare `async` is
rejected, with a message saying how to make the claim.

**Effect lattice** — `pure < observational < idempotent < externallyIdempotent < nonIdempotent`,
with a `lub` join. Defined in SwiftEffectInference.

**Interaction family** — the five reducer/MVVM invariant families (idempotence, cardinality,
biconditional, referential-integrity, conservation). A separate vocabulary from `TemplateName`;
see `InteractionInvariantFamily`.

**Purity oracle** — `PurityInferrer`, the single authority both SwiftProjectLint's flagship rule
and this repo's veto consult, so the two can never disagree about what is pure. Refutes
`Date()`, `UUID()`, RNG reads. **Purity gates must not relax to reach a target** — removing the
`throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at a stroke, with a
subprocess-spawning function judged pure.
