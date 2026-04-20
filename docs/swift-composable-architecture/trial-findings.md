# swift-composable-architecture — Trial Findings

Post-PR-#19 remeasurement. This is the third time the TCA corpus has
been scanned; the evolution tracks three linter slices that each
surfaced on this round:

| Linter tip | Commit | Replayable | Strict | Note |
|---|---|---:|---:|---|
| Round-original | `114b0bf` | 1 | 1 | `return`-trailing annotation bug hid all 6 `.run { }` sites |
| Post-PR #17 | `4c8623f` | 7 | 22 | annotations land; cluster 1 (`send`) + cluster 4 (dep-clients) visible |
| Post-PR #18 | `5698683` | 1 | 16 | TCA `send` closure-parameter override silences cluster 1 (6 fires) |
| **Post-PR #19 + #20** | **`bc3c05e`** | **1** | **13** | **closure-property effect declarations close cluster 4 (3 fires)** |

The current scan (this document) reflects tip `bc3c05e` with the
trial-tca branch carrying `@lint.effect idempotent` annotations on
`WeatherClient.search`, `WeatherClient.forecast`, and
`FactClient.fetch` as closure properties — exactly the shape PR #19
teaches `EffectSymbolTable.merge(source:)` to recognise.

## Run A — replayable mode

Source transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).
**1 diagnostic.**

| # | File:line | Callee | Verdict |
|---|---|---|---|
| 1 | `Examples/Todos/Todos/Todos.swift:15` | `trialSendNotification` | positive control — fires correctly |

**Yield**: 1 catch / 7 annotated sites (positive control + 6
`.run { }`) = **0.14 including silent**. The 6 `.run { }` sites are
silent because their only previously-flagged `send(.action)` callee
is now classified `idempotent` via the TCA bare-name override
(PR #18) — the effect closures are no longer flagged anywhere in
replayable mode.

Silent does not mean a gap. The closures reach `send(...)` (TCA
action dispatch — pure state transition), `weatherClient.search(...)`
/ `factClient.fetch(...)` (now annotated `idempotent`), and
`clock.sleep(...)` (observational by framework contract). Under
replayable tier — where the `nonIdempotentInRetryContext` rule fires
only on provably non-idempotent callees — none of these warrant a
diagnostic. The positive control confirms the visitor is walking
these bodies.

## Run B — strict_replayable mode

Source transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).
**13 diagnostics** (1 carried from Run A + 12 strict-only).

### Carried from Run A (1)

Same as Run A: `trialHandleMoveEffect` → `trialSendNotification`,
relabelled `strict_replayable`.

### Strict-only (12)

Fires on unclassified callees inside the annotated `.run { }`
closures. All produce the `unannotatedInStrictReplayableContext`
diagnostic.

| # | File:line | Callee | Cluster | Verdict |
|---|---|---|---|---|
| 2 | `Todos.swift:89` | `sleep` | clock | defensible — `ContinuousClock.sleep` via TCA `@Dependency(\.continuousClock)`; observational in retry context |
| 3 | `Todos.swift:89` | `milliseconds` | Duration | noise — `.milliseconds(100)` `Duration` implicit-member |
| 4 | `Todos.swift:100` | `sleep` | clock | same as (2) |
| 5 | `Todos.swift:100` | `seconds` | Duration | noise — `.seconds(1)` `Duration` implicit-member |
| 6 | `SearchView.swift:86` | `searchResponse` | enum-case | noise — `Action.searchResponse(...)` enum-case constructor |
| 7 | `SearchView.swift:86` | `Result` | Result-init | noise — `Result { try await ... }` throwing-init |
| 8 | `SearchView.swift:104` | `forecastResponse` | enum-case | noise — `Action.forecastResponse(...)` |
| 9 | `SearchView.swift:106` | `Result` | Result-init | noise — same as (7) |
| 10 | `03-Effects-Basics.swift:53` | `sleep` | clock | same as (2) |
| 11 | `03-Effects-Basics.swift:53` | `seconds` | Duration | noise |
| 12 | `03-Effects-Basics.swift:78` | `numberFactResponse` | enum-case | noise |
| 13 | `03-Effects-Basics.swift:78` | `Result` | Result-init | noise |

### Decomposition into named slice clusters

The five clusters named in the round-original findings evolved across
three slices. Current state:

1. **`send`-on-closure-parameter** — **closed** by PR #18
   (commit `5698683`, bare-name override gated on
   `import ComposableArchitecture`). 6 of 6 fires eliminated.
2. **`Duration` constructors** — **3 fires remain** (`.milliseconds(100)`,
   `.seconds(1)`, `.seconds(1)`). These are implicit-member-access
   expressions (`.milliseconds(100)`), *not* `Type.init(...)` form, so
   PR #20 (`.init(...)` normalisation) does not address them. The
   leaf shape is: callee is `MemberAccessExpr` with `base == nil` and
   `declName == "milliseconds"`/`"seconds"`. Would slice cleanly under
   a stdlib-type-member whitelist gated on `Duration` as the inferred
   contextual type — but that inference doesn't exist and building it
   is a bigger slice than the ~1-fire-per-corpus impact justifies. See
   §Follow-up slice candidates.
3. **Enum case constructors + `Result { }`** — **6 fires remain**
   (4 enum case, 2 `Result`). Same shape as cluster 2 (implicit-member
   plus bare-identifier for `Result`). Noise, not adoption gap — these
   are genuinely idempotent data constructors with no effect. Closable
   via adopter-side `@lint.effect idempotent` annotations on individual
   cases, or a stdlib-type-member whitelist for `Result`. Neither is
   slice-worthy at current volumes.
4. **Dependency-client method calls** — **closed** by PR #19
   (commit `0be2d36`, closure-property declarations). 3 of 3 fires
   eliminated via `@lint.effect idempotent` on the `@DependencyClient`
   struct closure properties on trial-tca.
5. **`sleep` on `ContinuousClock`** — **3 fires remain**. Same count
   as round-original. Would close under a stdlib-clock-primitive
   whitelist entry — targeted, low risk. Not sliced yet because the
   defensible verdict is stable (no false positives, no false
   negatives); slicing it is a precision-polish move, not a
   correctness-unblock.

## Comparison to prior measurements

| Metric | Round-original (`114b0bf`) | Post-#17 (`4c8623f`) | Post-#18 (`5698683`) | **Post-#19+#20 (`bc3c05e`)** |
|---|---:|---:|---:|---:|
| Annotated sites recognised | 1 / 7 | 7 / 7 | 7 / 7 | 7 / 7 |
| Replayable diagnostics | 1 | 7 | 1 | **1** |
| Strict diagnostics | 1 | 22 | 16 | **13** |
| Sites producing ≥1 diagnostic | 1 / 7 | 7 / 7 | 1 / 7 (strict only) | 1 / 7 (strict only) |
| Open named adoption gaps | 1 (visibility) | 2 (clusters 1, 4) | 1 (cluster 4) | **0** |

**The round is fully closed on adoption-gap terms.** All three linter
slices that originated in this round (return-trailing annotation,
TCA `send` override, closure-property declarations) have landed and
remeasured cleanly. The residual 13 strict diagnostics decompose
into three known noise/defensible clusters (Duration, enum-case +
Result, clock-sleep) that track as cross-adopter patterns, not
TCA-specific gaps.

## Follow-up slice candidates

These are **noise-reduction** slices, not correctness-unblocks. Each
would close a row in the 12-strict residual above. Priority is set by
cross-adopter recurrence, not this-round volume.

1. **`ContinuousClock.sleep` whitelist entry** (3 fires here). Gated
   on `_Concurrency` import presence — `ContinuousClock` / `SuspendingClock`
   / `ClockOf` are the stdlib clock types whose `.sleep(for:)` is
   observational-by-contract. Smallest slice; candidate for "stdlib
   whitelist group" if other stdlib clock / time-primitive patterns
   surface in future rounds.
2. **Stdlib `Duration` / time-primitive implicit-member whitelist**
   (3 fires here). The implicit-member shape `.seconds(1)` /
   `.milliseconds(100)` is a `DurationProtocol` factory method on a
   type the parser can't resolve without type-checking. Either:
   (a) pattern-match the callee names (`seconds`, `milliseconds`,
   `nanoseconds`, `microseconds`) as bare-name idempotent when receiver
   is nil — risky, collides with any user function of the same name;
   (b) defer to a future type-resolution improvement. (b) is correct
   long-term; (a) is too risky for the yield.
3. **Enum-case constructor + `Result { }` recognition** (6 fires
   here; widespread across Swift). `Result(catching:)` is a stdlib
   codec-shape. Enum case constructors are generally pure data
   constructors — classifying them as idempotent requires recognising
   the `.caseName(...)` implicit-member shape as an enum case
   constructor vs. an arbitrary method call, which the linter can't
   do without type-checking. Adopter-side `@lint.effect idempotent`
   on specific enum cases works today.

No single candidate exceeds the ~2-fire-per-round threshold used for
slot-2-style promotion in [`../next_steps.md`](../next_steps.md). The
residual is the expected tail for strict-mode inference without full
type-resolution, and the "why was this unannotated?" diagnostic prose
already tells adopters what to do: add `/// @lint.effect idempotent`.

## Source state on trial-tca

Annotations on the `trial-tca` branch as scanned:

- 7 × `/// @lint.context strict_replayable` — positive control +
  6 `.run { }` sites across Todos / Search / CaseStudies.
- 1 × `/// @lint.effect non_idempotent` — `trialSendNotification`
  (positive control target).
- 3 × `/// @lint.effect idempotent` — `WeatherClient.search`,
  `WeatherClient.forecast`, `FactClient.fetch` (closure properties
  on `@DependencyClient` structs; the shape PR #19 unlocked).

No logic edits to TCA; annotation-only diff.
