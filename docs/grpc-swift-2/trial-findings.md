# grpc-swift-2 — Trial Findings

Linter SHA `0ca8a12`. Target `grpc/grpc-swift-2` @ `d19a948`. Fork
`Joseph-Cursio/grpc-swift-2-idempotency-trial` on branch
`trial-grpc-swift-2`. Five handlers annotated `/// @lint.context
replayable` then flipped to `strict_replayable`.

## Run A — replayable

Transcript: [`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| # | Site | Callee | Verdict |
|---|------|--------|---------|
| 1 | `route-guide/Sources/Subcommands/Serve.swift:184` | `recordNote` (in `routeChat`) | **Correct catch.** |

**Yield:** 1 catch / 5 handlers = **0.20 including silent**, 1/1 =
**1.00 excluding silent** (4 silent handlers).

The single Run A diagnostic is the canonical gRPC bidirectional-
streaming non-idempotent example. `Notes.recordNote(_:)` does a
`Mutex.withLock` append to `self.notes` (a stored `[Routeguide_RouteNote]`);
on a retried `routeChat` invocation each input note would be
appended again, duplicating downstream "notes at the same location"
results. The diagnostic message names `recordNote` precisely and
suggests the right two remediations (idempotent alternative or
deduplication-key wrapper).

The four silent handlers are the correctness signal:

- `getFeature` (unary) — pure `self.features.first { … }` lookup.
- `listFeatures` (server-streaming) — pure `self.features.filter`
  + `RPCWriter.write` (the writer's `non_idempotent` mechanism is
  the at-least-once-streaming counterpart that makes the *handler*
  replayable in the first place; the linter correctly does not
  re-flag it).
- `recordRoute` (client-streaming) — for-loop over input stream;
  mutates only locals (`pointsVisited`, `distanceTravelled`,
  `previousPoint`), returns a fresh `RouteSummary`.
- `sayHello` (hello-world unary) — single message construction.

Predicted outcome from the scope doc: handler #4 fires, others
stay silent. **Outcome matches prediction.**

## Run B — strict_replayable

Transcript: [`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).
17 fires total (16 in route-guide + 1 in hello-world + 0 in echo,
which has no annotated handlers). Carried-from-A: 1; strict-only: 16.

### Carried from Run A (1)

| Site | Callee | Verdict |
|------|--------|---------|
| `route-guide/.../Serve.swift:184` | `recordNote` | **Correct catch.** Same fire as Run A; strict elevates the rule but the verdict is unchanged. |

### Strict-only — adopter-internal helpers (4)

Strict mode requires every callee to be *declared* idempotent /
observational / externally-keyed; body-inferable purity is not
sufficient. These four fires would silence with one-line
`/// @lint.effect idempotent` annotations on the helpers.

| Site | Callee | Verdict |
|------|--------|---------|
| `Serve.swift:108` | `findFeature` (in `getFeature`) | **Defensible by strict-mode design.** Pure `self.features.first` lookup; annotate the helper. |
| `Serve.swift:117`, `:119` | `with` (SwiftProtobuf builder, in `getFeature`) | See "SwiftProtobuf builder pattern" cluster below — strict-only, cross-adopter. |
| `Serve.swift:134` | `filter` (in `listFeatures`) | See "stdlib pure" cluster below. |
| `Serve.swift:135` | `isContained` (in `listFeatures`) | **Defensible by strict-mode design.** Pure Bool-returning extension on `Routeguide_Feature`; annotate. |
| `Serve.swift:138` | `write` (in `listFeatures`) | See "gRPC stream-emit" cluster below. |
| `Serve.swift:155` | `findFeature` (in `recordRoute`) | Same as `:108` — annotate `findFeature`. |
| `Serve.swift:160` | `greatCircleDistance` (in `recordRoute`) | **Defensible by strict-mode design.** File-private free function over stdlib math; annotate. |
| `Serve.swift:166` | `duration` (in `recordRoute`) | See "stdlib pure" cluster below. |
| `Serve.swift:167` | `with` (in `recordRoute`) | See "SwiftProtobuf builder" cluster. |
| `Serve.swift:168`, `:169`, `:170`, `:171` | `Int32` (primitive ctor coercions, in `recordRoute`) | See "primitive constructor" cluster. |
| `Serve.swift:185` | `write` (in `routeChat`) | See "gRPC stream-emit" cluster. |
| `hello-world/.../Serve.swift:52` | `Helloworld_HelloReply` | See "SwiftProtobuf builder" cluster. |

### Strict-only clusters

The 16 strict-only fires decompose into four named clusters:

#### A. Adopter-internal helpers (4 fires)

`findFeature` × 2, `isContained` × 1, `greatCircleDistance` × 1.
Each is a pure local helper that the body inferrer cannot label
declared-idempotent (strict mode rejects body-only inference by
design — the bargain of strict mode is that the developer must
annotate every callee). **Verdict: defensible by strict-mode
design.** Silenced with one-line `/// @lint.effect idempotent`
on each helper.

#### B. SwiftProtobuf builder pattern (5 fires)

`with` × 4 (route-guide) + `Helloworld_HelloReply` × 1 (hello-world).
The `Foo.with { $0.field = … }` SwiftProtobuf builder pattern is
the standard message-construction shape across **every** grpc-swift
adopter and across most Apple-server protobuf consumers. The body
of `Foo.with` is generated `swift-protobuf` library code that
returns a freshly-built message — semantically `idempotent` (every
call produces a new value, no shared state, no external observable
effect).

**Verdict: cross-adopter adoption-gap candidate.** This is the
first round where SwiftProtobuf surface has been measured. If a
second adopter round (any future protobuf consumer) repeats this
cluster, it crosses the 2-adopter threshold for slice consideration.
Fix direction: a `swift-protobuf`-aware whitelist analogous to
the existing framework-receiver whitelists (`idempotentReceiverMethodsByFramework`
infrastructure from commit `040f186`) — `protobuf` namespace
recognising `<Type>.with(_:)` and direct constructors of types
ending in standard generated suffixes (`_<name>`, message types
generated by `protoc-gen-swift`).

#### C. stdlib pure methods (6 fires)

`filter` × 1, `duration` × 1, `Int32` × 4. Stdlib closure-taking
pure methods (`filter`) and primitive-coercion constructors
(`Int32`, also broadly `Int`/`Double`/`String`) plus
`Duration.duration(to:)`. These fire on every strict-mode scan
and represent the universal "stdlib in strict mode" tax — the
same noise that surfaced on swift-aws-lambda-runtime, isowords
strict, and TCA strict.

**Verdict: defensible by strict-mode design / known cross-adopter
noise.** Strict mode is meant to require explicit annotation;
stdlib-trust would be a separable policy decision (a "trusted
core" tier) rather than a fix to this round's findings. Not
counted as new evidence — this is the third+ round to log
the same pattern.

#### D. gRPC stream-emit `RPCWriter.write` (2 fires)

`write` × 2 — `RPCWriter<T>.write(_:)` in `listFeatures` (server-
streaming) and `routeChat` (bidirectional-streaming). gRPC's
streaming response writer; each call dispatches one message to
the wire. On retry, every `write` would re-emit, so mechanism-
wise it is non-idempotent — but the framework's at-least-once
contract makes the **handler** replayable in the first place,
and the application is supposed to tolerate or compensate for
duplicate downstream message delivery (same as Vapor's response
in retry scenarios).

**Verdict: defensible by framework design.** The replayable
context exists *because* gRPC streaming is at-least-once; the
writer is the mechanism, not the violation. If the adopter
team wanted strict-mode silence, the right shape is an
`@Observational` annotation on the writer or an `@ExternallyIdempotent`
annotation on a wrapper that includes a per-message dedup token —
both of which are downstream-application policy, not a linter
shape change.

Cross-adopter note: this is structurally identical to the
question raised on Hummingbird `addMiddleware` and SPI-Server
`AppMetrics.push` — observability-shape framework primitives
that fire in strict mode but are the framework's correct
mechanism, not the user's bug. No 2-adopter slice trigger
(this is gRPC-specific; the Hummingbird/Vapor analogues are
their own shapes).

### Cluster summary

| Cluster | Fires | Verdict | Cross-adopter status |
|---------|-------|---------|----------------------|
| A. Adopter helpers | 4 | Defensible by strict-mode design | adopter-local |
| B. SwiftProtobuf `.with` / msg-ctor | 5 | **Adoption gap candidate** | **first-adopter evidence** |
| C. stdlib pure | 6 | Defensible / known cross-adopter noise | n+ adopter evidence |
| D. gRPC `RPCWriter.write` | 2 | Defensible by framework design | gRPC-specific |
| Carried (`recordNote`) | 1 | Correct catch | — |

**Yield:** 17 / 5 = 3.40 fires per handler (strict-mode aggregate).
The "real signal" yield (Run A carried + adoption-gap candidates)
is 1 + 5 = **6 of 17 strict diagnostics** carry slice-relevant
information; the remaining 11 are strict-by-design or known noise.

## Comparison to scope-doc predictions

| Pre-committed question | Predicted | Observed |
|------------------------|-----------|----------|
| 1. Bidi append-on-receive fires | yes | **yes** — clean diagnostic, names `recordNote`, suggests right remediations. |
| 2. Pure-handler silence across four RPC kinds | yes (incl. `RPCWriter.write` not flagged in replayable) | **yes** — `RPCWriter.write` correctly *not* flagged in Run A; only fires under strict mode in cluster D. |
| 3. SwiftProtobuf builder fires under strict | yes | **yes** — 5 fires form the round's cleanest cross-adopter slice candidate. |
| 4. Run A non-zero yield (vs Lambda demo zero) | yes | **yes** — route-guide yields 1 catch / 1 non-silent handler = 1.00 excluding silent. Cleaner than awslabs Examples corpus for infrastructure-smoke-test purposes. |

All four pre-committed predictions held. The most actionable
finding is the SwiftProtobuf builder cluster — the first
measurement of protobuf-message construction surface, and
the kind of cross-adopter pattern that becomes a slice once
a second adopter (any future grpc-swift adopter, or any
Apple-server app using SwiftProtobuf for non-gRPC reasons)
repeats it.
