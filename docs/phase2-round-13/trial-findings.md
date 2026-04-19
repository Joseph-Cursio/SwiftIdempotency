# Round 13 Trial Findings

First adopter-application validation. Three Hummingbird examples — `auth-jwt`, `todos-fluent`, `jobs` — each annotated and scanned twice (replayable, strict_replayable).

## Diagnostic count per run

| Run | State | auth-jwt | todos-fluent | jobs | Total |
|---|---|---|---|---|---|
| A | bare baselines (per package) | 0 | 0 | 0 | 0 |
| B | 6 `@lint.context replayable` annotations | **0** | **0** | **0** | **0** |
| C | promoted to `@lint.context strict_replayable` | 17 | 17 | 0 | 34 |

## Run B — replayable yield is **zero on adopter Hummingbird code**

Six annotations across three real Hummingbird example apps. **Zero diagnostics.** This is the first round where annotations on a real-app corpus produced no catches. Two distinct root causes, each a meaningful finding:

### Finding 1 — Fluent ORM verb gap (`save`, `update`, `delete`)

**Affected:** `TodoController.create` and `.deleteId`, `UserController.create`. All three use Fluent's instance-method API:

```swift
try await todo.save(on: db)
try await todo.update(on: db)
try await todo.delete(on: db)
try await user.save(on: db)
```

`save`, `update`, `delete` aren't in `HeuristicEffectInferrer.nonIdempotentNames`. The verbs are unambiguously destructive in an ORM context — `save` creates/updates rows, `update` mutates, `delete` removes. Adding them to the heuristic whitelist would catch the entire class of Fluent CRUD violations the linter exists to catch.

**Adoption impact:** the canonical "POST creates duplicate row on retry" bug — exactly what the rule suite is designed to surface — does NOT fire on the most common Swift web ORM. This is the single highest-priority follow-on the round identifies.

**Fix shape:** 3-line change to `nonIdempotentNames` (add `save`, `update`, `delete`), plus 6-9 unit tests. ~30 min slice. Same shape as PR #8 (`stop`/`destroy`).

### Finding 2 — Mock/fake-service body masks name-based intent

**Affected:** `JobController` trailing closure → `emailService.sendEmail(...)`.

`emailService` is `FakeEmailService` (in-project, defined a sibling file away). Its body:

```swift
func sendEmail(to: [String], from: String, ...) async throws {
    self.logger.info("To: ...")
    self.logger.info("From: ...")
    self.logger.info("Subject: ...")
    self.logger.info("\(message)")
}
```

The upward inferrer walks this body, computes the lub of its callees (all `logger.info` → observational), and classifies `sendEmail` as `.observational`. The heuristic-name path would have classified the same call as `.nonIdempotent` (via the `send` prefix), but **declared/upward inference has higher precedence than heuristic** — by design.

The local reasoning is correct: this specific `sendEmail` body is observational. But adopters using mock/fake services in dev environments may get **false negatives in dev that disappear in prod** when the real service replaces the mock.

**Adoption impact:** documenting the precedence is a documentation slice, not a code change. Possible mitigations:
- An `@lint.assume sendEmail is non_idempotent` annotation that overrides upward inference (the proposal already discusses `@lint.assume` syntax)
- A linter mode that suppresses upward inference for un-annotated functions (probably too aggressive)

This is the more interesting structural finding — not a gap in the rules, but a finding about how body-based inference interacts with adopter codebases that contain test doubles.

## Run C — strict_replayable surfaces 34 catches across three packages

| Package | Strict diagnostics | Decomposition |
|---|---|---|
| auth-jwt | 17 | Fluent ORM (5), framework type-constructor `.init(...)` form (5), `Date(timeIntervalSinceNow:)` (1), `request.decode` (1), JWT primitives (5) |
| todos-fluent | 17 | Fluent ORM (8), framework type-constructor `.init(...)` form (5), `request.decode` (1), `context.parameters.require` (1), `db` accessor (2) |
| jobs | 0 | The closure body's only call is `emailService.sendEmail`, which (per Finding 2) is upward-inferred as observational and defers from strict mode |

### What strict_replayable found that replayable didn't

All 34 diagnostics are **callees the replayable rule stays silent on** (because the replayable rule only fires on declared/inferred non_idempotent). Strict mode's "flag unless proven idempotent" surfaces them.

Decomposition by class:

| Class | Count | Adoption fix |
|---|---|---|
| Fluent ORM methods (`query`, `filter`, `first`, `save`, `update`, `delete`, `db()`) | 13 | **Framework whitelist extension** to cover Fluent. `query`/`filter`/`first` are pure reads (idempotent); `save`/`update`/`delete` are mutations (non-idempotent — also closes Finding 1). |
| Framework type constructors via `.init(...)` form | 10 | **Whitelist extension**: PR #9 captured bare-identifier constructors (`JSONDecoder()`) but not member-access form (`HTTPError(.notFound)` parses as `.init(...)`). |
| Hummingbird/JWT primitives (`HTTPError`, `JWTPayloadData`, `JWTKeyCollection.sign`, `requireID`, `request.decode`, `context.parameters.require`) | 9 | Per-callee adopter annotation, OR Hummingbird-specific framework whitelist. |
| `Date(timeIntervalSinceNow:)` | 1 | **Defensible catch.** Date reads current time → not idempotent. JWT expiration ≠ deterministic across replays. Adopter would annotate `@lint.unsafe reason: "expiration drift acceptable"`. |
| `request.decode` | 1 (×2 actually) | Could be added to codec whitelist with an extended receiver-name pattern. |

### `jobs` strict-mode silence

The trailing closure has only one call (`emailService.sendEmail`), and that call is upward-inferred observational. So strict mode adds nothing — the existing classification suffices. **The same finding as Run B.**

If `FakeEmailService` were replaced with a real service whose body actually sent email (mutating external state), strict mode would still silence it unless the real body's upward inference produced a non-idempotent result — and given Vapor/Hummingbird-style "delegate to async client" implementations, even real services often have bodies the inferrer classifies favorably. This is an adoption-time consideration: services-with-bodies-the-inferrer-trusts may need explicit annotation to express intent.

## Cross-corpus yield comparison (now five corpora)

| Corpus | Annotations | Replayable catches | Yield | Strict catches | Strict delta |
|---|---|---|---|---|---|
| pointfreeco | 5 | 4 | 0.80 | n/a | n/a |
| Hummingbird (framework) | 5 | 4 | 0.80 | n/a | n/a |
| Vapor (demo routes) | 6 | 2 | 0.33 | 1 (round 10) | n/a |
| Lambda (compute/return) | 9 | 0 | 0.00 | 4 (post-PR-9) | n/a |
| **hummingbird-examples (adopter app)** | **6** | **0** | **0.00** | **34** | **+34** |

### What this teaches

The first four corpora measured **framework code** — code WRITTEN by framework authors who understand idempotency well and structure callsites accordingly. Yield 0.00-0.80, generally low strict-mode delta.

The fifth corpus measures **application code** — code that ADOPTS the frameworks. It has the opposite shape:
- Replayable yield is 0.00 because the heuristic doesn't recognise the ORM verbs the application uses
- Strict mode surfaces 34 callees the application would need to classify

**This is the real adoption-cost data point the project has been missing.** Twelve rounds of framework-code yield numbers said "the rules work as designed." The first adopter-app round says: "the rules don't catch what they should on real adopter code without two specific extensions" (Fluent verbs + Hummingbird primitives), "and strict mode requires an extensive per-callee classification effort the adopter must do."

## Per-handler audit (replayable mode)

| # | Handler | Result | Verdict |
|---|---|---|---|
| 1 | `UserController.create` (auth-jwt) | silent | **gap** (Fluent `save`) |
| 2 | `UserController.login` (auth-jwt) | silent | **defensible silence** (`Date()` and `sign()` aren't classified by replayable) |
| 3 | `TodoController.list` (todos-fluent) | silent | **silent-by-correctness** (pure read; only calls `Todo.query(...).all()`) |
| 4 | `TodoController.create` (todos-fluent) | silent | **gap** (Fluent `save`/`update`) |
| 5 | `TodoController.deleteId` (todos-fluent) | silent | **gap** (Fluent `delete`) |
| 6 | `JobController` closure (jobs) | silent | **inference-precedence finding** (Finding 2) |

## Answer to the four sub-questions

### (a) Yield on real adopter handlers?

**0.00 catches/annotation.** First time a corpus has produced this. Driven by the Fluent ORM heuristic gap, not by handler-shape. Adopters using Fluent see no catches because their write-path methods aren't in the heuristic.

### (b) Strict surface beyond replayable?

**34 catches across 6 handlers.** Decomposition is dominated by Fluent ORM (13), `.init(...)` constructor form (10), and Hummingbird/JWT primitives (9). Each class has a clear adoption-fix path.

### (c) Heuristic / whitelist gaps?

**Three high-priority gaps:**
1. Fluent ORM verbs `save`/`update`/`delete` → `nonIdempotentNames` (3-line code change)
2. Fluent ORM read verbs `query`/`filter`/`first` → idempotent receiver-pattern (modest code change)
3. `.init(...)` constructor form → idempotent type whitelist must check both bare-identifier AND member-access shapes

### (d) Mock/fake-service body-masking phenomenon?

**Yes — surfaced cleanly in `JobController`/`FakeEmailService`.** Documented as Finding 2. Not a bug; the precedence is by design. But it's a real adoption consideration the proposal should call out as part of the "what does this rule catch and not catch" docs.

## Data committed

Under `docs/phase2-round-13/`:

- `trial-scope.md` — this trial's contract
- `trial-findings.md` — this document
- `trial-retrospective.md` — next-step thinking
- `trial-transcripts/run-A.txt` — bare hummingbird-examples (root, 0 diagnostics)
- `trial-transcripts/run-B.txt` — (run via for-loop; 0 diagnostics across all three)
- `trial-transcripts/run-C.txt` — strict counts (17/17/0)

hummingbird-examples annotations applied in-place; can be reverted via `git checkout` per directory. Linter untouched.
