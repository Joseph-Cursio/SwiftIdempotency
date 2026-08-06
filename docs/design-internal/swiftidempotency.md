# SwiftIdempotency — the terminal package

**Repo:** `~/xcode_projects/SwiftIdempotency` (`github.com/Joseph-Cursio/swiftidempotency`) ·
**Book home:** Chapter 26; the `@Pure`/`@ClockDeterministic` markers in Chapter 22 §22.6; the
sequence property's MBT reading in Chapter 19 §19.5.2.

> **As of 2026-08-03** · subject `SwiftIdempotency@11cfebb` (`0.4.1`+4) · observer
> `SwiftInferProperties@2722975`. **No dependency edge** — this repo never links the subject, so
> nothing but prose keeps the two aligned.
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.

<!-- doc-provenance date=2026-08-03 subject=SwiftIdempotency@11cfebb97c2cc71fba8dac0af11234b8a3946080 version=0.4.1 observer=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 -->


```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
```

**Read the arrow as workflow, not dependency.** This repo does not depend on SwiftIdempotency —
`Package.swift` and `Package.resolved` contain zero references to it, and neither does the kit. It is
the end of the *adoption loop*, not the bottom of a dependency graph.

So the honest question this doc answers is narrower than the previous three: **what does property
inference actually touch here?** Measured by grep over `Sources/` on 2026-08-03:

| grammar term | occurrences in this repo |
|---|---|
| `@ClockDeterministic` | **9** |
| `@Pure` · `@Idempotent` · `@NonIdempotent` · `@Observational` · `@ExternallyIdempotent` | 0 |
| `IdempotencyKey` · `assertIdempotent` | 0 |

**One word of shared vocabulary, and this repo never links the package that defines it.** The join
runs through SwiftEffectInference, which parses a grammar SwiftIdempotency owns:

```
SwiftIdempotency  defines the grammar  (@Pure, @Idempotent, @ClockDeterministic, …)
        │
SwiftEffectInference  parses it        (EffectAnnotationParser)
        ├──▶ SwiftProjectLint      ENFORCES it (idempotencyViolation)
        └──▶ SwiftInferProperties  READS it    (the async admission gate)
```

That is Chapter 26 §26.4's **annotate-once-enforced-twice** loop, and it is why an author's claim can
reach two tools that never see each other.

---

## The package itself

Version `0.4.1` (`git describe`: `0.4.1-4-g11cfebb`). Four library products; the last is opt-in:

| product | what it is |
|---|---|
| `SwiftIdempotency` | the `IdempotencyKey` type + the marker macros |
| `SwiftIdempotencyTestSupport` | `assertIdempotentEffects(recorders:)`, the effect recorders |
| `SwiftIdempotencyFluent` | FluentKit integration (drags in `fluent-kit`) |
| `SwiftIdempotencyPropertyBased` | **the only one that touches `swift-property-based`** |

### Tier 1 — `IdempotencyKey`, enforced by the type checker

The type has **no `init()`**, no `init(_ uuid: UUID)`, no `ExpressibleByStringLiteral`. Two
construction paths only: `init(from:)` (requires `Identifiable`) and `init(fromAuditedString:)`
(requires the caller to explicitly audit a string as stable across retries).

> Using `UUID()` or `Date()` as a key becomes a type error — not a runtime mistake, not a lint
> finding, a compile-time failure.

Note what that shares with this repo's purity oracle: `UUID()` and `Date()` are also two of
`PurityInferrer`'s nondeterminism markers. The same two calls are refuted by a token scan in one
package and by a missing initializer in another — belt and braces on the same failure.

### Tier 2 — the annotation grammar

Six markers, each with a doc-comment twin:

| attribute | doc comment | on the lattice? |
|---|---|---|
| `@Pure` | `/// @lint.effect pure` | ✅ bottom |
| `@Observational` | `/// @lint.effect observational` | ✅ |
| `@Idempotent` | `/// @lint.effect idempotent` | ✅ |
| `@ExternallyIdempotent(by:)` | `/// @lint.effect externally_idempotent(by:)` | ✅ |
| `@NonIdempotent` | `/// @lint.effect non_idempotent` | ✅ top |
| **`@ClockDeterministic`** | **`/// @lint.determinism clock_deterministic`** | ❌ **orthogonal** |

All are `@attached(peer)` macros — they attach nothing and generate nothing. **Their entire job is
to be readable by a static analyzer**, which is why a package that emits no code still matters to two
that read it. The README calls it a one-way producer: SwiftIdempotency defines the grammar and takes
no inference dependency in return.

### Tier 3 — test scaffolding

`@IdempotencyTests` on a `@Suite` emits one `@Test` per `@Idempotent` zero-argument member. The
expansion is **effect-aware** — `try` and `await` appear only when the target's signature needs them,
so non-throwing targets don't produce spurious `"no calls to throwing functions occur within 'try'
expression"` warnings. For parameterised functions, the freestanding `#assertIdempotent` macro has
sync and async overloads and lets Swift's overload resolution pick.

### Tier 4 — the property forms (and the finding worth the trip)

`SwiftIdempotencyPropertyBased` v0.4.0 ships `assertIdempotentProperty` and
`assertIdempotentEffectsProperty`. The reason they exist rather than "just call `#assertIdempotent`
inside `propertyCheck`" is a measured lesson that generalises well past this package:

> `#assertIdempotent { … }` fails via `precondition`, which **terminates the test process** — so on a
> failing property the process dies before the shrinker can find a minimal counterexample.

And the correction the repo made to its own claim is the better half. `trial-findings.md` had carried
this as a *reasoned but unverified* limitation, predicting users "get the raw randomised input on
failure rather than a shrunk one." Somebody finally wrote the deliberately-failing property. It took
about five minutes.

> The mechanism was right and the consequence was wrong, **in the optimistic direction**. There is no
> input in the output at all. The process traps and the value goes with it.

Same bug (non-idempotent only above 100), two assertion mechanisms:

| mechanism | output |
|---|---|
| `#assertIdempotent` | `Precondition failed: …` + signal 5 — **no mention of the input** |
| `assertIdempotentProperty` (`#expect`) | `Failure occured with input 101.` — the boundary itself |

> **A shrinker minimises by running the property *again* on smaller inputs, and a trapping assertion
> denies it the "again."** There is no degraded-but-useful mode; there is no output.

This is the same shape as this repo's Pass 1 / Pass 2 asymmetry — boundary values cannot go in the
verdict pass because `x + 1` traps at `Int.max`, and a trap is not a test result. **A fatal assertion
inside a property is a category error**, and it costs the whole counterexample, not just its
minimality. Worth carrying into any law this repo emits that could trap.

---

## What this repo actually consumes: `@ClockDeterministic`

The single point of contact, and it is deliberately **not on the lattice**. `@Pure` implies
*synchronous* referential transparency, so an async function can never be `.pure` no matter what the
author claims. The marker lives in its own `@lint.determinism` namespace for exactly that reason:

> Attaching it grants no lattice trust — it makes a *determinism* claim.

`EffectAnnotationParser.isClockDeterministic(declaration:)` recognises both spellings and answers
outside `Effect` entirely. This repo consumes the claim as a **conjunction gate on its async vetoes**:

- an annotated async function earns the generic determinism law
  `(await f(x)) == (await f(x))` over generated inputs;
- an annotated async view-model method joins the synthetic action surface with an awaited dispatcher;
- **un-annotated async stays excluded**, because it would make seeded sequence replays
  nondeterministic — and bare `async` keeps a clean rejection that says how to make the claim.

Carried here by `ViewModelDiscoveryVisitor:154` → `FunctionSummary.isClockDeterministic` →
`ReducerCandidate.isClockDeterministic`, decoded with a `false` default.

**The claim is checkable, and that is the point.** It asserts exactly the property SwiftPropertyLaws'
`TimedAsyncSequence.debounceIsDeterministicUnderTestClock` states: under a virtual clock, two runs
produce identical output. Annotate a function that secretly reads `Date()` or sleeps on a clock it
didn't inject, and **the emitted determinism law is the test that falsifies the claim.** The author
makes an assertion; this repo turns it into something that can fail.

That is the whole loop in one marker: SwiftIdempotency provides the vocabulary for a human to state
something a tool cannot infer, and the toolchain then holds them to it.

---

## Traps

### "Idempotent" means three different things across this toolchain

The most expensive confusion available here, and the source states it outright:

> This is SwiftIdempotency's notion of idempotence (**effects don't accumulate across retries**), not
> the algebraic `f(f(x)) == f(x)`.

| where | "idempotent" means | shape |
|---|---|---|
| this repo's `idempotence` **template** | applying the function twice equals applying it once | `f(f(x)) == f(x)` — a **value** law |
| this repo's `idempotence` **interaction family** | dispatching the same action twice leaves state unchanged | a law over a reducer |
| SwiftIdempotency / the SEI lattice | calling twice has the same **observable effect** as calling once | a law over the world |

The first is checkable in-process over generated values. The third generally is not — it is about
database rows and HTTP calls — which is why SwiftIdempotency reaches for effect *recorders* rather
than equality. A carrier can satisfy any one and fail the others. When reading `.idempotent` on the
lattice, it is the third.

### Other things worth knowing

- **The grammar join has no contract test.** `PBTSeedRole` ↔ `SeedRole` gets one
  (`SeedRoleContractTests`) because a drifted entailment claim would propose a false law. The
  attribute-name join is softer — `AttributeRecognition` is configurable and defaults to
  `["Pure"], ["Idempotent"], …` — but nothing in any repo asserts those strings still match the
  shipped macro names. A rename in SwiftIdempotency would silently stop being recognised, and the
  symptom is a *missing* annotation, which looks exactly like an unannotated codebase.
- **`@Pure` was recognised prospectively before it shipped.** SEI's default set carried the name for
  a while before swiftidempotency's 2026-07-10 release made the attribute spelling compile. Recognition
  running ahead of the grammar is the safe direction; the reverse would be silent.
- **This repo recommends the *other* idiom.** `EffectAnnotationAdvice.recommendedAnnotation` defaults
  to `"/// @lint.effect pure"` — the doc-comment form — with no attribute-form option. A project that
  has adopted `@Pure` gets advised in the spelling it didn't choose. Harmless (both parse), but
  noticeable to a reader, and a one-line fix if it ever bothers anyone.
- **This repo never proposes an idempotency annotation.** `SoundPurity` only ever yields `Effect.pure`,
  so the advisory channel is single-tier by construction. Nothing here suggests `@Idempotent` — that
  is the linter's `idempotencyViolation` rule's job, going the other way (policing a claim already
  made).
- **`@ClockDeterministic` is a user claim, never an inference.** Everything downstream that relaxes an
  async veto is trusting an author. The falsifying law is the safety net, not the gate.

---

## Where to look

| question | file |
|---|---|
| the key type and its two construction paths | `SwiftIdempotency/Sources/SwiftIdempotency/IdempotencyKey.swift` |
| the five effect markers | `…/Sources/SwiftIdempotency/Idempotent.swift` |
| **the one marker this repo reads**, and why it is off the lattice | `…/Sources/SwiftIdempotency/ClockDeterministic.swift` |
| why a trapping assertion destroys a counterexample | `…/Sources/SwiftIdempotencyPropertyBased/AssertIdempotentProperty.swift` |
| the verified-and-worse-than-predicted write-up | `…/docs/property-based/trial-findings.md`, commit `7fc5128` |
| task-oriented adoption, incl. coordinating with the linter | `…/USER_GUIDE.md` · `TUTORIAL.md` · `REFERENCE.md` |
| who parses the grammar | `docs/design-internal/swifteffectinference.md` |
| who enforces it | `docs/design-internal/swiftprojectlint.md` |
| where the claim is consumed here | `Sources/SwiftInferCore/FunctionSummary.swift`, `ReducerCandidate.swift`, `ViewModelDiscoveryVisitor.swift:154` |
| vocabulary — `@ClockDeterministic`, *Effect lattice* | `docs/design-internal/glossary.md` § Neighbours |
