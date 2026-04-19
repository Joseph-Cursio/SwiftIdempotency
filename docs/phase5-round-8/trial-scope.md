# Round 8 Trial Scope

Follow-on spike to round 7. Closes the one mechanism deferred there: `@Idempotent`'s peer-macro test generation, blocked by Finding 4 (Swift Testing's `@Test` expansion producing `@used`/`@section`/`self` errors when emitted by another macro inside a struct).

## Research question

> "Can any peer-macro-adjacent role (member, extension, or a two-macro split) produce idempotency test generation that compiles cleanly inside a `@Suite struct` — where the round-7 peer-role design fails?"

Operationalised as a three-candidate spike, each measured against the same consumer sample the round-7 trial used.

## Pinned context

- **Macros package:** `/Users/joecursio/xcode_projects/SwiftIdempotencyPackage` @ branch `spike-peer-macro-redesign` forked from `da51db1` (round-7 post-fix tip).
- **Consumer sample:** `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample` (local, not git-tracked). Exactly the round-7 sample, extended with a zero-arg `currentSystemStatus()` target.
- **Linter:** untouched. `SwiftProjectLint` main is the round-7 baseline at `58d302d`.
- **Swift toolchain:** same as round 7. No toolchain migration during the spike.

## Scope commitment

- **Three candidates, time-capped.** One day per candidate; the spike stops at whichever candidate is known-working (Fallback clause in the plan).
- **In-spike fixes in scope.** Same policy as round 7. Where a candidate's first form produces a concrete error (friction), the fix is attempted inside the candidate's day budget before moving to the next candidate. Cap: three in-candidate iterations.
- **Sample package exclusively as the integration-test surface.** No third-corpus validation this round; mechanism-level trial only.
- **Red-baseline confirmation is a prerequisite.** Before any candidate, restore `@Idempotent` on `currentSystemStatus` and verify the exact three-error Finding 4 signature reproduces. A candidate "works" only if the same file compiles clean with the candidate's shape applied.
- **No linter edits.** If a candidate needs a second attribute (e.g., `@IdempotencyTests`), the linter's attribute-recognition set will need one line updated — but that's a follow-on, not part of this spike's scope.

## Candidates (as pre-committed in the plan)

- **A — `@attached(member)` on an enclosing `@Suite` attribute.** Emits `@Test` methods inside the attached type's body via member role.
- **B — `@attached(extension)` on an enclosing `@Suite` attribute.** Emits the same `@Test` methods inside a generated extension of the type.
- **C — Two-macro split: `@Idempotent` (marker) + `@IdempotentTestable` (peer emits `@Test`-free helper).** User wraps the emitted helper in their own `@Test`. No nested-macro emission.

Pre-spike prediction: **C most likely to work** (eliminates macro-inside-macro nesting entirely); A and B worth prototyping because single-attribute ergonomics win if either succeeds.

## Pre-committed questions for the retrospective

1. Which candidate landed, and what was the measured symptom on the rejected ones?
2. Did the candidate require in-spike shape-changes beyond the plan's pre-committed design? What were they?
3. What's the next unit of work now that Finding 4 is closed — `strict_replayable` tier (round-7 retrospective direction 2), or something surfaced during this spike?
4. Is the `SampleWebhookAppTests` sample still useful as ongoing validation infrastructure, or should round-8 artefacts subsume it?

## Acceptance

- Red baseline confirmed before any candidate.
- Each candidate gets a per-candidate entry in `trial-findings.md`: unit-test result, integration-test result, error text on failure, fix attempted on friction.
- Landing candidate compiles and runs clean in the sample, with the emitted test passing.
- Macros package test suite green at spike-end; no regressions against the round-7 test count (was 39/4).
