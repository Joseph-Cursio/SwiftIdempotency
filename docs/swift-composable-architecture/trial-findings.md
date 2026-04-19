# swift-composable-architecture — Trial Findings

Post-fix remeasurement. The initial round on this target ran against
SwiftProjectLint `114b0bf` and produced **zero diagnostics on the six
`.run { send in ... }` sites** because doc-comment annotations above
`return .run { ... }` bound to the `return` keyword, not the call.
The round surfaced `return-trailing-annotation` as a correctness
slice; SwiftProjectLint PR #17 landed as commit `4c8623f` and this
document records the remeasurement.

Pre-fix findings: replayable = 1, strict = 1 (positive control only).
Post-fix findings (below): replayable = 7, strict = 22 — **all six
`.run { }` annotation sites now create analysis sites** and produce
diagnostics on the calls inside them.

## Run A — replayable mode

Source transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).
**7 diagnostics.**

| # | File:line | Callee | Verdict |
|---|---|---|---|
| 1 | `Examples/Todos/Todos/Todos.swift:15` | `trialSendNotification` | positive control — fires correctly |
| 2 | `Examples/Todos/Todos/Todos.swift:90` | `send` | defensible (TCA `Send<Action>` closure parameter — see §Adoption gap) |
| 3 | `Examples/Todos/Todos/Todos.swift:101` | `send` | defensible (same shape) |
| 4 | `Examples/Search/Search/SearchView.swift:86` | `send` | defensible (same shape) |
| 5 | `Examples/Search/Search/SearchView.swift:103` | `send` | defensible (same shape) |
| 6 | `Examples/CaseStudies/SwiftUICaseStudies/03-Effects-Basics.swift:54` | `send` | defensible (same shape, ternary-branch placement) |
| 7 | `Examples/CaseStudies/SwiftUICaseStudies/03-Effects-Basics.swift:78` | `send` | defensible (same shape) |

**Yield**: 7 catches / 7 annotated sites (positive control + 6
`.run { }`) = **1.00 including silent**. Zero sites are silent under
the fix — every annotation produces at least one diagnostic.

Every `.run { send in ... }` closure contains a `send(...)` call. The
heuristic reads bare `send` and infers `non_idempotent` from the
callee name. Semantically this is a false positive — `send` in a TCA
effect closure is the `Send<Action>` closure parameter that
dispatches actions, not an external-effect "send email" method. The
annotation is now being recognised, which is the round's primary
validation. The downstream precision question is tracked as a
separate slice candidate (see §Adoption gap).

## Run B — strict_replayable mode

Source transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).
**22 diagnostics** (7 carried from Run A + 15 strict-only).

### Carried from Run A (7)

Same 7 diagnostics as replayable mode, re-labelled `strict_replayable`.
No new fires from the `nonIdempotentInRetryContext` rule.

### Strict-only (15)

Fires on unclassified callees inside the annotated `.run { }`
closures. All produce the `unannotatedInStrictReplayableContext`
diagnostic.

| # | File:line | Callee | Verdict |
|---|---|---|---|
| 8 | `Todos.swift:89` | `sleep` | defensible — `ContinuousClock.sleep` via TCA `@Dependency(\.continuousClock)`; stdlib clock sleep is observational in a retry context |
| 9 | `Todos.swift:89` | `milliseconds` | noise — `.milliseconds(100)` `Duration` constructor |
| 10 | `Todos.swift:100` | `sleep` | same as (8) |
| 11 | `Todos.swift:100` | `seconds` | noise — `Duration` constructor |
| 12 | `SearchView.swift:86` | `searchResponse` | noise — enum case constructor `Action.searchResponse(...)` |
| 13 | `SearchView.swift:86` | `Result` | noise — `Result { try await ... }` constructor |
| 14 | `SearchView.swift:86` | `search` | **adoption gap** — `weatherClient.search(query:)` via `@Dependency(\.weatherClient)`. Idiomatic TCA dependency-client call; GET-shape. Classifiable with receiver-type resolution + dependency-keypath awareness. |
| 15 | `SearchView.swift:104` | `forecastResponse` | noise — enum case constructor |
| 16 | `SearchView.swift:106` | `Result` | noise — `Result { ... }` constructor |
| 17 | `SearchView.swift:106` | `forecast` | **adoption gap** — same shape as (14), `weatherClient.forecast(location:)` |
| 18 | `03-Effects-Basics.swift:53` | `sleep` | same as (8) |
| 19 | `03-Effects-Basics.swift:53` | `seconds` | noise — `Duration` constructor |
| 20 | `03-Effects-Basics.swift:78` | `numberFactResponse` | noise — enum case constructor |
| 21 | `03-Effects-Basics.swift:78` | `Result` | noise — `Result { ... }` constructor |
| 22 | `03-Effects-Basics.swift:78` | `fetch` | **adoption gap** — `factClient.fetch` via `@Dependency(\.factClient)` |

### Decomposition into named slice clusters

1. **`send`-on-closure-parameter** (6 fires, already called out
   in Run A): bare-name `send` matches the non-idempotent heuristic
   but in TCA refers to `Send<Action>.callAsFunction(_:)` — an
   action dispatcher, not a side-effectful method. Fix directions:
   receiver-type resolution on closure parameter types, or a
   `composableArchitecture` framework whitelist gated on
   `import ComposableArchitecture`.
2. **`Duration` constructors** (3 fires): `.milliseconds(100)`,
   `.seconds(1)`. Sits under the existing `.init(...)` member-access
   form gap already tracked in
   [`../next_steps.md`](../next_steps.md) slot 4 — stdlib `Duration`
   constructors match the same `Type.method(value:)` shape as
   `JSONDecoder()`. Would close cleanly alongside that slice.
3. **Enum case constructors** (4 fires): `.searchResponse`,
   `.forecastResponse`, `.numberFactResponse`, `Result { }`. All are
   pure data constructors — noise, not adoption gap. Could be
   silenced via `@lint.effect idempotent` on the enum cases if
   adopters care, but this isn't a heuristic problem.
4. **Dependency-client method calls** (3 fires —
   `weatherClient.search`, `weatherClient.forecast`,
   `factClient.fetch`): TCA's core testability pattern. The
   linter sees `self.weatherClient.search(query:)` but cannot
   classify it because the `@Dependency(\.weatherClient)`
   property wrapper hides the receiver's real type from syntactic
   analysis. A TCA-specific adoption gap; a generic
   receiver-type-via-property-wrapper improvement would unlock
   this class of dispatches for any `@propertyWrapper`-based
   DSL (SwiftUI `@Environment`, etc.).
5. **`sleep` on `ContinuousClock`** (3 fires): defensible —
   sleep is observational, but the linter doesn't know that
   without a stdlib whitelist entry. Small, targeted slice;
   likely worthwhile.

## Comparison to pre-fix measurement

| Metric | Pre-fix (`114b0bf`) | Post-fix (`4c8623f`) |
|---|---:|---:|
| Annotated sites recognised | 1 / 7 | 7 / 7 |
| Replayable diagnostics | 1 | 7 |
| Strict diagnostics | 1 | 22 |
| Sites producing ≥1 diagnostic | 1 / 7 (14%) | 7 / 7 (100%) |
| New named slice clusters | 1 (`return-trailing-annotation`) | 2 (`send`-on-closure-param; dependency-client receiver resolution) |

The slice closed the visibility gap completely — every annotated
site now creates an analysis site. The remeasurement re-opens the
round's primary research question: now that the linter can reach
the `.run { }` bodies, what's inside them? Answer: two new slice
candidates (1 and 4 above).

## Current verdict summary

- **1 correct catch** — positive control on `trialHandleMoveEffect`.
- **6 defensible** — `send` on closure parameter across all TCA
  effects; shape is semantically safe but the heuristic can't tell.
- **7 noise** — stdlib/enum constructors; category already tracked
  under existing slots.
- **3 adoption gaps** — dependency-client method dispatch via
  `@Dependency` property wrappers. New TCA-specific slice.
- **3 defensible** — `ContinuousClock.sleep` uses; small stdlib
  whitelist slice would silence.
