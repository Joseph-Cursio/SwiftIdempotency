# SwiftEffectInference — the shared leaf

> **Status:** `reference` · **As of:** 2026-08-06


**Repo:** `~/xcode_projects/SwiftEffectInference` (`github.com/Joseph-Cursio/SwiftEffectInference`) ·
**Book home:** Appendix C; Chapter 26 §26.3 (the lattice), Chapter 22 §22.6 (clock-determinism).

> **Counts verified 2026-08-06** against subject `SwiftEffectInference@6f45139` · observer
> `SwiftInferProperties@2c599c0`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.
>
> **What the 2026-08-06 pass changed.** The pin divergence **reversed direction and is no longer
> blocked**: SEI#1's regression was fixed (`6470222`), this repo bumped from `1f2265a0` to HEAD, and
> the §13 budgets were re-measured green. SwiftProjectLint was then the laggard, by two commits, with
> a named consequence. Size held at 13 files / ~3,800 lines.
>
> **2026-08-07 — pin only, counts NOT re-verified.** SEI moved two commits to `bc084fb` (`01bcdf7`
> *Track what an inferred effect rests on*) and this repo's pin was bumped to match, closing the
> divergence — see § *The pin divergence*. That section and the **§13 perf table** are current (all
> 8 budgets re-measured green at `bc084fb`); **the file/line counts and every other number still
> describe `6f45139`** and have not been retaken. The bump was source-compatible (additive, defaulted
> argument), so the diagnoses are unaffected.

<!-- doc-provenance date=2026-08-06 subject=SwiftEffectInference@6f45139e3e243a451c20fd5f6af43d6f8a8db2a5 pinned=50c5d3a03c1620e5db7e7a71fac3f62378c6c0dd observer=SwiftInferProperties@2c599c02fd5a070b97c582a610909f542bbc5cdc -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

The smallest package in the toolchain and the only one with **no CLI and no dependents below it** —
13 source files, ~3,830 lines, depends on nothing in the set. It is a library two other tools
*embed*, which is the entire architectural point: **the linter and the inference engine consult one
purity oracle, so they cannot disagree about what is pure.**

### In and out, precisely

The only member of the toolchain with **no process boundary** — so its "output" is return values, not
files, and there is no format to version.

| | what | shape |
|---|---|---|
| **consumes** | SwiftSyntax nodes, in memory | `FunctionDeclSyntax` · `ClosureExprSyntax` · `AccessorBlockSyntax` — never a path, never source text |
| | doc-comment and attribute annotations | the `@lint.effect` grammar + `@Idempotent`-family attribute names, matched **by name** |
| | *(nothing else)* | no config, no disk, no network, no build |
| **produces** | `Effect?` | the five-tier lattice position, or `nil` for "no opinion" |
| | `PurityVerdict` | `pure` · `pureButPartial` · `refuted` — separates transparency from totality |
| | `Bool` | the `isPure` overloads, for the three node kinds |

**`nil` is a real answer and is not the same as `.pure`.** It means the oracle declines, which is why
`@EffectUnknown` needed its own predicate (`declaresUnknownEffect`) rather than a sixth tier: before
it, an author's explicit *"I cannot determine this"* returned the same `nil` as an unannotated
declaration **and** as a misspelled tier — three different situations collapsed into one.

That claim is the thing to check when reading this doc, because **the two consumers do not compile
against the same revision, and as of 2026-08-03 they deliberately cannot** — closing the gap costs a
measured ~2× regression on this repo's hot path, filed as
[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1). See
[The pin divergence](#the-pin-divergence).

---

## The lattice

```
pure < observational < idempotent < externallyIdempotent < nonIdempotent
```

`Effect` (`Effect.swift`, 115 lines) is a five-case enum with a `rank` (0…4) and a `lub` that is
**rank-only**: `rank >= other.rank ? self : other`, with left-bias on ties. `lub(of:)` is the
collection form, returning `nil` for empty input.

**Two axes are stacked in one chain, and the doc comment is explicit about it.** The upper four
tiers classify *retry-safety* — the original axis, and SwiftIdempotency's concern. `pure` was
**inserted at the bottom later** to add the *referential-transparency* axis, which is the one a
property-based test needs. Every pure function is retry-safe; an observational function that logs or
reads a clock is retry-safe and not pure. So the chain reads in one direction and is used in two.

**What is deliberately omitted, and why.** SwiftIdempotency's reference lattice is a genuine
*non-linear partial order* with two elements SEI does not model:

- `transactional_idempotent` sits **parallel** to `externallyIdempotent` — incomparable, since one
  relies on a transaction boundary and the other on a caller-supplied dedup key.
- `unknown` is incomparable to `non_idempotent`.

Modelling either forces a Hasse-diagram join in place of the rank comparison — a substantial change
to the core algebra **for tiers no current consumer reads**. `transactional_idempotent` is, by
SwiftIdempotency's own design, a doc-comment-only tier needing transaction-boundary verification
neither a macro nor SEI performs. So the chain stays linear, and `EffectAnnotationParser` still
*recognizes* the spelling and projects it conservatively onto `.nonIdempotent` — the sound bound
absent verification, rather than a silent drop.

`Effect.rank`'s own doc warns the values are **relative ordinals, not a wire format** — they shifted
once already when `pure` was inserted at the bottom.

---

## The four engines

| type | what it answers | swift-infer uses it? |
|---|---|---|
| `PurityInferrer` | is this function referentially transparent? | **yes** — via `SoundPurity` |
| `EffectAnnotationParser` | what did the author *declare*? | **yes** — 3 sites |
| `CallSiteEffectInferrer` | what does this call expression do? | **no** |
| `BodyEffectInferrer` | what does this body do, from its callees? | **no** |
| `EffectSymbolTable` | cross-file declared+inferred lookup | **no** |

Measured by grep over `Sources/` on 2026-08-03: `PurityInferrer` 4 references,
`EffectAnnotationParser` 5, and **zero** for `EffectSymbolTable`, `BodyEffectInferrer`,
`CallSiteEffectInferrer`, `FunctionSignature`. That asymmetry is worth stating plainly: the
cross-file grading machinery — call-graph lub with depth tracking, framework-gated call-site
classification, collision-withdrawal — is **SwiftProjectLint's half of the library**. This repo uses
the two leaf primitives and none of the graph.

### `PurityInferrer` — the one that matters here

> This is the **canonical** purity oracle for the ecosystem.

The soundness argument is the load-bearing part, and it is stated as an asymmetry:

> Purity is a *conjunctive* property — a function is `.pure` only when **none** of the refuters fire
> — so a single narrow analyzer can never *establish* it soundly; it can only **refute** it.

`.pure` is the lattice bottom and the most dangerous place to land wrongly, because every downstream
consumer *trusts* it: a generated property test runs a `.pure` function in-process and asserts a law
over random inputs. So the inferrer over-approximates by construction — **any doubt refutes purity**,
and a missed refuter would be unsound.

Two marker sets do the refuting, both matched by **bare identifier token**:

- **side effects** — `print`, `NSLog`, `FileManager`, `URLSession`, `UserDefaults`,
  `NotificationCenter`, `DispatchQueue`
- **nondeterminism** — `arc4random`, `arc4random_uniform`, `drand48`, `CFAbsoluteTimeGetCurrent`,
  `random`, `randomElement`, `shuffled`, `Date`, `UUID`

The token scan is **deliberately** crude and says so: it refutes `Date()` *and* the perfectly
deterministic `Date(timeIntervalSince1970:)` alike, and refutes injected `random(in:using:)` as well
as the system-RNG form. Over-refutation is the sound direction. The AST-precise forms live in
SwiftProjectLint's `NonInjectedNondeterminismVisitor`; **this token set is the leaf-level
over-approximation of that rule**, not a rival to it.

Plus signature gates: `async` refutes, a body-less declaration (a protocol requirement) refutes —
there is nothing to inspect — and the body must be total (no traps, no force-unwraps).

### `EffectAnnotationParser` — two grammars, plus one orthogonal marker

Reads declared effects in **both spellings**, so a project can annotate either way:

- doc comment — `/// @lint.effect pure`
- attribute — `@Pure`, `@Idempotent`, `@NonIdempotent`, `@Observational`,
  `@ExternallyIdempotent(by:)`

Recognized attribute names are configurable (`AttributeRecognition`), with a `.default` set. Parses
`FunctionDeclSyntax` and `VariableDeclSyntax`, in both static and instance form.

**`@ClockDeterministic` is not on the lattice, and that is the design.** It is an *orthogonal* marker
— `/// @lint.determinism clock_deterministic` or `@ClockDeterministic` — surfaced only via
`isClockDeterministic(declaration:)` and never via `Effect`. The reason is stated in the source:
`.pure` implies *synchronous*, so an async function can never be `.pure` no matter what the author
claims. The marker exists so downstream consumers can relax an **async veto** exactly where the claim
is present, without pretending the lattice moved.

That is the mechanism behind this repo's async story. `ViewModelDiscoveryVisitor:154` and
`ReducerDiscoverer` call it; `FunctionSummary.isClockDeterministic` and
`ReducerCandidate.isClockDeterministic` carry it forward. Bare `async` keeps a clean rejection that
says how to make the claim; the claim, once made, is what admits the code to verification.

### The two swift-infer does not use

`CallSiteEffectInferrer` (498 lines) classifies call expressions by callee name plus **the file's
imports** — framework-gated for FluentKit, Hummingbird, Vapor, AWSLambdaRuntime, TCA, swift-metrics,
swift-log. The gate exists because of a real false positive: a user-defined `class Counter` in a
module with no `import Metrics` was classifying as observational purely on the name match
(`FrameworkGates`, 505 lines — the largest file in the package).

`StdlibIdempotentMutations` is the companion suppressor: `append`/`insert`/`remove` are correctly
non-idempotent for a user-defined persistent queue and **wrong** for `Array.append` or `Set.insert`,
so `(typeName, methodName)` pairs suppress the bare-name inference back to "no heuristic applied."
`Set.insert` is idempotent by set semantics; `Dictionary.updateValue` is key-addressed and
replay-safe.

`EffectSymbolTable` resolves cross-file with **collision-withdrawal**: unannotated declarations do
not participate in collisions (an annotation expresses intent; an unannotated sibling is noise, not
ambiguity), and two annotated declarations with conflicting effects **withdraw the entry** rather
than pick one. Precedence is `declared > collision-withdraw (silent) > upward-inferred >
heuristic-downward > silent`, of which the table covers the first three.

---

## How this repo consumes it: `SoundPurity`

`SwiftInferProperties/Sources/SwiftInferCore/SoundPurity.swift` — 45 lines, and the reason the conjunctive framing above
matters. It takes the **meet of two independent refutations**:

```swift
guard ReducerPurityAnalyzer.analyze(function) == .pure else { return nil }
return PurityInferrer().inferredEffect(for: function)
```

- `ReducerPurityAnalyzer` refutes on TCA/concurrency effects (`Effect`, `Task`, `await`, `.run`,
  `.send`) and hidden mutation (static / `Self` writes).
- `PurityInferrer` refutes on I/O, logging, nondeterminism, and totality.

`.pure` is claimed **only when neither refutes**, and each analyzer is blind to the other's refuters.
Mapping `ReducerPurity.pure` onto `Effect.pure` alone would be **unsound**: a reducer can be
`ReducerPurity.pure` while calling `print()` or `Date()` or force-unwrapping.

Consumers of the result: `FunctionScannerVisitor+Summary.swift:38` sets
`FunctionSummary.isInferredPure` at scan time, where the syntax node is live; `EffectAnnotationAdvice`
renders it as a *"consider adding `/// @lint.effect pure`"* row on its own advisory channel
(`DiscoverArtifacts.effectAnnotations`) — deliberately **not** a property-test `Suggestion`, since
that would need a fabricated `Score` and `GeneratorMetadata` and would dead-end in the
templateName-driven accept/verify switches. `SoundPurity` only ever yields `.pure`, so the
recommended annotation is always that tier.

**This is the veto CLAUDE.md means** by *"Purity gates must not relax to reach a target."* Removing
the `throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at a stroke, with a
subprocess-spawning function judged pure.

---

## The pin divergence — RE-OPENED and re-closed 2026-08-08

SEI carries **no version tags**, so both consumers pin by revision. As of 2026-08-07 they pin **the
same revision** for the first time, and the section title is kept rather than renamed because the
divergence is the thing worth remembering: it ran for weeks, and it had a named consequence each time.

> **2026-08-08 — it did not stay closed for a day, and the shape is worth more than the fix.**
> SEI moved two source commits; SwiftProjectLint bumped to `fc82ec4` and this repo did not, so the
> divergence re-opened **with this repo as the laggard** while the section above said CLOSED. A
> heading that records a state rather than a rule goes stale the moment the state changes — the
> rule is *read the pin from `Package.swift`*, which is the standing instruction in CLAUDE.md and
> the reason this table names the manifest line.
>
> Now at `50c5d3a`, which is `fc82ec4` **plus a docs-only commit**, so the two consumers are
> source-identical again.
>
> **A/B measured before bumping, because one of the two commits relaxes a purity gate.**
> `a7acb22` counts a nested closure's parameters as locals, which its own message says makes
> `isPure` *"strictly more permissive"* — and CLAUDE.md's standing rule is that purity gates must
> not relax to reach a target. This is an upstream bug fix rather than a relaxation, but that is
> an argument, not a measurement. Two release binaries, same afternoon, `discover
> --include-possible` over **seven corpora** — this repo's three targets plus `OrderedCollections`,
> `DequeModule`, `ArgumentParser` and `NIOCore`: **byte-identical output on all seven, zero rows
> moved.** The other commit, `20b6e5a`, is additive API (it publishes the capture-write clause on
> its own for SwiftProjectLint's `unreachable-effect-closure` rule) and cannot move a verdict here.

| package | manifest | revision | vs SEI `HEAD` |
|---|---|---|---|
| SwiftInferProperties | `Package.swift:122` + `Package.resolved` | `50c5d3a` | **at HEAD** |
| SwiftProjectLint | root + `SwiftProjectLintVisitors` + `SwiftProjectLintIdempotencyRules`, all three | `fc82ec4` | 1 commit behind, **docs only** |

**Both consumers now agree, and the linter got there first.** SwiftProjectLint was already at
`bc084fb` in all three of its manifests when this repo bumped from `6f45139` to match — so the
two-commit gap this section used to describe closed from the *other* side, which is the reverse of
how the previous two closures went. The convergence is the state the shared leaf exists to produce:
one purity oracle, one revision, no way for the two tools to disagree about what is pure.

The history of the gap, kept because each phase had a distinct cause:

| date | this repo | the linter | why the gap existed |
|---|---|---|---|
| 2026-08-03 | `1f2265a0` | `097181aa` | this repo held **two public methods against five** and the bump was blocked by the SEI#1 regression (§ *The bump was blocked*) |
| 2026-08-06 | `6f45139` | `bfcf0e3` | direction reversed; the linter's oracle could not read `@EffectUnknown` (`7a70b3b`), so `@lint.effect unknown` parsed to `nil` — **indistinguishable from an unannotated declaration and from a misspelled tier**, and the two tools could disagree about an author's own stated uncertainty |
| 2026-08-07 | `bc084fb` | `bc084fb` | — |

Both consumers compile against the full five-method `PurityInferrer` — `inferredEffect(for:)`,
`isPure(_: FunctionDeclSyntax)`, `verdict(for:)`, `isPure(_: ClosureExprSyntax)`,
`isPure(_: AccessorBlockSyntax)` — and both are past the regression that once blocked the bump
(`6470222` is an ancestor of both pins).

**What the 2026-08-07 bump adds here.** `01bcdf7` *Track what an inferred effect rests on* gives
`BodyInference` an `Anchor` (`.declared` / `.heuristic`), so a consumer can tell an author's
annotation from a name-or-framework guess. It is **additive with a default argument**, and this repo
constructs no `BodyInference` — it only calls `applyBodyInference` — so the bump is source-compatible
and nothing here reads the anchor yet. That last clause is the open end: the anchor exists to let a
consumer *decline* a heuristic, and declining is not wired up.

### The bump was blocked 2026-08-03, and is UNBLOCKED as of 2026-08-06

**Resolved in SEI, exactly where this doc predicted it belonged.** `6470222` — *"Stop the whole-domain
purity path paying for verdict's body walk"* — is the fix for
[SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1), and it
implements the remedy proposed below verbatim: `inferredEffect(for:)` stops delegating to
`verdict(for:)`. Both consumers' pins now contain it.

**Re-measured on this repo, 2026-08-06, at pin `6f45139`** — a full `make test` run, the §13 perf
target in its own isolated step:

| §13 perf test | budget | at `1f2265a0` | at `097181aa` (regressed) | at `6f45139` | at `bc084fb` |
|---|---|---|---|---|---|
| Discover pipeline, 100 test files | 6.0s | 3.389s | **6.777s** ❌ | 4.219s ✅ | **4.310s** ✅ |
| TestLifter.discover, 100 files | 4.0s | 0.502s | 1.036s | 0.669s ✅ | **0.690s** ✅ |
| Discover, 50-file corpus | 2.0s | 0.671s | 1.356s | 0.916s ✅ | **0.960s** ✅ |
| …with decisions-load active | — | 1.660s | 3.652s | 2.238s ✅ | **2.406s** ✅ |
| 500-file corpus, peak RSS delta | 800 MB | — | — | 234.1 MB ✅ | **245.6 MB** ✅ |

The `bc084fb` column was taken 2026-08-07 by `make perf` (serial, alone, 22.1s, 8 tests). Every row
is within noise of `6f45139` — the anchor work adds a field to `BodyInference` and does not change
the walk, so a flat reading is the expected shape rather than a reassuring one.

Slightly slower than `1f2265a0` and comfortably inside every budget, which is the expected shape: the
cheap path is restored, and the extra three methods are real work that path no longer pays for.

**The record below is kept as the diagnosis, not as current state.** It is the argument that a
reasoned claim is not a measured one, and that argument is why the regression was caught at all.

---

**Historical — the blocking measurement (2026-08-03).**
`097181aa` cost a **~2× wall-clock regression on the whole-domain purity path**, which is the path
this repo's every command runs. Five of the PRD §13 budgets failed, one hard.

Controlled A/B, same machine, same isolated `make perf`, one variable — the revision:

| §13 perf test | `1f2265a0` ×2 | `097181aa` | ratio |
|---|---|---|---|
| Discover pipeline, 100 test files (budget 6.0s) | 3.389s / 3.455s ✅ | **6.777s** ❌ | 2.0× |
| TestLifter.discover, 100 files | 0.502s / 0.511s | 1.036s | 2.1× |
| Discover on 500-file corpus | 10.369s / 10.582s | 21.833s | 2.1× |
| Discover, 50-file corpus | 0.671s / 0.700s | 1.356s | 2.0× |
| …with decisions-load active | 1.660s / 1.703s | 3.652s | 2.2× |
| whole perf run | 16.682s / 17.038s | 28.474s | 1.7× |

The control replicates to **~2%**, one arm after a clean build and one after an incremental one, so
the effect is ~50× the measurement noise. Matched on the same harness too: full `make test` passes end
to end at `1f2265a0` and fails at the `perf` step at `097181aa`.

**Diagnostic detail worth keeping:** the treatment got *worse* in isolation (6.777s) than under
full-suite load (6.263s). That is backwards for a contention flake, and it is what moved the
investigation off `MemoryCeilingPerformanceTests`' "rerun before blaming your edit" note and onto a
controlled A/B.

Two candidate mechanisms, **neither measured** — in a chain of costs the first one found hides the
rest, so this is left open rather than guessed:

1. **`throws` no longer short-circuits before the body walks.** At `1f2265a0`,
   `isSynchronousAndNonThrowing(function.signature)` rejected throwing functions on a *signature*
   check. At HEAD only `async` short-circuits, so every throwing function pays two full traversals —
   and Swift corpora, test code especially, are dense with `throws`.
2. **The body-walk helpers were generalized to erased `Syntax`** (`hasRefutingMarker(in: Syntax(body))`,
   `isTotal(Syntax(body))`). Necessary — it is what lets HEAD answer purity for closures and computed
   properties — but it is on the hot path.

The proposed fix lives in SEI, not here: `inferredEffect(for:)` should stop delegating to
`verdict(for:)`. `verdict` genuinely needs the body walk to tell `.pureButPartial` from `.refuted`;
the whole-domain question does not, because `throws` disqualifies outright.

### What this cost, and the lesson it carries

**The paragraph that used to sit here said the drift was latent and nothing observable was broken.**
It reasoned — correctly — that `SoundPurity` calls only `inferredEffect(for:)`, that the method exists
at both revisions, and that its *answer* is unchanged. All true. The *cost* doubled, and reading the
code could not see it.

That is the identical shape as SwiftIdempotency's shrinker-composition entry, which sat labelled
*"not experimentally verified — the claim rests on reading the source"* until somebody wrote the
failing property in five minutes and found the reasoning had been optimistic. Same failure, recorded
in a document arguing that this failure keeps happening. **A reasoned claim about behaviour is not a
measured one, and "I read the call site" is not a measurement.**

### The invariant still stands, and is now reachable

**Keep this pin equal to SwiftProjectLint's**, not current with SEI's HEAD. The claim the shared leaf
exists to support — *the linter and the inference engine can never disagree about what is pure* — is
about the **oracle they compile against**, not the repository. The blocking reason is gone, so the
inequality is no longer *on purpose*; it is now just unfinished.

**The guard situation improved by half on 2026-08-04.** SwiftProjectLint's `SEIPinAgreementTests`
asserts its own **three** manifests name one revision — the duplication that a comment saying "keep
this aligned" was previously all that coordinated. Its doc comment is careful about what it cannot
reach: *"This test cannot see that cross-repo gap; nothing in a single repository can. What it can do
is make sure that when this repository's pin moves, it moves in all three places at once."*

So of four manifests across two repos, three are now guarded as a group and **the cross-repo equality
is still unchecked** — the same failure shape CLAUDE.md has a rule for on the other dependency
(*"The verifier's kit pin must equal this package's own,"* guarded by `VerifierWorkdirKitPinTests`,
written after that pin drifted a full major version unnoticed).

Progress against the ordered list this section used to carry:

| | item | state |
|---|---|---|
| 1 | **SEI#1** — restore the cheap path | ✅ **done** (`6470222`) |
| 2 | bump, re-running `make perf` before `make test` | ✅ **done** — this repo is at HEAD, budgets green |
| 3 | pin-equality guard, phrased as *equality with the sibling consumer* | ⚠️ **half** — intra-repo guarded there, cross-repo unguarded |
| 4 | adopt `verdict(for:)` for `.pureButPartial` | **open, and now actually reachable** — the method is in the pinned surface for the first time |
| 5 | SwiftProjectLint may be paying the regression unmeasured | ✅ **moot** — its pin is past the fix |

Item 4 is the one with value left in it: a `.pureButPartial` function is a real candidate whose law
narrows to the success set, and it is the surface the seed manifest's own `isPartial` field was built
to carry. This repo has had the method available since 2026-08-06 and does not call it.

Item 3 has a **new** motivating symptom rather than a hypothetical one — see the `@EffectUnknown` row
above. A guard phrased as *equality with the sibling consumer* would currently fail, correctly.

---

## Traps

- **The README is stale in a way that inverts its meaning.** It says *"Status: Pre-extraction
  skeleton"* and *"The current skeleton has no behavior; the test target only asserts the namespaces
  compile."* There are ~3,700 lines of working engines and a mutation corpus. Read `Sources/`, not
  the README.
- **`Effect.rank` values are not stable.** They shifted when `pure` was inserted at the bottom. Never
  serialize them.
- **The marker sets are token-matched, not AST-matched.** `Date(timeIntervalSince1970:)` refutes
  purity. That is intended over-approximation, not a bug — but it means a false refutation is the
  expected failure mode and a false `.pure` is the alarming one.
- **`lub` is left-biased on ties**, which is only observable for two `externallyIdempotent` values
  with different `keyParameter`s. `[a, b].reduce(initial) { $0.lub($1) }` therefore matches
  SwiftProjectLint's collection-form lub — first in iteration order wins.
- **Purity is refuted, never established.** Any consumer that wants to *claim* `.pure` must take the
  meet with its own domain-specific refuter, the way `SoundPurity` does. A single narrow analyzer
  answering "pure" on its own is unsound by construction.
- **`@ClockDeterministic` is a user claim, not an inference.** SEI recognizes it; it never derives
  it. Everything downstream that relaxes an async veto is trusting an author.

---

## Where to look

| question | file |
|---|---|
| the lattice, `lub`, and what was deliberately left out | `SwiftEffectInference/Sources/SwiftEffectInference/Effect.swift` |
| the purity refuters and the soundness argument | `SwiftEffectInference/Sources/SwiftEffectInference/PurityInferrer.swift` |
| both annotation grammars + the clock-determinism marker | `SwiftEffectInference/Sources/SwiftEffectInference/EffectAnnotationParser.swift` |
| collision-withdrawal and lookup precedence | `SwiftEffectInference/Sources/SwiftEffectInference/EffectSymbolTable.swift` |
| why a name match needs an `import` to count | `SwiftEffectInference/Sources/…/Internal/FrameworkGates.swift` |
| why `Set.insert` is not a non-idempotent `insert` | `SwiftEffectInference/Sources/…/Internal/StdlibIdempotentMutations.swift` |
| the full design, including the migration plan §10 | `SwiftEffectInference/docs/SwiftEffectInference Design v0.2.md` |
| **the meet this repo actually takes** | `SwiftInferProperties/Sources/SwiftInferCore/SoundPurity.swift` |
| where the verdict is recorded at scan time | `…/FunctionScannerVisitor+Summary.swift:38`, `FunctionSummary.swift` |
| the advisory channel it renders on | `…/EffectAnnotationAdvice.swift` |
| the linter's side of the same oracle | `docs/design-internal/swiftprojectlint.md` |
| vocabulary — *Purity oracle*, *Effect lattice*, `@ClockDeterministic` | `docs/design-internal/glossary.md` § Neighbours |
