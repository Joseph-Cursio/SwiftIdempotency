# Graphiti — Trial Retrospective

## Did the scope hold?

Yes — measurement-only, doc-comment annotations only, no logic
edits, audit cap not exceeded (5 strict-mode fires << 30).
Cleanest round protocol-wise to date — no mid-round deviations,
no policy questions surfaced. ~20 minutes wall clock from "fork
created" to "findings doc written."

## Pre-committed questions

### 1. DSL-binding triggers slot 3 receiver resolution?

**No — slot 3 was not triggered.** This is the round's most
substantive finding, structured as negative evidence: the
GraphQL DSL pattern `Field("hero", at: StarWarsResolver.hero)`
(passing an unbound static-method reference to the schema
builder) does not interfere with the linter's body-inference
walk on the annotated resolver method.

The mechanism: annotations attach to the resolver `func` decl
in `StarWarsResolver.swift`. The schema builder's
`Field("...", at: ...)` calls live in `StarWarsAPI.swift`
inside DSL closures, and the linter doesn't try to associate
"this method is a GraphQL field resolver" with "this method
should be analyzed under @lint.context replayable" — it just
walks any method that has a `@lint.context` annotation directly,
regardless of how the schema-side binding was set up. That
turns out to be the right behavior: the schema-author's
contract (which method binds to which field) is invisible to
the code-flow analyzer, and the analyzer doesn't need it.

**Slot 3 still requires same-name method collisions across
types with differing tiers**, not present in this corpus
(StarWarsResolver and Human/Droid extensions each declare
distinct method names — `hero`, `human`, `search`, `getFriends`,
`getSecretBackstory`). The trigger condition for slot 3
remains an annotated-corpus round where two different types
each declare a signature with the same `name(labels:)` and
different effects.

### 2. Throwing-only resolver fires correctly?

**Yes.** `Human.getSecretBackstory(context:arguments:)` —
body is `try context.getSecretBackStory()` (which always
throws) — stayed silent in replayable mode and fired exactly
once in strict mode (same cluster as the other four
resolvers). The body-inference path treats `try X()` calls
identically to `X()` calls for effect inference; the throwing-
ness doesn't perturb the analysis. Replayable tolerates the
unknown effect of `getSecretBackStory`; strict requires
declaration.

This is the right behavior — replayed throws are observably
identical to first throws (a thrown error is a value, idempotent
in observability terms). Annotating `StarWarsContext.getSecretBackStory`
with `/// @lint.effect idempotent` would silence strict mode.

### 3. Pure-resolver silence in replayable?

**Yes — 5/5 silent.** All five resolvers delegate to
`StarWarsContext` lookups against `private static let` data
(`humanData`, `droidData`, `planetData`). Pure dictionary
lookups, sorted/filtered/mapped chains over those, and the
always-throws case. Linter correctly does not flag any.

### 4. Strict-mode cluster size?

**Exactly 5 — single cluster.** Hypothesis confirmed. Each
resolver fires exactly once on its delegated context-method
call (`hero` → `getHero`, `human` → `getHuman`, `search` →
`search`, `Human.getFriends` → `getFriends`, `Human.getSecretBackstory`
→ `getSecretBackStory`). No spurious fires, no missed fires,
no second-cluster pattern.

## Counterfactuals

What would have changed the outcome:

- **If the StarWarsContext methods had been annotated.** Adding
  `/// @lint.effect idempotent` to all 8 context methods
  (each one trivially pure) would silence the strict-mode
  cluster entirely. This would produce a **fully clean strict
  scan** — the first round to achieve zero strict fires on
  an annotated handler set. Not done in this round (scope was
  measurement-only on the resolver layer); worth noting that
  Graphiti's design encourages this annotation pattern more
  cleanly than HTTP frameworks (the resolver/context split
  is one-to-one with the orchestration/effect split).

- **If droid + Droid resolvers had been included.** Three more
  resolvers, all isomorphic to Human's. Run A would still be
  5+3 = 8/8 silent. Run B would extend the cluster to 8 fires,
  same shape. No new evidence; correct decision to skip.

- **If `Character.secretBackstory` (computed property) had been
  included.** `var secretBackstory: String? { nil }` bound via
  `Field("secretBackstory", at: \.secretBackstory)` KeyPath. The
  KeyPath binding is structurally distinct from the method-
  reference binding measured here, and `@lint.context` on a
  computed property is a different-shaped annotation site (the
  property doesn't have a body the way a func does — only a
  getter). Worth measuring in a future round if KeyPath-binding
  evidence is needed; deferred from this round to keep scope
  tight.

- **If a real Graphiti production consumer had been available.**
  Search came up empty for non-trivial Graphiti consumers. A
  production GraphQL server would have real context-method
  bodies (database calls, gRPC fan-outs, etc.), and the strict-
  mode cluster would extend into "real" non-idempotent shapes
  (insert-style lookups, etc.). Round was correctly framed as
  infrastructure smoke test rather than FP-rate validation.

## Cost summary

- **Estimated:** ~20 minutes (smaller annotation surface than
  grpc-swift-2 — single package, one resolver file, no nested
  Examples to enumerate).
- **Actual:** ~20 minutes wall clock from "fork created" to
  "findings doc written." No iteration on linter green-tip
  (already verified earlier this session). Scans were instant.

## Policy notes

Nothing for `road_test_plan.md`. The round demonstrated the
existing template handles GraphQL DSL-bound resolvers with no
shape changes — same recipe as method-reference handlers in
HTTP frameworks. No new pattern to fold back.

One observation worth recording elsewhere (in `next_steps.md`'s
1-adopter list, alongside the SwiftProtobuf entry from
grpc-swift-2): **Graphiti DSL field-binding pattern is
verified compatible with the existing inference path**. If a
future round on a Graphiti production adopter needs receiver
resolution improvements, slot 3 would handle it — and the
trigger condition there is method-name collision across
multiple types, not the DSL pattern itself.

## Data committed

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md`
- `trial-transcripts/replayable.txt`
- `trial-transcripts/strict-replayable.txt`

Trial fork (authoritative): `Joseph-Cursio/graphiti-idempotency-trial`
on branch `trial-graphiti`. Final state restored to
`@lint.context replayable` (the strict variant was committed
mid-round at `6f29cce`, then reverted at `adc3f08` so the
authoritative branch tip carries the documented Run A state).
