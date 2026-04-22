# Package Adoption Test Plan

How to run a substantial integration test of the `SwiftIdempotency` package against a real adopter, what the gap is that this plan closes, and how to read the output.

## Purpose

The linter's [`road_test_plan.md`](road_test_plan.md) rounds exercise the linter on adopter code via a single doc-comment annotation — measurement-only. They do not validate the macro surface from `SwiftIdempotency`: no adopter has actually imported the package, migrated a real handler to use `IdempotencyKey`, added `@ExternallyIdempotent(by:)` to a real call site, or written `#assertIdempotent` in their own test suite.

The package's "10-for-10 real-bug shape coverage" claim is **structural** — each real bug fits the shape the macro surface could express. It is not validated adoption. This plan closes that gap via a distinct trial protocol where an adopter's code actually takes a dependency on the package.

## When to run a trial

- Before a release (v0.1.0 minimum). Specifically gating Swift Package Index submission: the package needs validation that the three tiers' APIs work on at least one real adopter, not just three hand-authored examples.
- After a macro-surface API change (new initializer on `IdempotencyKey`, parameterised `@IdempotencyTests` expansion, async `#assertIdempotent`) that hasn't been validated beyond unit tests.
- When an adopter has surfaced a real bug that the macro surface *should* be able to express, to check whether the fix actually compiles and the test actually catches it.

Not needed for linter slices (that's `road_test_plan.md`'s job) or for package internals that have no external-facing surface.

## Per-trial protocol

### Pick target + feature combination

- **One adopter per trial.** Hybrid-adopter trials dilute the signal.
- Prefer adopters where a **linter road-test has already been done** — the fork, trial branch, and domain knowledge are already in place.
- Match adopter shape to the feature under test:
  - `IdempotencyKey` construction & call-site threading → webhook/payment/notification handlers where a caller-supplied key is structurally natural.
  - `@ExternallyIdempotent(by:)` → a handler whose function signature already has (or trivially can have) a named parameter that serves as the dedup key.
  - `#assertIdempotent` Option C → a handler with a **non-trivial return type** (not `HTTPStatus.ok`-only — those can't exercise the Option C comparison meaningfully).
  - `@IdempotencyTests` → a type with actual zero-argument idempotent helpers. Real adopter code rarely has these, so this feature may need a synthetic target instead.

### Migration

Unlike linter road-tests, this trial **modifies adopter source code**. The migration is the deliverable:

1. Add `SwiftIdempotency` as a package dependency in the fork.
2. Migrate one handler (not the whole app) to use the macro surface:
   - Change parameter types to `IdempotencyKey` where appropriate.
   - Add `@ExternallyIdempotent(by:)` on the `func` decl.
   - Refactor any caller shape that doesn't fit (e.g. dotted-path parameters, non-Identifiable source types, inline trailing-closure handlers that need a named-func refactor).
3. Add one `#assertIdempotent { ... }` test in the adopter's existing test target.
4. Record every single frictions point as you hit it — even trivial ones (`couldn't find initializer`, `compiler suggested X`, `Xcode showed a confusing diagnostic`).

### Integration scope

- **One handler, one test.** Don't migrate the entire app. The goal is to surface the API's ergonomics, not to rewrite the codebase.
- Keep the changes on a **new `trial-<slug>-package` branch** (or similar). Do not overwrite the linter's `trial-<slug>` branch — that carries separate artifacts referenced in the linter findings docs.
- The fork hardening banner (for a contribution fork) does not apply here — these changes are deliberately non-contribution; the fork's dual-use is already established.

### Measurement

Capture:

- **Compilation transcript.** Did the changes compile on first attempt? What errors/warnings did you hit? How many attempts before it built?
- **Test outcome.** Does `swift test` pass? Does `#assertIdempotent` actually detect the non-idempotency (if one exists)? Is Option C sharp enough on this return type?
- **Build-time delta.** `time swift build -c release` before vs. after adding the package. Record both clean-build and incremental-build deltas on a small change.
- **API frictions.** Every time the adopter code had to be refactored to fit the API, name the shape mismatch. Every initializer that didn't exist. Every compiler error the adopter would need to understand.
- **Linter parity check.** Run SwiftProjectLint with the attribute-form annotations on the migrated handler. Compare diagnostic output to the doc-comment-annotated version. Record any divergence.

## Documents to produce

Four files under `docs/<adopter>-package-trial/`:

### `trial-scope.md`

- Research question (which macro-surface features, on which adopter shape).
- Pinned context (SwiftIdempotency tip SHA, SwiftProjectLint tip SHA, adopter upstream SHA, fork branch).
- Migration plan (which handler, which tier, expected refactor scope).
- Pre-committed questions (3-4).

### `trial-findings.md`

- Compilation log (attempts, errors, resolutions).
- Test outcome (passed / failed / Option C false-negative).
- Build-time delta.
- API friction log.
- Linter parity result.
- Answers to pre-committed questions.

### `trial-retrospective.md`

- Did the scope hold?
- What would have changed the outcome (counterfactuals).
- Recommendations for the package API (list of concrete changes, prioritized).
- Policy notes for this plan.

### `migration.diff`

The actual diff of adopter-code changes, preserved verbatim.

## Proposed first-trial targets

Three candidates, ranked by value-per-effort:

1. **`kylebshr/luka-vapor`** — smallest adopter (3 handlers, ~150 LOC). Real side effects (Redis `hset` / `zadd` + APNS push). `start-live-activity` and `end-live-activity` POST handlers are natural targets for `@ExternallyIdempotent(by: "idempotencyKey")`. **Weakness:** both handlers return `HTTPStatus.ok`, which exercises the Option C return-equality pathology we flagged — a feature, not a bug, for testing the pathology itself.

2. **`sinduke/HelloVapor`** — slightly larger (multiple controllers + Fluent). The `app.post("api", "acronym")` handler **returns the `Acronym` model with synthesised `Equatable`** — a more realistic Option C test target than a bare `HTTPStatus`. Clean Fluent dep shape; SQLite-driver makes test isolation tractable.

3. **Fresh synthetic target** — build a small from-scratch adopter (~5 handlers) specifically to exercise the full macro surface. Advantages: control over every ergonomics question (non-Identifiable entity types, async handlers, complex `Equatable` returns). Disadvantages: zero external-adoption signal; we're testing our own code against our own API.

Recommend **luka-vapor first** because the Option C pathology is *the* deferred question, and luka-vapor is structurally designed to surface it. HelloVapor follows as the "does Option C work on a sanely-typed return?" test.

## Completion criteria

Package-side trials should continue until:

1. **Three adopter integrations complete**, each with a distinct shape (async vs sync, trivial vs non-trivial return, Identifiable vs non-Identifiable entity source).
2. **No new P0 API-change requirements surface from an integration.** "P0" meaning the API couldn't express the adopter's case at all, not "we'd prefer a helper method."
3. **Linter parity confirmed** on at least one attribute-form-annotated handler.

Pre-release (v0.1.0 → SPI submission), **one integration** is enough to invalidate the "only tested via self-authored examples" critique. Criterion 1's three-trial bar is post-release validation work that can proceed in parallel with real adoption.

## What this plan is not

- Not a performance benchmark. Build-time measurement is binary (acceptable vs. makes the adopter's CI time 10× worse), not a calibrated microbenchmark.
- Not a test-suite expansion. This plan runs integration trials, it doesn't add new unit tests to the package itself. Internal macro expansion tests remain the unit-test target.
- Not an adopter-engagement activity. The integration is on a fork; no PR is filed to the adopter. The adopter isn't informed. The point is validating our API, not the adopter's adoption readiness.
