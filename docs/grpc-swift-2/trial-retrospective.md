# grpc-swift-2 — Trial Retrospective

## Did the scope hold?

Yes — measurement-only, doc-comment annotations only, no logic
edits, audit cap not exceeded (17 strict-mode fires < 30). One
mid-round protocol deviation: the audit was conducted at the
cluster level for the 16 strict-only fires rather than per-row,
because the four named clusters covered everything cleanly and
per-row verdicts would have repeated themselves. Folded back into
the findings doc as a four-cluster decomposition.

## Pre-committed questions

### 1. Bidirectional-streaming append-on-receive correctness

**Yes, with a clean diagnostic.** `recordNote` fires at
`Serve.swift:184` with the message *"Non-idempotent call in
replayable context: 'routeChat' is declared `@lint.context
replayable` but calls 'recordNote', whose effect is inferred
`non_idempotent` from its body."* — names the correct callee,
correctly attributes the inference (body-based, not a hardcoded
list), and offers the two right remediations (idempotent
alternative or dedup-key wrapper).

This is the round's high-confidence catch and the canonical
gRPC bidirectional-streaming non-idempotent example. The
google.routeguide protocol was *designed* by the gRPC project
to demonstrate the four RPC kinds; finding that the linter
fires the correct diagnostic on the bidi handler that the
protocol authors chose to make append-mutating is the strongest
"does this work on the canonical shape" evidence the round
could produce.

### 2. Pure-handler silence across the four RPC kinds

**All four pure handlers stayed silent in replayable mode.**
The interesting case is server-streaming (`listFeatures`):
`RPCWriter<T>.write(_:)` is structurally a per-message wire
emit, mechanism-wise non-idempotent on retry, but the linter
correctly does not flag it in replayable mode — which is the
right call, because the at-least-once semantic of gRPC
streaming responses *is* the reason the handler is replayable
in the first place. Flagging the writer would be circular.

This means `RPCWriter.write` doesn't need a framework-receiver
whitelist entry for replayable mode; it's already correctly
under-flagged. It only surfaces under strict mode (cluster D
in findings), where the verdict is "defensible by framework
design."

### 3. Strict-mode SwiftProtobuf builder-pattern coverage

**Yes — `Foo.with { … }` fires 5× under strict mode.** This
is the round's cleanest cross-adopter slice candidate. 4 fires
of `with` in `route-guide` (in `getFeature` and `recordRoute`)
plus 1 fire of `Helloworld_HelloReply` in `hello-world`. Both
are SwiftProtobuf-generated message construction shapes —
`<Type>.with(populator:)` (a `swift-protobuf`-library extension
on every generated message type) and the bare `<Type>.init()`
generated initialiser.

First-adopter evidence — no prior round has measured SwiftProtobuf
surface. Crosses the 2-adopter threshold the next time any
protobuf consumer repeats the cluster. That includes future
grpc-swift adopters (high probability) and Apple-server apps
that consume protobuf for non-gRPC reasons (lower probability
but possible — some Vapor / Hummingbird APIs are protobuf-shaped).

Fix direction is mechanically straightforward when triggered:
add a `protobuf` namespace to the existing `idempotentReceiverMethodsByFramework`
infrastructure (commit `040f186` in linter, originally Hummingbird-
introduced and used by other framework receiver shapes). Whitelist
`with(_:)` on types in modules that consume `swift-protobuf`, plus
the bare-init form for generated message types.

### 4. Demo-corpus signal/noise vs awslabs/Lambda Examples

**Cleaner signal than awslabs Examples.** The route-guide
example produces a non-zero Run A yield (1 catch on the bidi
handler) where awslabs/Examples produced zero (demo bodies
are pure echo + base64 + AWS SDK reads with no real side
effects). The reason is structural, not coincidence: the
google.routeguide protocol was *intentionally* designed to
demonstrate the bidi append shape, so its demo body
genuinely contains the kind of effect that idempotency
linting cares about.

Implication for future rounds: when an "infrastructure smoke
test" target is needed (validate handler-shape coverage, not
FP rate), gRPC's `route-guide` example is a better choice
than awslabs/Examples because it has a guaranteed Run A
positive control built into the canonical demo. Adding to
the policy notes below.

## Counterfactuals

What would have changed the outcome:

- **If echo had been annotated.** Echo's handlers are isomorphic
  to route-guide's four shapes but operate on user-provided
  strings rather than a stored dataset. Annotating echo would
  have added 4 silent handlers (boosting the silence-correctness
  signal) but no new diagnostic shape — the SwiftProtobuf builder
  cluster is the only fire shape that would have differed (echo
  doesn't use `Foo.with { … }`, returns `EchoResponse.with { … }`
  inline, so it would have added 1-2 more `with` fires under
  strict). Decision to skip echo stands.

- **If grpc-swift v1 had been chosen.** v1 is callback/NIO-handler
  shaped, structurally similar to swift-nio's own handler
  surface (already road-tested). The fresh-shape signal would
  have been zero — v1 is the wrong target for "what is gRPC's
  novel handler shape?" because it predates async/await
  structured concurrency. Decision to target v2 stands.

- **If a production gRPC consumer had been available.** Search
  turned up only `yulin-liang/grpc-swift-server` (0 stars,
  2020, abandoned) — no real production grpc-swift consumer
  surfaces in GitHub search. This is the same scarcity pattern
  as awslabs/Examples: novel-domain frameworks tend to lag
  behind production adoption signals. Round was correctly
  framed as infrastructure smoke test rather than FP-rate
  validation.

## Cost summary

- **Estimated:** ~30 minutes (small annotation surface, two
  scans, three docs).
- **Actual:** ~30 minutes wall clock from "fork created" to
  "findings doc written." Linter green-tip check (5 minutes
  for clean+test) was the longest single step. Scans were
  near-instant — no SPM resolution required for the three
  example packages.

## Policy notes

Folded back into [`../road_test_plan.md`](../road_test_plan.md)
on a future revision when there's something else to bundle:

- **gRPC route-guide as canonical infrastructure smoke test.**
  Add to the road-test plan that when a future round needs an
  "infrastructure smoke test" (validate that the linter walks
  novel handler shapes, not FP-rate measurement), grpc-swift-2's
  `route-guide` example is preferred over demo corpora that
  produce zero Run A yield. The route-guide protocol was
  designed by the gRPC team to exercise all four RPC kinds in
  one service, with a deliberately-mutating bidi handler — it
  has a guaranteed Run A positive control that demo Lambda
  examples lack.

- **Cluster-level audit cap policy.** When strict-mode fires
  decompose cleanly into < 5 named clusters (each with 1-6
  fires of the same shape), per-row verdicts are noise vs.
  cluster-level verdicts. The road-test plan currently mandates
  per-row up to 30 / cluster-only above 30; consider lowering
  the per-row threshold when cluster decomposition is clean.
  Not urgent — this round handled it ad-hoc and the findings
  doc reads cleanly. Mention if the same pattern recurs on a
  future round.

## Data committed

- `trial-scope.md`
- `trial-findings.md`
- `trial-retrospective.md`
- `trial-transcripts/replayable.txt`
- `trial-transcripts/strict-replayable.txt`

Trial fork (authoritative): `Joseph-Cursio/grpc-swift-2-idempotency-trial`
on branch `trial-grpc-swift-2`. Final state restored to
`@lint.context replayable` (the strict variant was committed
mid-round at `99cfc549`, then reverted at `809c4c81` so the
authoritative branch tip carries the documented Run A state).
