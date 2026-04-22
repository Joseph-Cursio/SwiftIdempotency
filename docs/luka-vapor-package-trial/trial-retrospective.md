# luka-vapor — Package Integration Trial Retrospective

## Did the scope hold?

Yes. One handler migrated (`start-live-activity`), one test added
with multiple `@Test` functions covering distinct API surfaces,
one linter parity check. No handler other than the target got
touched. No PR filed upstream.

One scope-adjacent decision made mid-trial: I stubbed the
Option C pathology with a local `actor Counter` rather than
wiring a real Redis backend. The substitution preserves the
essential property being tested (side effect invisible to the
return value), is faster to run in CI-unfriendly environments,
and documents the shape without requiring Redis infrastructure.
Alternative would have been a VaporTesting harness with a live
Redis — more authentic but out of scope for a first trial.

## What would have changed the outcome

- **If the handler had returned a model type** (like HelloVapor's
  `Acronym.save → Acronym`), Option C would likely have caught
  the non-idempotency via model-equality mismatch. The
  `HTTPStatus`-returning shape is the worst case; a typed-model-
  returning shape is the best case. The pathology is therefore
  handler-return-type-dependent, which matters for the README
  framing.
- **If `IdempotencyKey` had a non-Identifiable-requiring
  constructor already**, the migration diff would be cleaner and
  the "audit hatch is primary" finding wouldn't surface. That
  would arguably be a worse outcome — we'd have missed real
  signal about the API's shape.
- **If I had tried to file a PR to the upstream**, the scope would
  have ballooned: upstream maintainer wouldn't accept the
  restructuring without discussion, and the linter trial and
  package trial would conflate into one PR review. Keeping the
  trial on a fork-only branch was the right call.

## Recommendations for the package API

Prioritized by blocker status for v0.1.0 → SPI submission:

### Blocker (P0)

1. **README section on Option C's side-effect blindness.** The
   current README acknowledges Option C is only as sharp as
   `Equatable`, but the framing suggests the issue is encoding
   nondeterminism (JSON key ordering). The real pathology is
   broader: **any side effect invisible to the return value is
   invisible to `#assertIdempotent`.** The trivial `HTTPStatus.ok`
   return is the worst case; CRUD-handler `→ .ok` / `→ Void` /
   `→ .created` returns are extremely common in real Vapor /
   Hummingbird adopters. Without this callout, v0.1.0 ships a
   test-time guarantee claim that real adopters will misread.

### Significant (P1)

2. **README section on the inline-closure → named-func refactor
   cost.** Current docs don't mention that `@ExternallyIdempotent(by:)`
   can't attach to inline trailing closures. Most small Vapor /
   Hummingbird adopters use that handler shape. Adopters reading
   "just add the attribute" will hit a compilation error or
   realize mid-refactor that they need to extract handler bodies.
   Could be short — two paragraphs + one before/after snippet.

### Ergonomic (P2)

3. **Candidate new initializer for Codable-only types.** Name TBD:
   `IdempotencyKey(fromHashable:)` or
   `IdempotencyKey(fromEncoded:)`? Adopters whose natural idempotency-
   key source is a Codable struct (request bodies, external API
   response records, Stripe event payloads where you don't own
   the type) currently route through `init(fromAuditedString:)` —
   the audit hatch. Defer pending a second adopter trial to
   confirm the shape.

### Cosmetic (P3)

4. **Fix `SwiftIdempotencyTestSupport` reference in README.** The
   target is currently a placeholder; the runtime helpers for
   `#assertIdempotent` live in `SwiftIdempotency`. Either document
   the placeholder status or remove the installation reference
   until v0.x ships real test-only helpers.

### Post-release (not blocker)

5. **Promote Option B (dep-injected mock effects) from "deferred"
   to v0.1.1 planning.** Option B would catch the pathology that
   recommendation 1 documents around. Significant design effort
   — not blocking v0.1.0 — but worth naming as the trajectory.

## Cost summary

Estimated effort for this trial: one session. Actual: the trial
executed in ~45 minutes from fork branching to findings commit,
with the bulk going into:

- 10 min: build a working understanding of the upstream handler's
  existing shape (routes.swift + Models + existing test target).
- 10 min: migrate the handler and request model. Straightforward
  given the attribute-macro restriction I anticipated.
- 10 min: wire up tests. The actor-counter Option C pathology
  demonstration and the `IdempotencyKey` Codable round-trip were
  both small. Test fixture hiccup (`AccountLocation` rejecting
  `"us"` vs `"usa"`) cost ~2 min to diagnose.
- 5 min: cold-build timing + linter parity scan.
- ~10 min: doc writing.

**Faster than expected.** The plan budget was "one session"; this
used less than half.

## Policy notes for the plan

Two observations from this first trial that should fold back into
`package_adoption_test_plan.md`:

### Actor-counter substitution for side-effect demonstration

When a handler's real side effects live behind network/DB
infrastructure (Redis, Postgres, external APIs), using a local
`actor` with a mutable counter as a stand-in is both faster to
set up and cleaner as a demonstration. The essential property —
side effect invisible to the return value — is preserved. Add
this as an accepted technique to the plan's "Test plan" section.

### Linter parity is cheap and worth always including

Running SwiftProjectLint on the migrated branch took ~5 seconds
and produced concrete evidence that the attribute form matches
the doc-comment form. Every integration trial should include
this as a standard check; it's infrequently surprising but when
it is, the divergence is a bug worth finding.

## Data committed

- `docs/luka-vapor-package-trial/trial-scope.md`
- `docs/luka-vapor-package-trial/trial-findings.md`
- `docs/luka-vapor-package-trial/trial-retrospective.md`
- `docs/luka-vapor-package-trial/migration.diff`

Fork state (on `Joseph-Cursio/luka-vapor-idempotency-trial`):
- `package-integration-trial` branch at `d8bd8dc`. Tests green
  on the 5 trial tests.
- Default branch unchanged (`trial-luka-vapor` from the linter
  round is still the default — per trial policy, this branch is
  a sibling, not a replacement).
