# hummingbird-examples / todos-fluent — Trial Retrospective

First adopter-corpus road-test under the new project-named docs
scheme. Short retrospective; the primary question had a clean yes.

## Did the scope hold?

**Yes.** One throwaway branch, three annotations, two scans, no
linter edits, no scope creep into `auth-jwt` or `jobs`. The scope
doc predicted "3 catches / 3 handlers with `list` silent" for Run A
and "3 Fluent + N unannotated" for Run B — both predictions landed
within the scope commitment.

## Answers to the four pre-committed questions

### (a) Did Run A's yield match the prediction?

**Yes — exactly.** 3 catches on 3 annotated handlers, decomposed as:

- `list` — 0 diagnostics, silent by correctness (pure Fluent read)
- `create` — 2 diagnostics (`save` + `update`)
- `deleteId` — 1 diagnostic (`delete`)

Per-handler yield is 0/2/1; per-non-silent-handler yield is 1.50
(3 catches / 2 handlers that produce any). Compared to the pre-
slice baseline of 0.00 on the same handler set: the Fluent verb
gate is the load-bearing change.

### (b) Did the diagnostic prose correctly credit the Fluent gate?

**Yes.** Every Run A diagnostic carries `from the FluentKit ORM
verb \`<name>\`` — the inference-reason string wired in PR #11.
Users reading the diagnostic see exactly which heuristic fired
and why, and the `FluentKit` credit tells them immediately that
the fix (if wrong) is either a declared effect annotation or a
`.swiftprojectlint.yml` opt-out of the `FluentKit` whitelist.

### (c) What's the strict-mode decomposition?

3 Fluent catches (carried from Run A) + 14 unannotated-callee
catches = 17 total. Unannotated surface splits cleanly:

- **7 Fluent query-builder reads** (`db`, `query`, `all`, `first`,
  `filter`) — closable by a Fluent idempotent-read whitelist slice.
- **4 Hummingbird primitives** (`HTTPError`, `request.decode`,
  `parameters.require`) — closable by a Hummingbird framework
  whitelist slice.
- **1 `.init(...)` member-access form** — known PR-#9 gap, not
  closed by any framework whitelist until the type-constructor
  matcher learns member-access syntax.
- **1 adopter-owned `Todo()` constructor** — genuinely
  adopter-responsibility; the fix is `@Idempotent` on `Todo.init`.

### (d) Which adoption gaps are next-slice worthy?

Two named follow-ons fall out cleanly:

1. **Fluent query-builder idempotent-read whitelist** (~30 minutes).
   Extend `FrameworkWhitelist` with a Fluent-specific
   `idempotentMethodsByFramework` — `query`, `all`, `first`,
   `filter`, `db` gated on `import FluentKit`. Same shape as PR #11
   but for the read-only side of the API. Would silence ~7/14
   Run B diagnostics on this corpus.

2. **Hummingbird framework whitelist** (~1 hour). New framework
   entry covering error/decode/parameter-extraction primitives.
   Broader surface than Fluent (more adopters); worth measuring
   yield lift on a second Hummingbird adopter before generalising.

Deferred: `.init(...)` member-access form. It's a known gap and
firing rate here is 1/17. Low marginal value — wait for a round
where it surfaces across multiple adopters.

## What would have changed the outcome

- **Annotating the `update` controller method too.** `TodoController.update`
  has the same body shape as `create` (calls `todo.update(on:)`) and
  would have produced a fourth Fluent catch. The round-13 scope
  left it out; this round followed that precedent for comparability
  but the marginal cost was zero and the evidence would be stronger.
  Not changing the outcome of the primary question but would
  strengthen the yield number.

## Cost summary

- **Estimated:** 1 hour (per the follow-up plan from PR #11's PR body).
- **Actual:** ~25 minutes of model time end-to-end (branch, annotate,
  scan ×2, write up, commit).
- **Biggest time sink:** writing the strict-mode decomposition
  table — 14 diagnostics each needing a one-line adoption-fix verdict.
  Mechanical but necessary for the docs to answer question (d).

## Policy notes

- **Project-named docs directory works.** `docs/hummingbird-examples/`
  is self-describing; no phase number or round number needed. If a
  follow-up round happens after the Fluent query-builder slice lands,
  it overwrites this directory in place — git history is the audit
  trail.
- **The "doc-comment-only annotation campaign" shape is still the
  right default.** Macro-form (`@Idempotent` etc.) annotations
  would have required the adopter to depend on the `SwiftIdempotency`
  package — more invasive than a measurement round warrants. Defer
  the macro-form road-test to a purpose-built adopter OR to a round
  where the adopter has already consumed the package for their own
  reasons.

## Data committed

- `docs/hummingbird-examples/trial-scope.md`
- `docs/hummingbird-examples/trial-findings.md`
- `docs/hummingbird-examples/trial-retrospective.md` — this document
- `docs/hummingbird-examples/trial-transcripts/replayable.txt`
- `docs/hummingbird-examples/trial-transcripts/strict-replayable.txt`

Annotations on the `trial-fluent-verify` branch of
`hummingbird-examples` remain local-only. Revert with
`git checkout main -- todos-fluent/Sources/App/Controllers/TodoController.swift`.
