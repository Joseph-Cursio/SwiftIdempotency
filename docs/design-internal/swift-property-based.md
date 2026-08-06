# swift-property-based — the engine underneath

**Repo:** [`github.com/x-sheep/swift-property-based`](https://github.com/x-sheep/swift-property-based)
(Lennard Sprong) · **Book home:** Appendix C's closing section; `.fixedSeed` in Chapter 28 §28.1.1.

> **As of 2026-08-03** · subject `swift-property-based@edaffed` (`1.2.0`, the resolved pin) ·
> observer `SwiftInferProperties@2722975`. **Third-party** — the subject moves on someone else's
> schedule, and only a resolved version bump brings it here.
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.

<!-- doc-provenance date=2026-08-03 subject=swift-property-based@edaffedcd90339544fefb2f045f3fa988d94c794 version=1.2.0 observer=SwiftInferProperties@272297564d7842d5c30a6a38775898ed907fedb5 -->


**Not ours.** The only package in the toolchain nobody here controls, and nothing above runs without
it. `SwiftPropertyLaws` sits directly on it as its single backend; `SwiftIdempotency` reaches it only
through the opt-in property product; this repo touches it **only through generated code** — the stubs
`verify` compiles `import PropertyBased`, but the tool itself never links it.

```
SwiftPropertyLaws ▶ swift-property-based ◀ SwiftIdempotencyPropertyBased
        ▲                                          (opt-in product)
SwiftInferProperties ─── emits `import PropertyBased` into stubs ───┘
```

**Pinned at `1.2.0`** (`edaffedc`) in `Package.resolved`. ~3,745 lines across 32 files. Swift 6.2,
built on swift-testing, Foundation-optional.

## Why this doc exists

Because **its limits arrive here as our behaviour**, three packages downstream and unrecognisable by
then. A `.todo` in your generated stub, a replay test that runs one trial instead of a hundred, a law
you cannot state — each traces back to something in this 3,700-line library, and none of them says
so. This doc is that traceback, plus a verification of Appendix C's numbers against the source.

---

## What it provides

| piece | what |
|---|---|
| `Generator<ResultValue, ShrinkSequence>` | the real type — composable generate + shrink |
| `Gen<Value>` | **an empty enum namespace**, not a type — where the factories live |
| `propertyCheck` | the runner; **10 overloads** (1 hand-written + 9 gyb-generated for arity) |
| `Shrink.*` | **11 shrinker types** — `Integer`, `Floating`, `ElementWise`, `Tuple`, `Omit`, `Appended`, `Bitwise`, `Iterator`, `TruncateTime`, `WithNil`, `None` |
| `.fixedSeed(_:)` | a `TestTrait` that replays a failure |
| `Xoshiro` / `SeededRandomNumberGenerator` | the seeded RNG everything draws from |

Provenance note in the source: `Generator.swift` is *"Adapted from pointfreeco/swift-gen"* (MIT).

### Appendix C's numbers, checked

| claim | measured at 1.2.0 | verdict |
|---|---|---|
| "~75 factory overloads" | **74** `public static func`/`var` across the `Gen+*.swift` files | ✅ |
| "~42 generator families" | ~40 distinct factory names | ✅ close enough |
| "~10 combinators" | `map`, `compactMap`, `filter`, `zip`, `array`, `set`, `dictionary`, `string`, `optional`, `eraseToAny` (+ `eraseToAnySequence`, `withoutShrink`) | ✅ |
| **"the engine has no `flatMap`"** | **confirmed** — the only `flatMap` in the source is `Optional.flatMap` inside `filter`'s implementation | ✅ |
| "every integer width from `int8` to `int128`" | 16 factory decls in `Gen+Int.swift` | ✅ |
| "SIMD unit vectors and quaternions" | `Gen+SIMD.swift`, 12 decls, 9 `unitVector` overloads | ✅ |

---

## Four limits that surface as our behaviour

### 1. `zip` stops at 10-arity → your struct's 11th field is a `.todo`

`Zip.swift` (and its `.gyb` template) declares **exactly 9 `zip` overloads — 2-arity through
10-arity.** That is the whole reason `PropertyLawCore.DerivationStrategy` says:

> v1 supports 1–10 members; arity 11+ falls through to `.todo` because `swift-property-based` ships
> `zip` overloads up to 10-arity.

So the chain is: **engine overload count → kit derivation cap → a `<#…#>` placeholder in a stub this
repo emitted.** A reader hitting that placeholder is three packages away from the cause, and nothing
in the placeholder says "an eleventh stored property is one too many." Worth naming when you see it.

### 2. No `flatMap` → dependent generation must go through `map` and a closure

You cannot write "generate `n`, then generate an array of length `n`" as a monadic bind. Appendix C
turns this into a virtue for one case — generating a *function* needs no new combinator, because a
pure function is a seed plus a hash and a plain `map` closes over the seed:

```swift
Gen<Int>.int(in: 0...65_535).map { seed in
    let f: @Sendable (Int, Int) -> Bool = { a, b in
        var h = Hasher(); h.combine(seed); h.combine(a); h.combine(b)
        return h.finalize() % 2 == 0
    }
    return f
}.eraseToAny()
```

— *notable precisely because the engine has no `flatMap`, the combinator you would normally reach
for.* That is now verified against the source rather than asserted.

### 3. Shrinking runs on the **input**, not the result → a generated function cannot shrink

This is the architectural fact that explains the QuickCheck gap, and it is visible in the type:

```swift
public struct Generator<ResultValue, ShrinkSequence: SendableSequenceType> {
    public typealias InputValue = ShrinkSequence.Element
    var _runIntermediate: (inout any SeededRandomNumberGenerator) -> InputValue
    var _mapFilter:       (InputValue) -> ResultValue?
    var _shrinker:        (InputValue) -> ShrinkSequence
}
```

**The shrinker is a function of `InputValue`** — the intermediate, pre-`map` representation — and
never of `ResultValue`. So `map` is free and shrinking still works, because it shrinks *what was
drawn*, not what was returned.

Apply that to the function generator above: what shrinks is the **seed**, an `Int`. And a smaller
seed is not a simpler function — `hash(0, x)` is no more readable than `hash(76, x)`. QuickCheck's
`Fun` shrinks toward a smaller *table of distinguished input points* and prints that table. That —
**shrinking and showing a function, not conjuring one** — is the one capability class left on the
table, and the type above is why.

The display half is measurable too: force a failure with a function-valued generator and you get
`Failure occured with input (Function). (shrunk down from (Function))`. Quantify over the seed
instead and the same failure prints `Failure occured with input 0. (shrunk down from 76)` —
displayable and replayable, but still not *minimised*.

**Why this matters to this repo specifically:** a generated-comparator law is one the *author*
writes about their own sort. It has **no discovery surface** in a catalog that reads code and
proposes laws about what it finds — so nothing upstream of the engine would propose it either. The
boundary is ours as much as the engine's.

### 4. `.fixedSeed` runs **exactly one trial**

`PropertyCheck.swift`:

```swift
let actualCount = fixedRng != nil ? 1 : count
```

The doc comment says *"If a fixed seed is set, this value is ignored"* — but "ignored" undersells it.
It is not clamped or defaulted; it becomes **1**. A `.fixedSeed` test replays the single failing case
and nothing else.

That is correct for a regression test and a trap for anyone who reads
`propertyCheck(count: 500, …)` on a `.fixedSeed`-traited test and believes 500 trials ran. If you
want both, they are two tests. On failure the engine tells you the exact line to add:

> `Add .fixedSeed("…") to the Test to reproduce this issue.`

Two fixed seeds in one test is a recorded `Issue`, not a silent last-wins.

---

## What the engine assumes, that our stubs must not break

**A failing property must be *re-runnable*.** The shrinker minimises by running the property **again**
on smaller inputs — so anything that halts the process denies it the "again," and you get **no
counterexample at all**, not a coarse one. SwiftIdempotency measured both sides of exactly this:

| mechanism | output on the same bug |
|---|---|
| `precondition`-based (`#assertIdempotent`) | `Precondition failed:` + signal 5 — **no input reported** |
| `#expect`-based (`assertIdempotentProperty`) | `Failure occured with input 101.` — the boundary itself |

This repo's Pass 1 / Pass 2 split is the same constraint arriving from another direction: boundary
values cannot go in the verdict pass, because `x + 1` traps at `Int.max` and a trap is not a test
result — mixing them in turned three integration tests into `signal 5` crashes. **A composed law that
can trap is a law whose counterexample you will not get.** See `docs/verify-edge-pass.md`.

**Seeded means seeded all the way down.** The kit's `doubleWithNaN` / `floatWithNaN` drew their
finite values from `Double.random(in:)` — the *system* RNG, invisible to the engine's seed. NaN
positions replayed; the values did not. Nothing caught it, because *a law that holds does not care
whether its inputs are reproducible*. Anything that reaches for `.random` instead of threading
`Gen<Double>.double(in:)` breaks replay silently, and only a deliberately-failing test finds it.

---

## Traps

- **`Gen` is a namespace, not a type.** `public enum Gen<Value> {}` — empty. The value is a
  `Generator<ResultValue, ShrinkSequence>`, and its second parameter is usually unspeakable, which is
  why `eraseToAny()` exists and why signatures are written `Generator<Output, some Sequence>`. Prose
  across this toolchain says "synthesizes a `Gen<YourType>`"; what is synthesized is an *expression
  built from `Gen` factories* whose type is a `Generator`.
- **Two files are `.gyb`-generated** (`Zip.swift`, `PropertyCheck+Pack.swift`). Editing the `.swift`
  and not the `.gyb` is a losing move — relevant only if anyone ever forks this.
- **`filter` is a rejection sampler.** `_mapFilter` returns `ResultValue?` and `runFull` loops "until
  a single unfiltered value is found." A narrow predicate is a hang risk, not a slow test.
- **It is pinned, not vendored.** A `from:`-style bump anywhere in the graph moves it under all five
  packages at once. `Package.resolved` is the record of what actually ran.
- **The QuickCheck ledger cuts both ways.** The stack is *not* uniformly behind: on `CaseIterable`
  and `OptionSet` the engine is strictly **more general** than QuickCheck, which needs a hand-written
  instance per enum where this derives one from the conformance. And `Complex` — QuickCheck's one
  concrete-type advantage over the engine — is closed by the kit's `PropertyLawComplex`. The honest
  summary is *"ported everything value-shaped, and stopped short of making a function-shaped
  counterexample readable."*

---

## Where to look

| question | file (in the checkout) |
|---|---|
| the generate/shrink split that bounds higher-order support | `Sources/PropertyBased/Generator.swift` |
| the factory namespace | `Sources/PropertyBased/Gen*.swift` |
| **the 10-arity ceiling** | `Sources/PropertyBased/Zip.swift` (+ `.gyb`) |
| the runner, and `count` becoming 1 under a seed | `Sources/PropertyBased/PropertyCheck.swift` |
| replay semantics and the two-seeds `Issue` | `Sources/PropertyBased/FixedSeedTrait.swift` |
| the 11 shrinkers | `Sources/PropertyBased/Shrink*.swift` |
| where the 10-member cap resurfaces | `SwiftPropertyLaws/Sources/PropertyLawCore/DerivationStrategy.swift` |
| why a trapping assertion costs the counterexample | `docs/design-internal/swiftidempotency.md`, `docs/verify-edge-pass.md` |
| the curated layer on top of this engine | `docs/design-internal/swiftpropertylaws.md` |

**Checkout path:** `.build/checkouts/swift-property-based` (gitignored; also resolved under
`SwiftPropertyLaws/.build/checkouts/`). There is no working copy in `~/xcode_projects` — it is a
dependency, not a sibling.
