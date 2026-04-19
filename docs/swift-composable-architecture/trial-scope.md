# swift-composable-architecture — Trial Scope

Fourth adopter road-test, first against the Point-Free ecosystem
— the last remaining framework tier from
[`../swift_idempotency_targets.md`](../swift_idempotency_targets.md).
TCA is pure-function-heavy and closure-based, a shape unlike the
webhook and server-framework adopters measured so far.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On a reducer-based, pure-function-heavy adopter whose canonical
> retry-exposed surface is `.run { send in ... }` effect closures
> returned from reducer cases, does the existing trailing-closure
> annotation mechanism fire correctly — and if not, what is the
> specific mechanical gap?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `114b0bf`
  (post-PR #16 tip — includes wall-clock budget on the fixed-point
  inference loop).
- **Target:** `pointfreeco/swift-composable-architecture` at SHA
  `7517cc3` on `main` (shallow clone). 536 Swift files /
  ~40k lines. Annotations live in `Examples/`.
- **Trial branch:** `trial-tca` forked from `main`. Local-only,
  not pushed.
- **Build state:** not built — SwiftSyntax-only scan.

## Annotation plan

Six `.run { send in ... }` effect closures across three example
files, each with `/// @lint.context replayable` (then flipped to
`strict_replayable` for Run B):

1. `Examples/Todos/Todos/Todos.swift:79` — `.move` case:
   `.run { send in try await self.clock.sleep(...); await send(.sortCompletedTodos) }`
2. `Examples/Todos/Todos/Todos.swift:90` — `.todos(.binding(\.isComplete))` case:
   `.run { send in try await self.clock.sleep(...); await send(.sortCompletedTodos, ...) }`
   `.cancellable(id: ..., cancelInFlight: true)`
3. `Examples/CaseStudies/SwiftUICaseStudies/03-Effects-Basics.swift:51` —
   `.decrementButtonTapped` case: cancellable `.run { }` with clock sleep.
4. `Examples/CaseStudies/SwiftUICaseStudies/03-Effects-Basics.swift:76` —
   `.numberFactButtonTapped` case: `.run { [count] send in await send(.numberFactResponse(Result { try await self.factClient.fetch(count) })) }`
5. `Examples/Search/Search/SearchView.swift:84` — `.searchQueryChangeDebounced`:
   debounced API call via `.run { [query] send in await send(.searchResponse(...)) }`
6. `Examples/Search/Search/SearchView.swift:101` — `.searchResultTapped`:
   weather forecast fetch wrapped in cancellable `.run { }`.

Plus one **positive-control pair** in `Todos.swift` head:
`trialSendNotification` declared `@lint.effect non_idempotent`,
`trialHandleMoveEffect` declared `@lint.context <tier>` and calls
it. Exists to prove the visitor fires on _some_ annotation site
in this file, isolating any silent-failure cause to the specific
placement shape of the six `.run { }` annotations.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling:** six `/// @lint.context` comments
  inside `.run { }` call sites, plus the positive-control pair.
  No logic or structural changes to TCA examples.
- **Scan strategy:** scan each annotated example directory
  separately (`Examples/Todos`, `Examples/Search`,
  `Examples/CaseStudies`). The TCA root `Package.swift` does
  not include the `Examples/*` xcodeproj-based projects as SPM
  targets — a single-root scan misses them.
- **Throwaway branch, not pushed.**

## Pre-committed questions for the retrospective

1. Does the existing trailing-closure annotation mechanism
   (`/// @lint.context <tier>` above a `call { closure in ... }`,
   round-11 slice) fire correctly when the annotated call is
   `.run { send in ... }` returned from a switch case?
2. What does the strict-mode residual look like? Does body-based
   inference reach through TCA's `@Dependency`-based method calls
   (`self.factClient.fetch`, `self.weatherClient.search`)?
3. Is any finding here a new named adoption-gap slice candidate,
   or does it collapse into an existing open slice?
4. What would a realistic macro-form annotation story for TCA
   look like? Adopter-side attribute-form annotations on the
   closures themselves aren't possible (closures aren't
   declarations); would the right surface be an attribute on
   the enclosing `@Reducer` struct's `body` property, or on
   individual `Reduce { ... }` / `.run { ... }` trailing closures
   via a hypothetical `@Replayable` macro?
