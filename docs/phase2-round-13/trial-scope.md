# Round 13 Trial Scope

**First adopter-application validation.** Round 12's retrospective named "find an adopter application" as the qualitatively next step — framework code (rounds 6, 9-12) is informative but doesn't measure cost-to-adopt at the level a real user-facing app does.

ChatGPT-curated target list (`swift_idempotency_targets.md`) identifies `hummingbird-project/hummingbird-examples` as the high-value adopter-app candidate: small enough to annotate fully, real-world patterns (auth, ORMs, async jobs).

## Research question

> "When a real Hummingbird adopter application's controllers and job handlers are annotated `@lint.context replayable` — and then promoted to `strict_replayable` — what does the rule suite catch, what does it miss, and which adopter-side or linter-side gaps does the trial surface?"

## Pinned context

- **Linter:** `main` at `e3a78b3` (post-PR-9 framework whitelist).
- **Target:** `hummingbird-project/hummingbird-examples` shallow-cloned at `/Users/joecursio/xcode_projects/hummingbird-examples`. Three sub-packages annotated:
  1. `auth-jwt/` — JWT auth example with `UserController`
  2. `todos-fluent/` — ORM CRUD with `TodoController`
  3. `jobs/` — async job queue with `JobController` + `FakeEmailService`

Each example is its own Swift package; the linter scans them one at a time.

## Annotation plan

6 handlers, all `@lint.context replayable` (then promoted to `strict_replayable` for Run C):

1. `UserController.create` (auth-jwt) — POST user, calls `User.query`, `user.save`
2. `UserController.login` (auth-jwt) — POST login, calls `Date(timeIntervalSinceNow:)`, `JWT.sign`
3. `TodoController.list` (todos-fluent) — GET all (pure read, expected silent)
4. `TodoController.create` (todos-fluent) — POST, calls `todo.save`, `todo.update` (canonical non-idempotent)
5. `TodoController.deleteId` (todos-fluent) — DELETE, calls `todo.delete`
6. `JobController` queue.registerJob trailing closure (jobs) — calls `emailService.sendEmail` (exercises PR #7)

## Scope commitment

- **Measurement only.** No linter changes this round.
- **Two scans per package: replayable + strict_replayable.** The two-tier comparison is the headline.
- **Per-diagnostic decomposition with adoption-fix verdicts.** For each diagnostic, name what the adopter would do to silence it: "annotate the callee," "add to framework whitelist," "accept as defensible catch."

## Pre-committed questions for the retrospective

1. What yield does the replayable rule produce on real adopter handlers?
2. What does strict_replayable surface that replayable doesn't?
3. Which heuristic / whitelist gaps does the corpus name (similar to round 11's `stop`/`destroy`, round 12's metric primitives)?
4. Does the FakeEmailService body-mask phenomenon (mock services in adopter code masking real-prod-non-idempotent intent via upward inference) surface anywhere?
