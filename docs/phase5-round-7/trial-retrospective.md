# Round 7 Trial Retrospective

One page. First cross-package validation of the macros package. The question it has to answer: did the Phase 5 macros package ship as designed, and — more importantly — what did end-to-end integration reveal that the unit-test surface couldn't?

## Did the scope hold?

**Yes, with in-trial fixes accepted into scope.** The scope doc anticipated that some discoveries would produce code changes rather than just measurements. That call proved right — four frictions surfaced, three produced immediate fixes (label rename, `names: arbitrary` restoration, expansion simplification), one produced a documented limitation (peer-macro `@Test` interaction).

The honest alternative — treat the trial as pure measurement and defer all fixes to a follow-on session — would have buried the findings under a layer of "works-in-theory" framing that R1-R6's rhythm explicitly avoids. Fixing in-trial and documenting the fix journey produced a sharper record.

## Answers to the four pre-committed questions

### (a) Attribute-form annotations integrate end-to-end?

**Yes.** The linter's `EffectAnnotationParser` scans attribute lists for `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent(by:)` identically to doc-comment annotations. The sample's `sendGiftEmail` declared `@ExternallyIdempotent(by: "idempotencyKey")` and the linter correctly treated it as lattice-trusted from `handlePaymentIntent`'s replayable context — 0 diagnostics on what was a legitimate call graph. Mechanism works exactly as designed.

### (b) `IdempotencyKey` compile-time enforcement works?

**Yes, after Finding 1's label rename.** `UUID()` cannot be passed where `IdempotencyKey` is expected, and neither can any other per-invocation generator. The type has no construction path from `UUID` or `Date`, so the rejection is type-level. The linter's `missingIdempotencyKey` rule remains as a fallback for code paths that accept raw `String` keys (e.g. library functions outside the adopter's control), but for code that uses the `IdempotencyKey` type, the whole class of mistake is un-expressible.

Finding 1 — the `Codable.init(from:)` collision in consumer modules — was a real gap the internal test suite didn't catch. Worth naming as the biggest lesson of the trial: macro-internal tests and consumer-module usage have different type-resolution contexts; validating in both is necessary.

### (c) `@Idempotent` peer-macro test generation works?

**No — deferred with documented limitation.** Four cumulative frictions (Findings 2-4 plus the global-scope Finding 2 variant) block the originally designed path. The expansion unit tests (`IdempotentPeerMacroTests`, 9 cases) all pass against `assertMacroExpansion`, but real-integration usage in a `@Suite struct` hits Swift Testing's internal "cannot use instance member within property initializer" error (Finding 4).

The `@Idempotent` attribute still works as a linter-consumed annotation — the peer-test-generation feature is what's blocked. Users who want idempotency test scaffolding should use `#assertIdempotent { body }` inside a hand-written `@Test` method. That path is green and demonstrated in the sample.

### (d) `#assertIdempotent` works?

**Yes.** Both trailing-closure form (`try #assertIdempotent { foo() }`) and explicit-paren form (`try #assertIdempotent({ foo() })`) expand to calls into `SwiftIdempotency.__idempotencyAssertRunTwice(_:file:line:)` — a `rethrows` helper that runs the closure twice, compares results via `precondition`, returns first. Runtime tests in the sample exercise both forms and pass cleanly.

The Phase-4 design decision to defer to a runtime helper (rather than inline the double-invocation as an immediately-invoked closure expansion) turned out to be the right call. The helper's `rethrows` + `inlinable` combination keeps call sites clean and avoids the `-> _` type-placeholder issue Phase 4's first-pass design had.

## What would have changed the outcome

- **Consumer-module integration tests written before shipping.** Round 7 caught four frictions that an "implementation-phase sample" could have caught earlier. A Phase 3 / Phase 4 that included a `Sources/SwiftIdempotencyExample/` target built inside the package (not a separate repo) would have surfaced Finding 1, Finding 3, and Finding 4 during development rather than at validation time. Future macro work should ship with a consumer target from day one.
- **Looking up Swift peer-macro conventions more carefully.** Findings 2 and 3 are documented Swift constraints (SE-0389 and the compiler's import rejection) that exist in the macro-design literature. The trial re-derived them empirically. A design-phase read of those documents would have avoided the round-trip.
- **Swift Testing's macro-inside-macro behaviour documented.** Finding 4 appears to be a lesser-known interaction; no Swift Evolution doc I read captured it. Worth filing upstream as a clarification request.

## Cost summary

- **Estimated:** 1 week. (The plan's original Phase 7 estimate.)
- **Actual:** ~2 hours of model time. Matches the "mechanism validation, not corpus measurement" framing — no large codebase to scan, just iteration on a small sample with fast feedback cycles.
- **Biggest time sink:** Finding 4's root-cause chase. Three iterations of macro-declaration shape changes (prefixed → arbitrary → prefixed → arbitrary) before landing on "can't ship peer-test-generation via this design." About 30 minutes of that 2 hours.

## Net output after seven rounds

- **Six prior rounds** measured rule behaviour on real corpora (pointfreeco, swift-aws-lambda-runtime, Hummingbird, swift-aws-lambda-runtime again). Confirmed the rule set's precision profile.
- **Round 7** measured mechanism integration on a purpose-built sample. Confirmed three of four shipped mechanisms work end-to-end; one requires redesign.
- **Cumulative artefact count across rounds:** 7 trial-scope.md files, 7 trial-findings.md files, 7 trial-retrospective.md files, 4 post-fix-verification/related docs, 5 implementation-plan files, 4 deferred-idea files. Traceable chain from "design proposal" to "measured evidence across two packages + four corpora."

The proposal's Phase 5 section is now accurate: macros shipped in the "first slice" sense, with one mechanism deferred and three live. Any future work on the peer-macro design can reference Finding 4 as the known blocker.

## Policy notes

- **"Fixing in-trial is within scope"** is a new pattern for round 7 that didn't apply to rounds 1-6. The earlier rounds measured stable mechanisms; round 7 measured a fresh distribution surface where discoveries couldn't always wait for a follow-up. The pattern produced a cleaner record than deferring would have, and the scope doc's explicit permission prevented mid-trial anxiety about whether to patch or document.
- **Sample packages are useful validation artefacts** even when they don't ship as user-facing examples. The round-7 sample at `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/` is local-only but remains available for follow-up work on Finding 4 if/when that redesign happens.
- **The "four frictions surfaced" framing is a feature of the round, not a bug.** Had the trial returned "everything works cleanly," the macros package would be shipped with unknown adopter-facing rough edges. The frictions are now named and either fixed or documented.

## Recommended path after round 7

Three directions, ordered by evidence-per-day:

1. **Peer-macro redesign addressing Finding 4.** Investigate `@attached(member)` or `@attached(extension)` roles that might sidestep Swift Testing's internal-member issue. Alternatively, design a two-macro split: `@Idempotent` (marker only) + `@IdempotentTestable` (generates peer test) — users opt into generation explicitly, and the peer could use a different scaffold that doesn't hit the `@Test`-in-peer-expansion fragility. 2-3 days of spike work.

2. **`strict_replayable` context tier.** The discussed opt-in strictness mode. Pair well with the macros package now that attribute annotations exist: `@lint.context strict_replayable` flags unannotated callees, but with `@Idempotent`/`@Observational` as cheap annotations, the adoption cost is low. Separate plan, ~3-5 days.

3. **Third-corpus validation.** A vapor app, an internal microservice, or the user's own codebase. Measures adoption friction end-to-end with both packages as real dependencies. The round-1-to-round-6 rhythm extended to round 8. Cost depends on corpus size.

My pick: **(1) first, then (2).** The peer-macro redesign closes the one outstanding round-7 finding cleanly; strict-mode is a feature addition that benefits from the closed finding. A third corpus is valuable but produces mostly duplicate evidence until there's something new to measure.

If forced to ship now without further iteration, the macros package is usable as-is: three of four mechanisms work and the fourth (`@Idempotent` peer-test) is both unit-tested and clearly documented as not production-ready. That's a defensible shipping state — not a "hide the gap" state, because the documentation is honest about the limitation.

## Data committed

- Sample package at `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/` — local-only, not pushed
- Macros package post-R7 edits on `SwiftIdempotency` main (to be committed + pushed alongside this writeup)
- Linter untouched by R7 (no linter-side code changes needed; attribute-form recognition from commit `58d302d` held under load)
- Proposal Phase 5 section already reflects the shipped state; no further edits needed post-R7

No new rule changes, no new linter diagnostics, no new annotation grammar. Round 7 is a mechanism-validation round — its output is findings, not features.
