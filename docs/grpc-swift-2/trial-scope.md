# grpc-swift-2 — Trial Scope

Fourteenth adopter road-test. First gRPC target; first exposure
to the four canonical RPC handler shapes (unary, server-streaming,
client-streaming, bidirectional-streaming) in a single round; first
SwiftProtobuf builder-pattern surface measured.

Picked under the post-2026-04-24 selection rule (domain/shape
novelty over project obscurity — see
`memory/project_validation_phase2.md`). Same demo-corpus framing as
the swift-aws-lambda-runtime round: real production gRPC-Swift
consumers are scarce on GitHub (closest hit was a 0-star, 2020
tutorial repo) so the Apple-maintained Examples corpus is the
infrastructure smoke test, not an FP-rate validation set.

See [`../road_test_plan.md`](../road_test_plan.md) for the template.

## Research question

> "On gRPC Swift 2's `SimpleServiceProtocol` handler shapes — the
> four canonical RPC kinds (unary, server-streaming, client-streaming,
> bidirectional-streaming) — does `@lint.context replayable` placed on
> the handler `func` produce the expected diagnostic profile? Does the
> textbook bidirectional 'append-on-receive' shape (`recordNote` in
> `routeChat`) fire as the canonical non-idempotent gRPC example, and
> do the three pure handlers stay silent?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `0ca8a12`
  (post-PR #29 merge tip, 2026-04-25 — closure-binding cross-reference
  + multi-rule SwiftLint hygiene). 2397 tests green on a clean build.
- **Upstream target:** `grpc/grpc-swift-2` @ `d19a948` on `main`
  (2026-04-16 push — Apple Cloud Services maintained, async/await
  structured-concurrency v2 stack). v2 chosen over the v1
  `release/1.x` branch because v1 is callback/NIO-handler shaped —
  already covered by the `swift-nio` round — whereas v2's
  `SimpleServiceProtocol` `async throws` handlers are a fresh shape.
- **Fork:** `Joseph-Cursio/grpc-swift-2-idempotency-trial`, hardened
  per road-test recipe (issues/wiki/projects disabled, README banner,
  trial branch as default).
- **Trial branch:** `trial-grpc-swift-2`, forked from upstream
  `d19a948`. Fork-authoritative — scans run against a fresh clone
  of the fork, not an ambient checkout.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required on the adopter.

## Annotation plan

Five handlers across two example packages, chosen for shape
diversity. The `route-guide` example is the canonical
google.routeguide protocol — explicitly designed by the gRPC
project to demonstrate all four RPC kinds in one service —
making it a natural fit for shape-coverage measurement.

| # | File | Handler | RPC shape |
|---|------|---------|-----------|
| 1 | `Examples/route-guide/Sources/Subcommands/Serve.swift:104` | `getFeature(request:context:)` | **Unary.** Pure read — `findFeature` lookup on `let features` array. Should stay silent. |
| 2 | `Examples/route-guide/Sources/Subcommands/Serve.swift:130` | `listFeatures(request:response:context:)` | **Server-streaming.** Pure filter on `let features`, writes results to `RPCWriter`. Should stay silent in replayable; the `RPCWriter.write` shape is what's under test. |
| 3 | `Examples/route-guide/Sources/Subcommands/Serve.swift:143` | `recordRoute(request:context:)` | **Client-streaming.** Consumes input stream, computes summary from local mutable scalars (`pointsVisited`, `distanceTravelled`). No external mutation. Should stay silent. |
| 4 | `Examples/route-guide/Sources/Subcommands/Serve.swift:179` | `routeChat(request:response:context:)` | **Bidirectional.** For each input note, calls `self.receivedNotes.recordNote(_:)` — Mutex-guarded append to a stored `[RouteNote]`. **Canonical gRPC non-idempotent shape — should fire.** |
| 5 | `Examples/hello-world/Sources/Subcommands/Serve.swift:48` | `sayHello(request:context:)` | **Unary.** Baseline minimal handler — single message construction + return. Should stay silent. |

Echo example deliberately not annotated: its handler shapes are
isomorphic to route-guide's and adding it would dilute the per-shape
signal without surfacing new patterns.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each handler `func`. No logic
  edits, no imports, no new types.
- **Audit cap.** 30 diagnostics max per mode (template default).
  If strict-replayable exceeds 30, decompose the excess into
  named clusters without per-diagnostic verdicts.

## Pre-committed questions

1. **Bidirectional-streaming append-on-receive correctness.** Does
   handler #4 (`routeChat` → `recordNote`) fire as the canonical
   non-idempotent gRPC bidi shape, with a clean diagnostic message
   that points at the right callee? This is the single highest-
   confidence catch the round can produce — it is the textbook
   gRPC example of a handler that would duplicate work on retry.

2. **Pure-handler silence across the four RPC kinds.** Do handlers
   #1 (unary read), #2 (server-stream over a pure filter), #3
   (client-stream over local-only scalars), and #5 (unary minimal)
   stay silent in replayable mode? Any unexpected fire here is a
   noise/precision finding scoped to a slice. The interesting case
   is handler #2 — if `RPCWriter.write` fires as non-idempotent in
   replayable, that's a cross-adopter framework-shape gap (every
   gRPC server uses the writer).

3. **Strict-mode SwiftProtobuf builder-pattern coverage.** Does
   strict_replayable fire on `Foo.with { $0.name = "..." }` builder
   calls? Cross-adopter implication: SwiftProtobuf is the message
   shape for every grpc-swift / Apple-server protobuf adopter. If
   the `.with { … }` builder pattern fires as unannotated, that's
   a cross-adopter slice candidate (potentially second-adopter
   evidence beyond gRPC itself).

4. **Demo-corpus signal/noise.** Per the swift-aws-lambda-runtime
   round, demo bodies (echo + base64 + AWS SDK reads) produce a
   zero-Run-A yield because they have no real side effects. Does
   the same pattern hold here, or does the `recordNote` shape in
   route-guide give Run A a non-zero yield that demo Lambda
   examples couldn't? If yes, route-guide is a cleaner
   "infrastructure-smoke-test" target than awslabs/Examples for
   future rounds where Run A signal is needed.
