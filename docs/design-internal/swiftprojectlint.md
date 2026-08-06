# SwiftProjectLint — the entry point

**Repo:** `~/xcode_projects/SwiftProjectLint` (`github.com/Joseph-Cursio/SwiftProjectLint`) ·
**Book home:** Appendix C, Chapter 15, and the seed hand-off in Chapters 12 and 16.

> **Counts re-verified 2026-08-03 (second pass)** · subject `SwiftProjectLint@9c5b305` · observer
> `SwiftInferProperties@201e3ea`
>
> Counts and measurements here are **dated and will rot**. Diagnoses, design rationale, and the
> reasons a decision was made **do not expire** — they were true when recorded and stay checkable.
> If the subject repo has moved, re-verify the numbers; don't re-litigate the prose.
>
> **What the first pass got wrong, and how it was caught.** This doc was written against
> `6c88715` — a local checkout that turned out to be **46 commits behind its origin**. Two counts
> were stale within hours (`RuleIdentifier` 197 → 202, the testability family 7 → 9), and
> `make docs-drift` reported `ok` throughout, because it compared against local `HEAD` rather than
> the project. Both the checker and these numbers are fixed; the episode is why the checker now
> resolves a project tip and reports a behind-by-N clone as its own fact.

<!-- doc-provenance date=2026-08-03 subject=SwiftProjectLint@9c5b305cdacd11f268f005beb5051df192cf7b7e observer=SwiftInferProperties@201e3eaa2b2ea0dfbed030a2fa1444453ee7e029 -->

---

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
  refactor + seeds       discover + stubs        run the laws         retry-safety
        ▲                        ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

A SwiftSyntax static analyzer with a macOS app and a CI-friendly CLI. Most of it has nothing to do
with property inference — it is a SwiftUI architecture linter. **This doc covers only the part that
does**, which is two jobs and nothing else:

| | job | output channel | who consumes it |
|---|---|---|---|
| **1** | **Make property-testable code exist** — extract a pure function, give a primitive a domain type, remove a blocker | the human-readable report | a person, who edits code |
| **2** | **Say where to point the next tool** — `{file, line, symbol, rule, kind, role}` | `--format pbt-seeds` JSON | `swift-infer discover --seeds`, and **only** that |

The two jobs are not independent, and the direction is the interesting part: **job 1's output
becomes job 2's input on the next run.** A kernel you extract this week is a named, analysable
symbol next week. That loop is the whole reason the linter sits upstream rather than beside.

It never says whether a property *holds*. It says where to look and what to fix.

---

## Job 1 — refactorings that create a subject

### 1a. Extract a pure function (the kernel family)

Three rules find pure logic, and they differ by **whether the logic already has a name**:

| rule | the logic is… | seed kind | can a tool act on it? |
|---|---|---|---|
| `Pure Function Property-Test Candidate` | a `func` | `pure-function` | yes — index it, propose laws |
| `Pure Closure Property-Test Candidate` | a closure passed to `sorted`/`filter`/`map`/`reduce` | `extractable-kernel` | **no** — extract it first |
| `Extractable Pure Kernel` | statements in the middle of an impure method | `extractable-kernel` | **no** — extract it first |

The third is the valuable one and the reason this family exists. `Docs/rules/extractable-pure-kernel.md`
carries the motivating case verbatim: `uploadRemainingChunks` is `private async throws`, does network
I/O, and has chunk arithmetic inlined in it that is a function of `(data.count, chunkSize, index)`
and nothing else. Two real bugs lived there — an unclamped resume counter that completes a partial
upload, and an empty file that never reports progress — and **no test could reach either**, because
reaching the arithmetic means standing up a live session and a server.

> A closure at least *exists* as a syntactic object. A kernel does not. It is a handful of statements
> separated from the I/O around it by nothing at all.

So the refactoring is not a style preference. It is the act of **creating a callable subject where
there was none** — and the linter's advice ("name this arithmetic") is exactly the precondition
`swift-infer` needs before it can do anything at all.

`ExtractablePureKernelVisitor` and `PureClosureCandidateVisitor` both hold a
`SwiftEffectInference.PurityInferrer` directly; `PureFunctionCandidateVisitor` reaches it through
`PropertyTestCandidacy`. That is why the linter and `swift-infer` can never disagree about what is
pure — same oracle, one instance each.

**Two gates worth knowing, both loosened by a road test that measured what the tightness cost:**

- **`throws` is not disqualifying.** A throwing function is reported as *pure but partial*
  (`PropertyTestCandidate.isPartial`). `throws` refutes *totality*, not referential transparency, and
  the consumer already knew how to narrow a law to the success set — `(try? f(x)) == (try? f(x))`.
  The exclusion meant `serialize(_:) throws -> String` was never named, so nothing downstream could
  propose it.
- **Instance methods are included.** `PropertyTestShape` is two-valued — `.ofInputs` and
  `.ofSelfAndInputs` — so a method reading only immutable stored state is a candidate, it just needs
  a `self` built first.

`PropertyTestCandidacy` is shared rather than private for a specific reason stated in its own doc:
`couldBePrivateMember` tells you to narrow a declaration used only in its own file, which is sound
scope advice that — applied to a pure function — puts it beyond `@testable import`. **Two rules each
individually right, composing into advice that destroys what the other just found.** They consult one
predicate so the rule can say what narrowing would cost.

### 1b. Give a primitive a domain type

Three Architecture rules, all `Info`, all **opt-in**:

| rule | signal | design |
|---|---|---|
| `Primitive Bypassing Its Domain Type` | a `[String: V]` beside an existing `[IdempotencyKey: V]` — same value type | Variant A, structural |
| `Primitive Named For Its Domain Type` | `idempotencyKey: String` in a project that declares `struct IdempotencyKey` | Variant B, name-keyed |
| `Shared Domain-Enum Field` | ≥3 unrelated types carrying the same project enum under the same field name, sharing no protocol | extract a marker protocol |

The design note is the one to keep: **primitive obsession is not detectable by a linter.** Whether a
given `String` "is really a dedup key" is domain knowledge in the developer's head, not in the
syntax. So the rules do not detect the disease — they **police the cure**. Once a newtype `W` over
primitive `P` exists and is used to key a map, a same-shaped map still keyed by raw `P` is a decidable
cross-file inconsistency. Undecidable becomes a cross-file check.

The matching value type is the false-positive guard, and it only holds when `V` is itself
distinctive — a bare-primitive value type (`[…: String]`) makes it worthless, because those maps are
ubiquitous. A 32-project field sweep is cited in the rule doc for that calibration.

**Why this family matters for property inference at all:** a law is stated over a **carrier**, and a
newtype is a carrier with an invariant that a bare `String` does not have. `Percentage` can own
"always in `0...100`"; `String` cannot. The refactor turns a value with no laws into a type that owes
some.

**And here is the honest gap: none of these three rules seed.** `PBTSeedsFormatter.seedKinds` maps
exactly four rules, and all four are testability/idempotency (below). A reader who adopts a domain
type gets no manifest entry for it, and the linter's own history says why that is expensive — see
*"a finding the linter prints but does not seed is a finding the pipeline does not have"* under Job 2.
Whether these should seed is **open**, not decided; the carrier they create has no callable function
attached, so a `pure-function` kind would be a lie and a new kind would be a v3 schema event.

### 1c. Blockers — things to remove before anything works

`Global Mutable State` · `Non-Injected Nondeterminism` · `Missing Equatable on State Type` ·
`Impure Call in View Body`. Warnings about things that are broken; they do not seed and are not
collapsed from the report. `Missing Equatable` is the quiet one — a law needs `==` to state a
conclusion, so a state type without it cannot carry one.

**The family grew to 9 on 2026-08-03** (`View Hosting Before Inspection`,
`Observable Environment View Missing Inspection Hook`). Both are about **ViewInspector** — whether a
test can drive a SwiftUI view at all — which is testability in the harness sense rather than the
property sense. Neither seeds, and the seeding set is unchanged at four: this family is the category
`--categories testability` selects, not the set `PBTSeedsFormatter` reads.

---

## Job 2 — the seed manifest

`swiftprojectlint <path> --format pbt-seeds > .pbt/seeds.json`, consumed by
`swift-infer discover --seeds`. One hop, one consumer.

### Schema (v2)

```json
{ "version": 2,
  "seeds": [ { "file": "Sync.swift", "line": 41, "symbol": "chunkCount",
               "rule": "Pure Function Property-Test Candidate",
               "kind": "pure-function", "role": "partition" },
             { "file": "Sync.swift", "line": 88, "symbol": "offset",
               "rule": "Pure Function Property-Test Candidate",
               "kind": "restricted-function", "restriction": "enclosing-type" } ] }
```

Both sides pin **2** (`PBTSeedManifest.currentVersion`, `SeedManifest.supportedVersion`). Producer
and consumer each declare `file`/`line`/`symbol`/`kind` required and `role` optional, for the same
stated reason: an absent role is honestly unknown and nothing acts on it, whereas an absent `kind`
would have to be *guessed*, and the guess decides whether a consumer narrows discovery onto the seed.

**`restriction` (added 2026-08-03, optional, `restricted-function` only)** — `declaration` or
`enclosing-type`, from `TestRestriction`. `kind` says a test cannot reach the symbol; this says what
would have to move, and **the two remedies are not interchangeable**: widening a member nested
inside a `private` type compiles and changes nothing, so a consumer acting on `kind` alone can emit
a patch that unblocks nothing and then read the resulting verification failure as evidence against
the *law*. `enclosing-type` wins when both apply, because it names the binding constraint.

Measured when it shipped: **27 of 338** restricted seeds on SwiftProjectLint (8%) and **18 of 659**
on SwiftInferProperties (2.7%) are `enclosing-type` — small, non-zero, and silent in exactly the
direction that would have been misread. No version bump: absent means "producer does not classify",
and a seed without it is byte-identical to one written before.

### The four seeding rules

```swift
static let seedKinds: [RuleIdentifier: PBTSeedKind] = [
    .pureFunctionCandidate:  .pureFunction,
    .idempotencyViolation:   .idempotency,
    .extractablePureKernel:  .extractableKernel,
    .pureClosureCandidate:   .extractableKernel
]
```

`.pureClosureCandidate` was held back once as "a separate, deliberate step," and the source records
what that cost: the kernel visitor is arithmetic-shaped, so on the road-test fixture it seeded
`uploadRemainingChunks` and `collect` and **could not see** `fetchLocalFiles`, whose logic is a
predicate and a comparator. The closure rule fired on both halves and said the right thing — and the
finding died in the formatter. No reader was asked to extract it, no comparator law was proposed, and
the bug in the predicate was reached by 1 cold reader in 3, by ignoring the manifest and reading the
code.

> **A finding the linter prints but does not seed is a finding the pipeline does not have.**

### Three fields, three different questions

| field | question | authority |
|---|---|---|
| `symbol` | *where* to look | `LintIssue.symbol` |
| `kind` | *whether a tool can call it yet* | `PBTSeedKind.isAnalysable` |
| `role` | *what law it owes* | `PBTSeedRole.impliesEntailedLaw` |

**`kind` — analysable vs refactor-pending.** `pure-function`, `idempotency` and `restricted-function`
are analysable; `extractable-kernel` is not. Feed a refactor-pending seed to a focus filter and you
get a **confident zero**: the tool narrows to a symbol it must then refuse (`private async throws`
refutes purity) and reports `kept 0` for a codebase full of property-testable logic.

**`restricted-function` is a label, not a gate**, and getting that wrong was measured. `@testable
import` reaches `internal` and no further, so a `private` pure function is analysable but not
verifiable from another module. The kind first shipped with `isAnalysable == false`, which conflated
two different obstacles:

| | symbol to analyse? | law proposable? | blocker |
|---|---|---|---|
| `extractableKernel` | no — the logic has no name | no | someone must draw a boundary |
| `restrictedFunction` | **yes** — name and signature | **yes** | one keyword, to *verify* it |

Answering the verification question with the analysis flag **suppressed 319 seeds on the linter's own
repository**, and silently switched off a `swift-infer` feature keyed to the analysable set. An app
has no public API; its pure logic lives in `private` helpers, so a private helper is often the *best*
property target.

The demotion happens in `PBTSeedsFormatter.effectiveKind`, driven by `TestReachability` — three-valued
(`reachable` / `unreachable` / `unknown`), because "the rule did not look" is a genuine third state
that must not be confused with "I looked and it is reachable."

**`role` — what the code is.** Six cases; three imply a law a *correct* implementation cannot fail:

| role | owes | entailed? |
|---|---|---|
| `comparator` | a strict weak ordering | ✅ |
| `predicate` | totality | ✅ |
| `partition` | a tiling — parts reassemble the whole, no gap, no overlap | ✅ |
| `transform` | only that it is a function | ❌ conjecture |
| `reducer` | *usually* associative, *often* has an identity | ❌ conjecture |
| `normalizer` | a round-trip and idempotence | ❌ conjecture |

`transform` and `reducer` are carried anyway and honestly: *"a consumer that wants only entailed roles
can filter; a consumer that never hears about a reducer cannot."*

**The entailment claim is what can rot**, not the spelling — `SeedRole.unrecognised` handles a
spelling mismatch loudly. If `swift-infer` ever demotes `comparator`/`predicate`/`partition` out of
`Refutability.roleEntailedTemplates`, the producer's `impliesEntailedLaw` becomes a lie in the exact
direction the whole project is designed against: proposing a law that correct code fails.
`SeedRoleContractTests` pins the correspondence from the consumer side.

The field exists because the consumer asked for it in its own output — `discover` was already warning
*"the manifest SHOULD have named it: this is a LINTER gap."*

### Two silences the formatter was taught to break

**Dropped seeds.** A seed-bearing finding with no resolved `symbol` is dropped, which is correct
behaviour and the wrong silence: the output is still valid JSON, still exits 0, and is simply shorter
than the run that produced it. `LintConfiguration.applyOverrides` rebuilt `LintIssue` without
carrying `symbol` across, so **configuring a severity on any seed-bearing rule silently emptied that
rule's contribution** — a confident zero at the entry point of the whole loop. The linter's own
`lossyStructRebuild` rule reported the responsible line and the finding went unread, which is the
argument for detecting the loss where it happens. `PBTSeedsFormatter.droppedSeeds` returns a
per-rule tally; the CLI prints it to **stderr** so stdout stays a clean manifest.

**The census flood.** On its own repository a default run produces **876 findings, 664 of them (76%)
from the two candidate rules** — 460 pure functions and 204 pure closures. That is not a bug in either
rule; the pipeline needs every one. It is a bug in what a human sees: the road test's sharpest result
was that the linter found a real defect in its own configuration code, reported it correctly, and
**the finding went unread**, buried among hundreds of "this function is pure" lines that require no
action and cannot be wrong. *Volume that large does not inform; it functions as silence.* This is the
Daikon trap arriving at the entry point.

`CandidateInventory` fixes it in **presentation, not detection** — and that distinction is
load-bearing. The CLI computes `issues` once and hands the same array to the report formatter and to
`PBTSeedsFormatter`; disabling the rules would empty the manifest and stop the linter feeding
`swift-infer` at all. So candidates are still found, counted, exported, and exit-code relevant; they
are just not printed one per line. Only `text` collapses — JSON/CSV stay complete, and `pbt-seeds`
exists precisely to carry them. `--categories testability` is itself the opt-in and turns collapsing
off.

**`.extractablePureKernel` stays listed**, and the rule is worth generalising: *a candidate rule
**nominates** ("this is pure, it could be property-tested") — there is nothing to do per item. A
kernel rule **diagnoses** ("pure logic is trapped here, and here is the refactor") — that is a claim
about a specific place, it can be wrong, and it is worth reading each time.*

`--format pbt-seeds` also bypasses the severity exit gate: it is an extraction format, not a lint
gate, and a redirect into `.pbt/seeds.json` must not abort under a threshold.

---

## The hand-off, read from the consumer side

Worth reading `Sources/SwiftInferCLI/Discover+Seeds.swift` in full; the short version:

- **A seed focuses, it does not extend.** Discovery scans the whole target and *then* narrows to
  seeded functions. An empty manifest focuses to **zero**, not to all. A missing or malformed file is
  an error, not a silent fallback.
- **Refactor-pending seeds never focus.** They are reported to the reader as work to do.
- **The focus never hides a law the code OWES.** `keepRoleEntailedLaws` overrides the focus for
  role-entailed laws, and the warning it prints names the **linter** as the culprit: *"the manifest
  SHOULD have named it: this is a LINTER gap … the usual cause is a shape the linter cannot see —
  methods on a value type it just told you to extract, a computed-property read, a call to `min`."*
- That rule was earned by a cold reader whose sentence is the specification: **"Doing what the tool
  asked *lost* coverage."** They performed the extraction the linter demanded; the linter then failed
  to seed the value type it had just told them to create; the focus found no match for the
  `partition` law discovery had produced and dropped it. The sharpest law in the run vanished
  *because the reader complied*.
- `guardFinalAnswer` is the backstop: a non-empty answer containing zero refutable laws, when the run
  found one, is a lie and the law comes back — with opposite warnings depending on whether the **tier
  cut** (a scoring bug) or the **focus** (a linter gap) ate it.

---

## Traps

- **Rule counts disagree across three places.** README says 160, Appendix C says 189,
  `RuleIdentifier.swift` has **202** `case`s. **Read the enum.** (`RuleIdentifier.allCases.count` is the
  only figure anything tests against.)
- **`PBTSeed.role`'s doc comment is stale.** It says roles are absent for *"every rule but the two
  candidate rules"* — but `ExtractablePureKernelVisitor:106` sets `role: kernel.role` too, so three
  of the four seeding rules classify. `.idempotencyViolation` is the only one that does not.
- **Only `PureFunctionCandidateVisitor` sets `testReachability`.** Everything else leaves it
  `.unknown`, which `effectiveKind` treats as reachable — deliberately, since demoting on "the rule
  did not look" would silently shrink the manifest. Consequence: the `restricted-function` demotion
  applies to pure-function seeds and to nothing else today.
- **The seed count is not a suggestion count.** 1,657 seeds have produced 21 default-tier picks on
  SwiftInferProperties. Never report one as evidence about the other.
- **The repo's own README opens with "THIS IS AN EXPERIMENT IN VIBE-CODING"** and says outright that
  some rules are bad ideas, some are poorly implemented, and some are both. The testability and
  idempotency families are the road-tested ones; treat a rule outside them as unvetted until measured.

---

## Where to look

| question | file (in `SwiftProjectLint`) |
|---|---|
| the manifest schema, seed kinds, dropped-seed detection | `Sources/Core/Export/PBTSeedsFormatter.swift` |
| what a role is and why these six | `Packages/SwiftProjectLintModels/…/PBTSeedRole.swift` |
| reachability's three values | `Packages/SwiftProjectLintModels/…/TestReachability.swift` |
| why the report collapses candidates but the manifest does not | `Sources/Core/Export/CandidateInventory.swift` |
| what counts as a pure-function candidate | `Packages/SwiftProjectLintVisitors/…/PropertyTestCandidacy.swift` |
| the kernel motivating case, with its two real bugs | `Docs/rules/extractable-pure-kernel.md` |
| policing the cure vs detecting the disease | `Docs/design/primitive-bypassing-domain-type-rule-design.md` |
| the format wiring and the exit-gate bypass | `Sources/CLI/OutputFormat.swift`, `SwiftProjectLintCLI.swift` |
| consumer side of the same hop | `SwiftInferProperties/Sources/SwiftInferCLI/Discover+Seeds.swift`, `SeedManifest.swift`, `SeedRole.swift` |
| the vocabulary, both sides | `docs/design-internal/glossary.md` — *Seed / seed manifest*, *Role-entailed*, *Confident zero* |
