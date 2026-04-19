# hummingbird-examples / todos-fluent — Trial Scope

First road-test after the framework-aware Fluent verb slice shipped in
`SwiftProjectLint` PR #11 and the `imports: nil` backward-compat
removal shipped in PR #12. The primary question this round answers:
does the Fluent gate actually fire on adopter code as designed?

## Research question

> "On a real Hummingbird adopter application with `import FluentKit`,
> does `@lint.context replayable` on controller handlers now produce
> catches on the canonical `todo.save` / `todo.update` / `todo.delete`
> pattern? And does `strict_replayable` decompose cleanly into
> Fluent-verb catches plus a named, bounded set of adoption gaps?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `e67f885`
  (post-PR-12 tip; includes PR #11's Fluent verb gate).
- **Target:** `hummingbird-project/hummingbird-examples`, tip `0d0f9bd`
  on `main`. Local clone `/Users/joecursio/xcode_projects/hummingbird-examples`.
- **Trial branch:** `trial-fluent-verify` forked from tip. Local-only,
  not pushed.
- **Scanned sub-package:** `todos-fluent/` — the `@lint.context`
  annotation target set is confined to `TodoController`.

## Annotation plan

Three handlers on `TodoController`, scanned twice:

1. `list(_:context:)` — pure read (`Todo.query(...).all()`). Expected
   silent in replayable mode; expected to surface query primitives as
   unannotated in strict mode.
2. `create(_:context:)` — calls `todo.save(on:)` + `todo.update(on:)`.
   Canonical adopter non-idempotent shape.
3. `deleteId(_:context:)` — calls `todo.delete(on:)`. Canonical Fluent
   delete shape.

**Run A — replayable:** all three handlers carry `/// @lint.context
replayable`. Expected diagnostic shape: Fluent-verb catches only
(3 catches: save/update on `create`, delete on `deleteId`; `list` is
silent by correctness).

**Run B — strict_replayable:** same handlers, context promoted to
`strict_replayable`. Expected shape: Run A's 3 catches plus
`UnannotatedInStrictReplayableContextVisitor` diagnostics on every
non-annotated callee in the call graph (query builder primitives,
Hummingbird error constructors, etc.).

## Scope commitment

- **Measurement only.** No linter changes this round.
- **Annotation-only source edits** to the target — three doc-comment
  lines added, one pass of `sed` between Run A and Run B to flip the
  tier. No logic changes.
- **Throwaway branch, not pushed.** Matches prior-round policy.
- **Single sub-package.** `auth-jwt/` and `jobs/` are out of scope for
  this round; the Fluent slice validation is todos-fluent-specific.

## Pre-committed questions for the retrospective

1. Did the Run A yield match the prediction (3 catches / 3 handlers,
   with `list` silent by correctness)?
2. Did the diagnostic prose correctly credit the Fluent framework
   gate ("from the FluentKit ORM verb `save`") rather than crediting
   the bare-name heuristic?
3. What's the strict-mode decomposition — Fluent-verb catches vs.
   genuinely unannotated surface?
4. Which of the strict-mode "unannotated" diagnostics point at
   adoption gaps worth a future slice (e.g. Fluent query-builder
   whitelist, `.init(...)` member-access form)?
