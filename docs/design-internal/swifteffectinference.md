# SwiftEffectInference — the shared leaf

**Repo:** `~/xcode_projects/SwiftEffectInference` (`github.com/Joseph-Cursio/SwiftEffectInference`) ·
**Book home:** Appendix C; Chapter 26 §26.3 (the lattice), Chapter 22 §22.6 (clock-determinism).

> **As of 2026-08-03** · subject `SwiftEffectInference@097181a` (HEAD; **this repo pins `1f2265a0`**
> — see the pin section) · observer `SwiftInferProperties@2722975`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.

<!-- doc-provenance date=2026-08-03 subject=SwiftEffectInference@097181aa3ebcca3918c98cf071ca083d69d97650 pinned=1f2265a0fa63a9659886024a01fb3221bddc8768 observer=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

The smallest package in the toolchain and the only one with **no CLI and no dependents below it** —
13 source files, ~3,700 lines, depends on nothing in the set. It is a library two other tools
*embed*, which is the entire architectural point: **the linter and the inference engine consult one
purity oracle, so they cannot disagree about what is pure.**

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

`Sources/SwiftInferCore/SoundPurity.swift` — 45 lines, and the reason the conjunctive framing above
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

## The pin divergence

SEI carries **no version tags**, so both consumers pin by revision. They are not pinned to the same
revision.

| package | manifest | revision |
|---|---|---|
| SwiftInferProperties | `Package.swift:122` + `Package.resolved` | `1f2265a0` |
| SwiftProjectLint | root + `SwiftProjectLintVisitors` + `SwiftProjectLintIdempotencyRules`, all three | `097181aa` |

`097181aa` is SEI's `HEAD` and is **9 commits ahead** of `1f2265a0`. The gap is not cosmetic — it is
the purity oracle's public surface:

| `PurityInferrer` public API | at `1f2265a0` (this repo) | at `097181aa` (the linter) |
|---|---|---|
| `inferredEffect(for: FunctionDeclSyntax)` | ✅ | ✅ |
| `isPure(_: FunctionDeclSyntax)` | ✅ | ✅ |
| `verdict(for:) -> PurityVerdict` | ❌ | ✅ |
| `isPure(_: ClosureExprSyntax)` | ❌ | ✅ |
| `isPure(_: AccessorBlockSyntax)` | ❌ | ✅ |

**Two methods against five.** The three the linter has and this repo does not are exactly the three
that matter to the pipeline's known failure modes:

- **`PurityVerdict.pureButPartial`** separates *transparency* from *totality*. Its own doc names the
  incident: collapsing them made a throwing-but-transparent function indistinguishable from one that
  reads the clock, *"which is exactly the confusion that cost the SwiftLintRuleStudio road test its
  highest-value law."* `serialize(_:) throws -> String` is a deterministic function of its argument;
  the linter refused to name it, so this repo — *"which vouches for purity via the seed and only
  checks shape itself"* — never got to propose the law it already knew how to write.
- **closure purity** — *"a great deal of pure logic in real Swift has no name"*; the backing for
  SwiftProjectLint's `Pure Closure Property-Test Candidate`.
- **computed-property purity**.

### The bump was attempted 2026-08-03 and is BLOCKED

**Do not re-apply it without reading [SwiftEffectInference#1](https://github.com/Joseph-Cursio/SwiftEffectInference/issues/1).**
`097181aa` costs a **~2× wall-clock regression on the whole-domain purity path**, which is the path
this repo's every command runs. Five of the PRD §13 budgets fail, one hard.

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

### The invariant still stands; it is just unreachable today

**Keep this pin equal to SwiftProjectLint's**, not current with SEI's HEAD. The claim the shared leaf
exists to support — *the linter and the inference engine can never disagree about what is pure* — is
about the **oracle they compile against**, not the repository. The pin is currently **unequal on
purpose**, with the reason above, which is a different and much better state than the unexamined
divergence that preceded it.

Nothing checks the condition. Same failure shape CLAUDE.md already has a rule for on the other
dependency — *"The verifier's kit pin must equal this package's own,"* guarded by
`VerifierWorkdirKitPinTests`, written after that pin drifted a full major version unnoticed. **There
is no equivalent guard for SEI**, and SwiftProjectLint has none either: it repeats the SHA in *three*
manifests coordinated by a comment saying "keep this aligned." Four manifests across two repos, no
test.

Open, in order:

1. **SEI#1** — restore the cheap path for the whole-domain question.
2. **Then** bump, and re-run `make perf` before `make test`, since perf is step 3 of 9 and fail-fast
   hides everything behind it.
3. **Then** add a pin-equality guard, phrased as *equality with the sibling consumer* rather than
   currency with HEAD.
4. **Then** consider adopting `verdict(for:)` — a `.pureButPartial` function is a real candidate whose
   law narrows to the success set, and it is the surface the seed manifest's own `isPartial` field was
   built to carry.
5. **Separately:** SwiftProjectLint is already on `097181aa` and calls `PurityInferrer` from two
   visitors over every function and closure in a project. It may be paying this regression now, with
   no wall-clock budget to say so.

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

| question | file (in `SwiftEffectInference`) |
|---|---|
| the lattice, `lub`, and what was deliberately left out | `Sources/SwiftEffectInference/Effect.swift` |
| the purity refuters and the soundness argument | `Sources/SwiftEffectInference/PurityInferrer.swift` |
| both annotation grammars + the clock-determinism marker | `Sources/SwiftEffectInference/EffectAnnotationParser.swift` |
| collision-withdrawal and lookup precedence | `Sources/SwiftEffectInference/EffectSymbolTable.swift` |
| why a name match needs an `import` to count | `Sources/…/Internal/FrameworkGates.swift` |
| why `Set.insert` is not a non-idempotent `insert` | `Sources/…/Internal/StdlibIdempotentMutations.swift` |
| the full design, including the migration plan §10 | `docs/SwiftEffectInference Design v0.2.md` |
| **the meet this repo actually takes** | `SwiftInferProperties/Sources/SwiftInferCore/SoundPurity.swift` |
| where the verdict is recorded at scan time | `…/FunctionScannerVisitor+Summary.swift:38`, `FunctionSummary.swift` |
| the advisory channel it renders on | `…/EffectAnnotationAdvice.swift` |
| the linter's side of the same oracle | `docs/design-internal/swiftprojectlint.md` |
| vocabulary — *Purity oracle*, *Effect lattice*, `@ClockDeterministic` | `docs/design-internal/glossary.md` § Neighbours |
