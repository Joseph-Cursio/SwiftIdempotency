# Graphiti — Trial Scope

Fifteenth adopter road-test. First GraphQL target; first measurement
of DSL-bound resolver shapes (`Field("name", at: TypeName.method)`
unbound static-method references) and type-extension resolver
overrides.

Picked under the post-2026-04-24 selection rule (domain/shape
novelty, not project obscurity). Same demo-corpus framing as
grpc-swift-2: GitHub search returned no real Graphiti production
consumers, so the round is an infrastructure smoke test on the
canonical StarWarsAPI demo (the GraphQL community's textbook
schema, analogous to gRPC's route-guide).

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On Graphiti's GraphQL schema-DSL binding pattern
> (`Field('hero', at: StarWarsResolver.hero)` — passing an unbound
> static-method reference to the schema builder), does
> `@lint.context replayable` placed on the resolver `func` decl
> walk correctly through the resolver body? Does the DSL-binding
> shape itself confuse receiver resolution (slot 3), or does the
> linter ignore the binding mechanics and walk the annotated
> method body as if it were a regular method-reference handler?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `0ca8a12`
  (post-PR #29 merge tip, 2026-04-25 — closure-binding cross-reference
  + multi-rule SwiftLint hygiene). 2397 tests green on a clean build.
  Same SHA as grpc-swift-2 round earlier this session.
- **Upstream target:** `GraphQLSwift/Graphiti` @ `20c8d02` on `main`
  (2026-04-06 push, 559 stars — the Swift GraphQL schema builder
  built on top of the `GraphQL` execution engine, both maintained
  by the GraphQLSwift org).
- **Fork:** `Joseph-Cursio/graphiti-idempotency-trial`, hardened
  per road-test recipe (issues/wiki/projects disabled, README banner,
  trial branch as default).
- **Trial branch:** `trial-graphiti`, forked from upstream `20c8d02`.
  Fork-authoritative — scans run against a fresh clone of the fork.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required.

## Annotation plan

Five resolver methods in `Tests/GraphitiTests/StarWarsAPI/StarWarsResolver.swift`,
chosen for shape diversity across the two GraphQL-typical resolver-
binding mechanisms:

| # | Site | Resolver | Binding shape |
|---|------|----------|---------------|
| 1 | `StarWarsResolver.swift:47` | `StarWarsResolver.hero(context:arguments:)` | **DSL-bound root resolver.** `Field("hero", at: StarWarsResolver.hero)` in the schema builder — unbound static-method reference passed to the DSL. |
| 2 | `StarWarsResolver.swift:56` | `StarWarsResolver.human(context:arguments:)` | Same DSL pattern — optional return (`Human?`). |
| 3 | `StarWarsResolver.swift:73` | `StarWarsResolver.search(context:arguments:)` | Same DSL pattern — array return (`[SearchResult]`), calls `context.search(query:)` which fans out across multiple lookups. |
| 4 | `StarWarsResolver.swift:15` | `Human.getFriends(context:arguments:)` (extension method) | **Type-extension resolver.** `Field("friends", at: Human.getFriends)` in the `Type(Human.self, …)` block — same unbound-method-reference pattern but on a type-extension method instead of the resolver root. |
| 5 | `StarWarsResolver.swift:20` | `Human.getSecretBackstory(context:arguments:)` (extension method, throws) | Same as #4, but `throws` — body is `try context.getSecretBackStory()` (which always throws). Tests whether throwing-only resolvers walk correctly. |

Deliberately excluded:

- `StarWarsResolver.droid` — same DSL-binding shape as #1/#2/#3, no
  new shape evidence. Skipped to keep the audit cap clean.
- `Droid.getFriends` / `Droid.getSecretBackstory` extensions —
  isomorphic to the `Human` versions (both resolve to identical
  `context.getFriends(of:)` / `context.getSecretBackStory()`
  calls). Skipping doesn't lose shape evidence.
- `Character.secretBackstory` (computed property `var ... { nil }`)
  — Graphiti binds this via `Field("secretBackstory", at: \.secretBackstory)`
  KeyPath, structurally distinct from the method-reference shape.
  Worth a separate measurement only if a future round needs
  KeyPath-binding evidence specifically; defer.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each resolver `func`. No logic
  edits, no imports, no new types.
- **Audit cap.** 30 diagnostics max per mode (template default).

## Pre-committed questions

1. **DSL-binding receiver-resolution.** Does `Field("hero", at:
   StarWarsResolver.hero)` confuse the linter's receiver
   resolution? Specifically: does the linter associate the
   annotation on `StarWarsResolver.hero` with the right method
   body, or does the unbound static-method-reference shape
   look like a closure to it and miss the body? **The answer
   determines whether GraphQL DSL binding triggers slot 3
   evidence (deferred receiver-type resolution work) or not.**

2. **Throwing-only resolver body inference.** Does handler #5
   (`Human.getSecretBackstory` — body is `try
   context.getSecretBackStory()`, which always throws) fire
   correctly? Throwing-only resolvers are an interesting
   semantic edge: re-invoking on retry produces the same throw
   (idempotent observably) but the body has no success path
   to infer from. Replayable mode tolerates `unknown`; strict
   mode shouldn't single this case out vs. the four success-
   path resolvers.

3. **Pure-resolver silence in replayable mode.** Do all five
   annotated resolvers stay silent in replayable mode? All
   five delegate to `StarWarsContext.<method>` calls that are
   pure lookups against static-let-bound dictionaries. If any
   fires in replayable, that's a precision / inference-gap
   finding scoped to a slice. Predicted outcome: 5/5 silent.

4. **Strict-mode cluster shape.** What does strict_replayable
   produce? Hypothesis: all five resolvers fire on their
   delegated `context.<method>` call (single cluster: "context
   methods unannotated"). The cluster size will be exactly 5
   (one fire per resolver) if the hypothesis is right; deviation
   from 5 surfaces secondary patterns worth investigating.
