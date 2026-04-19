# swift-nio — Trial Retrospective

Shortest retrospective of the three adopter rounds. The
hypothesis ("NIO is the wrong target") was confirmed; there's
little else to report.

## Did the scope hold?

**Yes, after mid-round narrowing.** An initial attempt at a
full-corpus scan did not complete (see scope doc). The
measurement was rescoped to `Sources/NIOHTTP1Server/` — one
Swift file — which kept the round bounded. The rescope is
consistent with the round's null-result expectation: a full-
corpus measurement wasn't needed to answer the primary question.

## Answers to the four pre-committed questions

### (a) Does the heuristic fire on NIO's API vocabulary?

**Largely no.** NIO's layer-of-abstraction names things by
protocol action (`write`, `flush`, `wrap`, `unwrap`, `slice`,
`clear`, `add`) rather than by business-logic semantic (`send`,
`insert`, `create`, `update`). The bare-name and prefix-match
heuristics target the latter. On `channelRead`'s ~13 call
sites, zero matched a bare-name or prefix-match trigger.

One partial exception: `append` is in our bare list, but NIO
consistently uses `writeX` rather than `append` on `ByteBuffer`
(`writeString`, `writeBuffer`, `writeInteger`). So even the
one potential overlap doesn't materialise in practice.

### (b) Does body-based upward inference produce catches?

**Yes — 2 catches, both on `handleFile`.** Body inference read
`handleFile`'s definition and determined its effect. This is
the one mechanism that fires through NIO's vocabulary divergence;
the name-based path is silent, but the body-based path keeps
working because it reasons about the *deeper* call graph, not
the immediate callee's name.

Both catches are semantically defensible (handleFile does
write bytes) but contextually misapplied — NIO doesn't retry
channelRead, so "replayable context" is the wrong frame for
those catches.

### (c) New cross-adopter slice candidates?

**No.** The round confirms the design claim. No linter changes
are warranted.

A minor observation: the full-corpus scan timeout could be an
artefact of concurrent process contention (three CLI invocations
were running at once) or a genuine pathological case in the
linter. This round's data isn't strong enough to diagnose; not
a slice candidate, not a named follow-on, just a note to future
rounds that want to attempt a single-process clean scan.

### (d) What should change in CLAUDE.md guidance?

**Nothing.** The existing guidance — "SwiftNIO is explicitly
called out as the wrong target" — is now backed by direct
measurement rather than design reasoning alone. The language
doesn't need softening or strengthening. Worth noting that
the measurement produced non-zero catches (2), so "wrong
target" doesn't mean "silent"; it means "any catches you get
are contextually misapplied." A reader might expect zero, and
finding two could lead them to wrongly conclude NIO IS a
target. A sentence clarifying "non-zero catches are expected
but contextually meaningless" could be worth adding.

## What would have changed the outcome

- **A clean single-process full-corpus scan.** Would confirm
  whether the 27-minute hang is pathological or contention-
  driven. Cheap to try in a future round; not scope-creep-worthy
  here.
- **Annotating a protocol-layer handler rather than an HTTP-
  example handler.** Something like `NIOCore`'s
  `ChannelInboundHandler` conformance in a more production-
  shaped example. The HTTP1 echo example is trivially small
  and the single-callee-surface hits on `handleFile` are the
  only signal. A richer example would produce richer findings
  but the architectural conclusion would be the same.

## Cost summary

- **Estimated:** ~20 minutes (null-result round).
- **Actual:** ~30 minutes, mostly spent waiting on the hung
  full-corpus scans and then rescoping.

## Policy notes

- **Null-result rounds are worth doing.** They validate design
  claims with measurement rather than assertion. The round-
  planning overhead is real but the evidence is durable.
- **"Wrong target" does not mean "zero diagnostics."** The
  `handleFile` catches demonstrate that the linter will *try*
  to be helpful on any annotated code, including code where
  the annotation is semantically inappropriate. Adopters
  reading the road-test plan should understand that annotating
  NIO-layer code is a *mistake*, not just a no-op.
- **Full-corpus scan timeout on a 258-file repo** warrants
  investigation if it reproduces on a clean single-process run.
  pointfreeco (918 files) scanned in ~3 minutes; swift-nio
  (258 files) did not complete in 27 minutes. Either a
  contention artefact or a genuine performance regression worth
  investigating.

## Toward completion criteria

Per [`../road_test_plan.md`](../road_test_plan.md):

- **Framework coverage** (criterion #2) — adding this round:
  Vapor (pointfreeco), Hummingbird + Fluent (todos-fluent),
  and now NIO (swift-nio). Point-Free ecosystem remains the
  last stated tier. swift-dependencies is implicitly covered
  via pointfreeco; TCA would be a pure-function-heavy target
  with different trade-offs.
- **Adoption-gap stability** (criterion #1) — this round
  produces **zero new named slice candidates**. Open
  slices from the pointfreeco round (escape-wrapper
  recognition) remain deferred. Plateau-clock: one round of
  zero-new-slices complete.
- **Macro-form** (criterion #3) — already ticked on
  todos-fluent; not exercised on swift-nio (wouldn't make
  sense — there's no annotation reason to consume the
  macros package in NIO's architectural layer).

## Data committed

- `docs/swift-nio/trial-scope.md`
- `docs/swift-nio/trial-findings.md`
- `docs/swift-nio/trial-retrospective.md` — this document
- `docs/swift-nio/trial-transcripts/replayable.txt`
- `docs/swift-nio/trial-transcripts/strict-replayable.txt`

Adopter-side edit remains on the `trial-swift-nio` branch of
`swift-nio`, local-only.
