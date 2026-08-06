# SwiftPropertyLaws — the law kit

**Repo:** `~/xcode_projects/SwiftPropertyLaws` (`github.com/Joseph-Cursio/SwiftPropertyLaws`) ·
**Book home:** Chapters 13–14, Appendix A; law families surface in nearly every chapter.

> **As of 2026-08-03** · subject `SwiftPropertyLaws@14d8987` (`v3.26.0`, equal to this repo's pin) ·
> observer `SwiftInferProperties@2722975`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.

<!-- doc-provenance date=2026-08-03 subject=SwiftPropertyLaws@14d89875d80ce99e1dce2ac5d2021c8cc1299bf1 version=3.26.0 observer=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
                            │                   run the laws
                            └── also DEPENDS on it (PropertyLawCore) ──┘
```

The kit is the only package in the toolchain that this repo relates to **in both directions**, and
that is the thing to hold onto. The pipeline diagram says "downstream" and the `Package.swift` says
"dependency" — both are true, and they are different products.

| direction | product | what crosses the boundary |
|---|---|---|
| **↑ upstream (build-time)** | `PropertyLawCore`, `PropertyLawSyntaxSupport` | `DerivationStrategist` — generator synthesis this repo must not reimplement |
| **↓ downstream (run-time)** | `PropertyLawKit` (+ opt-in products) | `check<Protocol>PropertyLaws` calls emitted into stubs and scaffolds |
| **↔ sideways (inference-time)** | neither — a *claim about* the kit | `ProtocolCoverageMap`'s veto, and `KitEvidence` reading its verdicts back |

**Pin:** `from: "3.26.0"` (`Package.swift:112`), resolving to `14d89875` / tag `v3.26.0` — currently
**equal to the kit's `HEAD`**. Read the pin from `Package.swift`, never from prose; this line has
been a full major version stale before.

---

## Products

Seven library products, and the split is a dependency-footprint decision, not a taxonomy:

| product | purpose | drags in |
|---|---|---|
| `PropertyLawKit` | the law suites — the main line | `swift-property-based` only |
| `PropertyLawCore` | `DerivationStrategist` + the `TypeShape` value types | — |
| `PropertyLawSyntaxSupport` | SwiftSyntax → `TypeShape` | swift-syntax |
| `PropertyLawMacro` | `@PropertyLawSuite` | swift-syntax macros |
| `PropertyLawComplex` | edge-biased `Complex` generators | **swift-numerics** |
| `PropertyLawCollections` | the swift-collections catalog, incl. model-based `HeapLaws` | **swift-collections** |
| `PropertyLawAsync` | `AsyncSequenceLaw`, virtual-time `TimedAsyncLaw` | — |

The three opt-ins exist so `PropertyLawKit` keeps a **zero swift-numerics / swift-collections
footprint**. This repo consumes `PropertyLawCore` + `PropertyLawSyntaxSupport` as build
dependencies, and emits `PropertyLawComplex` into *generated* stubs' imports — it is not a dependency
of this package. `SeededStubEmitter.swift:101` carries the base import set
(`ComplexModule`, `Foundation`, `PropertyBased`, `PropertyLawComplex`, `RealModule`);
`DoubleEdgeCaseStub` deliberately omits it.

**44 `check…PropertyLaws` suites** ship today (`grep -rho 'public func check[A-Za-z]*PropertyLaws'`,
2026-08-03) — the stdlib conformance protocols, the owned algebraic chain (`Semigroup` → `Ring`),
the interaction-invariant harnesses of Chapters 19/23–24, and the collection/async families.

**`Ring` is no longer deferred** — `checkRingPropertyLaws` ships. Still deferred kit-side:
`CommutativeGroup`, `Group acting on T`.

---

## ↑ Upstream: `DerivationStrategist`, and the rule not to reimplement it

PRD §11 and CLAUDE.md both state it as a standing decision: **generator inference delegates to
SwiftPropertyLaws. Call `DerivationStrategist`; don't reimplement.**

The reason is in the strategist's own doc — the macro and the discovery plugin *already* both call it
with their own SwiftSyntax-built `TypeShape` and emit identical generator text. A third caller
inventing its own derivation would make three tools that disagree about what `Gen<YourType>` is.

`DerivationStrategy` is the returned decision, and the tier order is PRD §5.7's priority list:

| case | when |
|---|---|
| `userGen` | the user defined `T.gen()` — just reference it |
| `caseIterable` | `Gen<T?>.element(of: T.allCases).compactMap { $0 }` (the Optional is load-bearing) |
| `rawRepresentable(RawType)` | lift the raw generator through `init(rawValue:)` with `compactMap` for sparse spaces |
| `enumCases(cases:)` | every case's payload resolves — `Gen.oneOf` over per-case generators |
| `memberwiseArbitrary(members:)` | every stored property resolves — `zip(…)` through the synthesized memberwise init |
| `initializerBased(arguments:)` | a user `init` suppressed the memberwise one; compose per-argument and honour labels |
| **`todo(reason:)`** | **nothing matched** |

**The arity cliff is real and worth knowing:** memberwise derivation supports **1–10 members**, and
11+ falls through to `.todo` — because `swift-property-based` ships `zip` overloads up to 10-arity.
That is an engine limit surfacing as a kit limit surfacing as a `.todo` in your stub.

**`.todo` is the boundary, not a failure.** It emits a deliberate compile error pointing at where the
user provides `gen()`, plus a `TodoReason` diagnostic that names the *specific* reason by type kind,
so the reader knows whether to add a `gen()` or restructure the type. In this repo's vocabulary a
`.todo` is what `scaffold` renders as a `<#…#>` placeholder, and it is the honest edge of automation
— §14.2.2 in the book.

Consumed here through `TypeShapeBuilder`, `IndexedTypeShape`, `CarrierKindResolver`,
`FunctionScanner`, `MemberBlockInspector` — the recipe's `expression` reaches verify as a **string**,
and composers read the generator solely from `recipe.expression`.

---

## ↓ Downstream: the kit runs the laws

Two emitters generate calls **into** the kit:

**1. Verify stubs.** `VerifierWorkdir` builds a throwaway SwiftPM package per suggestion, whose
manifest carries `VerifierWorkdir.swiftPropertyLawsRequirement` — currently `"3.26.0"`,
**equal to this package's own pin and guarded by `VerifierWorkdirKitPinTests`.**

> **The verifier's kit pin must equal this package's own.** A `--corpus-module` survey resolves both
> in one graph; disjoint major ranges make *every* entry report `measured-error: build-failed`, which
> reads as an architectural limitation rather than a broken manifest. Never write the version as a
> literal in a mode arm — that is exactly how it drifted a full major version.

**2. `scaffold-kit-suites`.** `KitSuiteEmitter` — the interesting one, because it exists to close a
gap the veto created:

> The kit's suites cover **996 laws over 299 carriers**, of which **5 execute.** The gap was never a
> missing capability — `ProtocolCoverageMap`'s veto suppresses each of those laws with a message that
> *names* the call and generates nothing. It tells you the test exists and leaves you to type ~299
> call sites.

Its constraint is derivability, measured before it was built: `check<Protocol>PropertyLaws` takes
`using generator:` with **no default**, so every suite needs a `Generator<Value, _>`, and
`DerivationStrategist` derives one for **180 of 351** covered carriers (51%), covering **598 of
1,153** laws. The other half emit **commented out**, carrying the kit's own `.todo` reason — because
emitting them live produces a file that does not compile, and omitting them silently reports half the
work as all of it (the "no silent caps" failure). It does **not** guarantee the live half compiles:
`Value: Sendable` is not always visible from a `TypeShape`, and a carrier may be `private`. Output is
a draft for review; nothing writes it into a build.

The standing argument for emitting at all is independent of running: *a law you can read is a claim
you can disagree with* — and `fixtures/equatable-signal` measured exactly the case where `Equatable`'s
laws pass on a broken type.

---

## ↔ Sideways: claims *about* the kit, made inside this repo

This is where the bugs live, because these are assertions about a package the project may not even
depend on, and for a long time nothing checked them.

### `ProtocolCoverageMap` — the veto

Suppresses a law when a conformance means the kit already checks it, so the reader is not
double-reported. Three findings worth carrying:

**1. The veto's premise was unchecked.** `assumedKitCoverage` takes only
`(summary, inheritedTypesByName)`; no path reads `Package.swift` for SwiftPropertyLaws. So the veto is
unconditional while the coverage it assumes is conditional on adoption — and the failure is silent in
the worst way, because *a veto that prevents double-reporting looks exactly like nothing to report*.
`ProtocolCoverageAudit` makes it visible; `wasExercised` alone cannot separate "the kit never ran"
from "it ran elsewhere" (the log's **emptiness** is what tells them apart).

**2. Measured 2026-08-01, the veto is close to a no-op.** Running `discover` with it disabled returns
*identical* output on five of six corpora, and `SwiftPropertyLaws` 20 vs 21 — **1 suggestion out of
~300.** That kills the Daikon-flood argument for auditing rather than un-vetoing, and simultaneously
kills the case *for* un-vetoing.

**3. 13 of 56 `(key, law)` claims were false** (`docs/protocol-coverage-law-drift.md`, kit `4a2dada`).
The live one: `checkSetAlgebraPropertyLaws` runs fifteen laws and **union associativity was not one of
them** — yet the map claimed it, a template emitted it, and a green test *pinned the suppression as
correct*. **Both halves are now fixed**, and the current source shows it — `"SetAlgebra"` lists six
laws with union associativity gone, and the comment records `equatableBase` removed 2026-08-02
because `checkSetAlgebraPropertyLaws` does not delegate to `checkEquatablePropertyLaws`.
`KitCoverageLawLevelTests` now verifies all 17 keys law-by-law against a 27-row
`KnownProperty → [kit law identifier]` table, with delegation **read** from
`await check<Parent>PropertyLaws` rather than re-derived from Swift's conformance graph.

Still open, in order: `Self` resolution in `assumedCoverageSignal` (deliberately last — resolving it
makes the map live *including* any remaining false claims), a behavioural companion to the guard, and
the under-claim direction (`SetAlgebra` claims 6 of 15, `Strideable` 1 of 12).

### `KitEvidence` — the kit's verdicts feeding back

The toolchain was one-way: `discover` proposed, the kit ran, and nothing came back — even though the
kit's verdicts are the **only executed evidence anywhere**. The asymmetry of the fix is argued rather
than assumed: `==` correctness is the Equatable laws' *job*, so inference is entitled to **assume** it.

| kit result | effect on score | why |
|---|---|---|
| no evidence | unchanged | the normal case |
| **passed** | score-**neutral** provenance | a sound `==` does not make `f(f(x)) == f(x)` truer; it makes testing it meaningful |
| **refuted** | **−45** (`KitEvidenceScoring.refutedOracleWeight`) | the assumption inference relied on is measured false, and every `==`-shaped law about that carrier inherits the problem |

**Demote, never veto** — the reader needs the prerequisite, not an empty run. Three measured
exclusions: Heuristic-tier failures, `.expectedViolation`, and `Comparable.totalOrder`. And the
demotion **can hide its own explanation** — `−45` on a 70-point pick lands at 25, below the default
cut — so the diagnosis is emitted as a run-level warning **before** the cut. Reporting on survivors
would guarantee silence in exactly the case worth reporting.

---

## The generator story, and where it actually lives

Worth being precise, because Appendix C is:

- **`swift-property-based` (Lennard Sprong, external)** owns `Gen`, `propertyCheck`, the shrinkers,
  `.fixedSeed` replay, and **~42 generator families / ~75 factory overloads** plus ~10 combinators.
  This is the engine, and every package above sits on it.
- **The kit adds about nine curated generators** — the Foundation types the engine lacks (`uuid`,
  `url`, `data`, `decimal`) and the edge-biased numerics (`doubleWithNaN`, `floatWithNaN`,
  `boundedForArithmetic`, `PropertyLawComplex.edgeCaseBiased`).
- **The kit's real generator contribution is not a catalog but `DerivationStrategist`** — it
  *synthesizes* a `Gen<YourType>` per type rather than shipping one.

**A seeding trap the kit already hit, found by pointing this toolchain at it.** `doubleWithNaN` and
`floatWithNaN` drew their finite values from `Double.random(in:)` — the **system** RNG, invisible to
a seed. NaN *positions* replayed; the values did not, so a FloatingPoint law failing on an ordinary
value could not be reproduced from the seed it failed under. **Nothing caught it**: both generators
run on every suite, and *a law that holds does not care whether its inputs are reproducible*. Found by
SwiftProjectLint's `Non-Injected Nondeterminism` rule; guarded by `NaNGeneratorSeedingTests`,
including the assertion that finite values **actually vary** — a constant would satisfy every replay
assertion and destroy the generator. `PropertyLawComplex.edgeCaseBiased()` deliberately keeps its
unseeded finite path and now says so at the call site.

---

## Traps

- **`measured-bothPass` means "no counterexample in the generated domain," not "the property
  holds."** A derived generator is tuned for coverage of the *type* and is silently mistuned for
  coverage of the *law*. Anything whose failure needs two values to **collide** — merge tie-breaks,
  cache-key collisions, dedup, key injectivity — is invisible. Narrow the alphabet deliberately and
  say so in a comment.
- **The map's claims are about a package the reader may not depend on.** A veto firing and a clean
  bill of health are indistinguishable from the output.
- **`Semigroup: []` and `CommutativeMonoid` are placeholders**, not coverage — the protocols were
  considered and no template emits the property. *Add the entry WITH the template, not before.*
- **Suite granularity is not law granularity.** `KitCoverageDriftTests` passed green through all 13
  false claims because every assertion worked at the *suite* level and none opened the
  `Set<KnownProperty>` on the value side. Its own comment named the failure it could not see.
- **`.multiplicativeInverse → []` is deliberate** — the enum carries it for symmetry, no kit law
  implements it, and the empty list *is* the assertion.
- **Parsing the kit's law identifiers: do not require a closing quote.** `Codable`'s is interpolated
  (`"Codable.roundTripFidelity[\(codec)]"`), and a stricter pattern read as *the kit ships no Codable
  law*.
- **A third catalog belongs in this join.** `known-properties`' 71 executable stdlib laws overlap the
  kit's 182 by ~40% with nothing between them — it independently asserts set union associativity as
  known-true, the exact law the false claim said the kit ran. The two catalogs together would have
  caught that defect the day it was written.

---

## Where to look

| question | file |
|---|---|
| the derivation tiers and the 10-member arity cliff | `SwiftPropertyLaws/Sources/PropertyLawCore/DerivationStrategy.swift` |
| what a `.todo` tells the user | `…/PropertyLawCore/TodoReason.swift` |
| the products and their dependency footprints | `SwiftPropertyLaws/Package.swift` |
| the kit's own running notes (NaN seeding, codegen fixes) | `SwiftPropertyLaws/CLAUDE.md` |
| **the pin, and why it must equal the verifier's** | `Sources/SwiftInferCLI/VerifierWorkdir+KitPin.swift`, `VerifierWorkdirKitPinTests` |
| emitting kit suite calls, and the 51% derivability bound | `Sources/SwiftInferCLI/KitSuiteEmitter.swift` |
| the veto, key by key | `Sources/SwiftInferCore/ProtocolCoverageMap.swift` |
| whether the veto's premise is true | `Sources/SwiftInferCore/ProtocolCoverageAudit.swift` |
| whether the claims are true **law by law** | `docs/protocol-coverage-law-drift.md` |
| kit verdicts feeding back into scoring | `Sources/SwiftInferCore/KitEvidence*.swift` |
| does the emitted suite catch a real bug? | `docs/kit-suite-backtest-plan.md` — Arm 1 is a measured HIT |
| the sibling packages | `docs/design-internal/swiftprojectlint.md`, `swifteffectinference.md` |
| vocabulary — *Strategist / generator recipe*, *Stub*, *Outcome* | `docs/design-internal/glossary.md` § Verify |
