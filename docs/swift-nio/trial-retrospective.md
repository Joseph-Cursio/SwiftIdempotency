# swift-nio — Trial Retrospective

Slot-8 remeasurement of the swift-nio round. Overwrites the prior
retrospective; git history is the audit trail.

## Did the scope hold?

**Yes, cleanly.** Four handlers were annotated exactly as planned;
full-corpus scans completed in ~95s under both modes; no mid-round
rescoping was required. The fork-authoritative workflow (first
dogfooded end-to-end on the Lambda round) carried over without
friction: provision the fork, branch, push, default-switch,
re-clone, scan. Two push-clone-scan cycles for the Run A / Run B
flip — no sequencing hiccups.

## Answers to the four pre-committed questions

### (a) Full-corpus scan bounded time post PR #16?

**Yes — 95 seconds on the 549-file corpus, both modes.** The
PR #16 wall-clock budget (default 30s per inference pass) was not
exercised — the scan completes before the budget engages. Prior
round's 27-minute non-completion was either a contention artefact
(three concurrent `swift run CLI` invocations on the same machine)
or a pathological case that subsequent linter changes incidentally
cleared. Either way, **slot 5 (real perf fix) has no triggering
evidence** from this round and stays deferred.

One bookkeeping note: the ~95s is dominated by the release build's
warmup and the SwiftSyntax parse pass — the actual inference loop
is a minor fraction. Future perf-regression watch should distinguish
parse time from inference time before concluding the inferer has
regressed.

### (b) Full-corpus aggregates vs scoped sums?

**Different, not equal, in a meaningful way.** Scoped sums across
four handlers:

| Mode | Scoped sum | Full corpus |
|---|---|---|
| Run A (replayable) | 2 | 0 |
| Run B (strict) | 40 | 0 |

Both modes collapse to 0 on the full corpus. The cause is inference
quality, not dropped signals: when the full NIO module graph is
visible, body inference resolves every framework callee (`write`,
`writeAndFlush`, `unwrapInboundIn`, `wrapOutboundOut`, `writeString`,
`writeBuffer`, `slice`, `clear`, `add`, etc.) to `idempotent`, at
which point strict mode has nothing to fire on and `handleFile`'s
non-idempotent body inference also withdraws (its NIOPosix /
NIOFileSystem internals now resolve to idempotent too).

The consequential adoption-guidance finding: **scoped scans are
not a reliable preview of full-corpus results.** This is a
documentation item, not a slice.

### (c) Heuristic vocabulary mismatch reproduces?

**Yes, at 100%.** Four handlers, ~30 distinct callee identifiers,
zero matches against the bare-name `non_idempotent` heuristic
(`create`, `insert`, `append`, `publish`, `enqueue`, `post`, `send`,
`stop`, `destroy`, `update`). NIO's vocabulary — `write`,
`writeAndFlush`, `wrap*` / `unwrap*`, `slice`, `clear`,
`writeString`, `writeBuffer`, `writeInteger` — targets the
protocol-action layer, not the business-logic layer. The heuristic
targets the latter; the two layers never overlap in NIO's API.

This is structural to the framework, not specific to any one
handler. The prior round hypothesised it from one handler's 13
callees; this round confirms across three additional handlers.

### (d) New cross-adopter slice candidates?

**None.** The round produces zero new adoption-gap candidates.
The scoped-vs-full-corpus divergence is an inference-quality
*feature* (more code → more resolution), not a gap. Slot 5
remains deferred. No slice work falls out of this round.

## What would have changed the outcome

- **Annotating NIO library code** (`NIOHTTP1Server.HTTPServerPipelineHandler`,
  `NIOCore.ChannelHandler` extensions, etc.) rather than example
  handlers. The library surface has richer behaviour and calls
  out to more internal layers — a cleaner test of multi-hop
  inference than the example handlers provide. But the
  architectural conclusion would be the same: NIO is the wrong
  target.
- **Scanning a NIO-using adopter app** (e.g., Vapor's NIOHTTP1-
  backed listener) with annotations placed on the *adopter's*
  business-logic handlers rather than NIO's channel handlers.
  That would measure whether NIO-shaped indirection through
  `context.write` chains obscures non-idempotent adopter-layer
  calls. Different question — not scoped to this round.

## Cost summary

- **Estimated:** ~30 minutes (cheap per slot 8's framing).
- **Actual:** ~45 minutes. Breakdown: fork branch setup + four
  annotations + two push cycles (~10 min), release build warmup
  and four scan invocations (~10 min wall-clock including two
  full-corpus runs at ~95s each), writing up the three docs and
  capturing transcripts (~25 min).

The ~15 minute overrun is in documentation — the measurement
itself was as cheap as slot 8 estimated.

## Policy notes

- **Null-result rounds are worth doing, again.** The prior round
  also said this, and this round doubles the evidence. A cheap
  confirm-the-claim measurement produced one concrete adoption-
  guidance finding (scoped-vs-full divergence) that wouldn't have
  come from design reasoning alone. Durable evidence accrues.
- **Default to full-corpus scans in road-tests** unless there's a
  specific reason to scope. The prior round's rescope was
  performance-driven, not by design; this round's clean full-corpus
  run shows that scoped-scan numbers can diverge from full-corpus
  numbers in the opposite direction of intuition (less code →
  more catches, not fewer). When possible, do both and report the
  delta if any.
- **"Wrong target" still doesn't mean "zero diagnostics" on
  scoped scans.** Full-corpus: yes. Scoped: no. A reader
  encountering this round should understand that the 0/0 headline
  is the full-corpus result; scoping produces non-zero counts
  that are inference-scope artefacts, not a reason to revisit the
  architectural claim.

## Toward completion criteria

Per [`../road_test_plan.md`](../road_test_plan.md):

- **Framework coverage (criterion #1).** Unchanged from the prior
  round — Vapor (pointfreeco), Hummingbird (todos-fluent), NIO
  (this round), Point-Free ecosystem (pointfreeco), TCA, AWS Lambda.
  All four listed framework tiers now have at least one adopter
  road-tested.
- **Adoption-gap stability (criterion #2).** **Zero new named
  adoption-gap slices** from this round — consistent with the
  null-result framing. The three-consecutive-rounds counter
  continues at whatever it's on post slot-10; this round doesn't
  reset it.
- **Macro-form (criterion #3).** Not exercised on swift-nio
  (same as prior round — no annotation reason for NIO-layer code
  to consume the macros package). Already ticked on todos-fluent
  and now webhook-handler-sample.

## Data committed

- `docs/swift-nio/trial-scope.md` — overwritten with slot-8 scope
- `docs/swift-nio/trial-findings.md` — overwritten with full-corpus findings
- `docs/swift-nio/trial-retrospective.md` — this document
- `docs/swift-nio/trial-transcripts/replayable.txt` — full + scoped
- `docs/swift-nio/trial-transcripts/strict-replayable.txt` — full + scoped

Adopter-side edits on the `trial-swift-nio` branch of
`Joseph-Cursio/swift-nio-idempotency-trial`, push tip `71a90f4`
(replayable-mode final state). Strict mode scans used tip
`6832ff0` from the mid-round flip; both tips are preserved in
the fork's ref history.
