# Graphiti — Trial Findings

Linter SHA `0ca8a12`. Target `GraphQLSwift/Graphiti` @ `20c8d02`.
Fork `Joseph-Cursio/graphiti-idempotency-trial` on branch
`trial-graphiti`. Five resolver methods annotated `/// @lint.context
replayable` then flipped to `strict_replayable`.

## Run A — replayable

Transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

**No issues found.** Zero diagnostics across all five annotated
resolvers.

**Yield:** 0 catches / 5 handlers = **0.00 including silent**.

This is the round's correctness signal. All five resolvers
delegate to `StarWarsContext.<method>` calls that operate on
`private static let` data — pure dictionary lookups
(`getCharacter` / `getHero` / `getHuman` / `getDroid`), filter/sort/map
chains over static-let dictionaries (`getPlanets` / `getHumans` /
`getDroids` / `search`), and the `getSecretBackStory()` always-
throws case. Every body is mechanically idempotent (or throws-
identically on replay), and the linter correctly does not
flag any of them.

The DSL-binding shape (`Field("hero", at: StarWarsResolver.hero)`
— unbound static-method references in the schema builder)
causes **no** linter confusion. The annotations attach to the
resolver `func` decls in `StarWarsResolver.swift`; the inferrer
walks the bodies as standard method-reference handlers, with
no slot 3 receiver-resolution interference.

Predicted outcome from the scope doc: 5/5 silent. **Outcome
matches prediction.**

## Run B — strict_replayable

Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

5 fires total — exactly one per annotated resolver. All five
fall into a single cluster.

### Cluster: adopter context-method calls (5 fires)

| Site | Callee | Verdict |
|------|--------|---------|
| `StarWarsResolver.swift:16` | `getFriends` (in `Human.getFriends`) → `context.getFriends(of: self)` | **Defensible by strict-mode design.** Pure `compactMap` over `character.friends` looking up via `getCharacter(id:)` against static-let `humanData` / `droidData`. |
| `StarWarsResolver.swift:23` | `getSecretBackStory` (in `Human.getSecretBackstory`) → `try context.getSecretBackStory()` | **Defensible by strict-mode design.** Always-throws body. Annotating with `/// @lint.effect idempotent` would silence — replayed throw is observably identical to first throw. |
| `StarWarsResolver.swift:48` | `getHero` (in `StarWarsResolver.hero`) → `context.getHero(of:)` | **Defensible.** Pure switch-on-episode returning `static let` characters. |
| `StarWarsResolver.swift:57` | `getHuman` (in `StarWarsResolver.human`) → `context.getHuman(id:)` | **Defensible.** `Self.humanData[id]` — direct dictionary lookup. |
| `StarWarsResolver.swift:74` | `search` (in `StarWarsResolver.search`) → `context.search(query:)` | **Defensible.** `getPlanets + getHumans + getDroids` concatenation; each is a sorted-filtered-mapped read over static-let data. |

**Single cluster.** All five strict-only fires share the same
shape: resolver delegates to `context.<method>`, the context
method's effect is undeclared, strict mode requires explicit
declaration. One-line `/// @lint.effect idempotent` on each
context method (8 methods total in `StarWarsContext`, each with
trivially-pure bodies) would silence the entire cluster.

**Verdict: defensible by strict-mode design.** This is the
canonical strict-mode bargain — the developer must annotate
every callee, and strict mode is correctly identifying that
the StarWarsContext methods aren't yet annotated. Not a
linter shape change; not a cross-adopter slice candidate;
not new evidence beyond confirming strict mode behaves as
documented.

### Cluster summary

| Cluster | Fires | Verdict | Cross-adopter status |
|---------|-------|---------|----------------------|
| Adopter context-methods | 5 | Defensible by strict-mode design | adopter-local |

**Yield:** 5 / 5 = 1.00 fires per handler in strict mode (one
per handler, single cluster). No carried-from-A fires (Run A
was silent), no second cluster, no cross-adopter shape evidence.

## Comparison to scope-doc predictions

| Pre-committed question | Predicted | Observed |
|------------------------|-----------|----------|
| 1. DSL-binding triggers slot 3 receiver resolution | unclear (round was designed to test) | **No, slot 3 not triggered.** Annotations on resolver `func` decls walk cleanly; DSL-side `Field("hero", at: StarWarsResolver.hero)` is invisible to the body inferrer (which is correct — the binding is the schema-author's contract, not a code-flow analysis input). |
| 2. Throwing-only resolver fires correctly | yes | **Yes** — `Human.getSecretBackstory` fires on `getSecretBackStory` callee in strict mode (cluster member). Replayable mode silent (correct — `unknown` tolerated). |
| 3. Pure-resolver silence in replayable | yes (5/5) | **Yes — 5/5 silent.** |
| 4. Strict-mode cluster size | exactly 5 (one per resolver, single cluster) | **Exactly 5 — single cluster.** Hypothesis confirmed. |

All four pre-committed predictions held. The round's most
substantive finding is **negative evidence on slot 3**: the
GraphQL DSL field-binding pattern alone does not surface
receiver-resolution issues, because resolver method names
are unique within their declaring type and the inferrer walks
the annotated method body without reference to the schema-
side binding. Slot 3 still requires same-name method
collisions across types with differing tiers — not present
in this corpus.

## Cross-round comparison

| Round | Run A yield | Run B fires | Cross-adopter slice candidates |
|-------|-------------|-------------|-------------------------------|
| swift-aws-lambda-runtime | 0.00 incl silent | (large strict residual, demo bodies) | none |
| grpc-swift-2 | 0.20 incl silent (1 catch) | 17 fires / 4 clusters | **SwiftProtobuf builder** (1-adopter) |
| **graphiti** | **0.00 incl silent** | **5 fires / 1 cluster** | **none** |

Graphiti is the *cleanest* round of the three — single-cluster
strict residual, all fires identically-shaped, no precision
issues, no new cross-adopter patterns. Cleanest because:

- StarWarsAPI is a smaller, more focused demo than route-guide
  or awslabs/Examples (one resolver type + one context type +
  static-let data).
- The resolver/context split is structurally what GraphQL is
  designed for: thin orchestration in the resolver, all real
  effect in the context. So the "annotate every callee" tax
  in strict mode lands on a small named surface (the eight
  `StarWarsContext` methods).
- No third-party framework primitives beyond Graphiti's own
  DSL (which the scan doesn't enter — DSL closures are
  Graphiti-internal builder code, not the adopter's resolver
  bodies).

This is consistent with the broader pattern: **GraphQL
resolvers, when written in the Graphiti idiom, partition
cleanly into "trivial orchestration" + "context-side data
access"**, which is exactly the partition idempotency
annotation cares about. The pattern is simpler to annotate
end-to-end than HTTP handlers (which mix context and effect
in the body) or gRPC handlers (which sometimes mutate stored
properties via Mutex like `routeChat` did).

If a future Graphiti adopter round happens (production
consumer with real database calls in the context), the
expected shape is: zero Run A fires (resolvers trivial) +
strict-mode fires concentrate in the context. **The slice
candidate, if any, would be on the context-method side, not
the resolver side.**
