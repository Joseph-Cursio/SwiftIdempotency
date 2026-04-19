# swift-nio — Trial Findings

## Run A — replayable context

**2 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

| Handler | Line | Callee | Inference path |
|---|---|---|---|
| `channelRead` | 533 | `handleFile` | body inference |
| `channelRead` | 537 | `handleFile` | body inference |

Both catches are the same `handleFile` helper called from two
branches of the URL-routing switch (`/sendfile/` and `/fileio/`).
Body inference determines `handleFile` is non-idempotent by
reading its body.

### What DIDN'T fire (the bulk of channelRead's calls)

This is the interesting part. `channelRead` calls:

- `Self.unwrapInboundIn(data)` — generic-dispatch unwrap
- `self.handler(context, reqPart)` — closure invocation
- `self.dynamicHandler(request:)` — helper
- `request.uri.chopPrefix(...)` — String extension
- `self.state.requestReceived()` — state-machine mutation
- `self.buffer.clear()` — ByteBuffer mutation
- `self.buffer.writeString(...)` — ByteBuffer append
- `responseHead.headers.add(...)` — HTTPHeaders mutation
- `Self.wrapOutboundOut(response)` — generic-dispatch wrap
- `context.write(...)` — channel write
- `self.state.requestComplete()` — state-machine mutation
- `self.buffer.slice()` — ByteBuffer read
- `self.completeResponse(context, trailers:, promise:)` — helper

Of these, **none** match the bare-name nonIdempotent heuristic
(`create` / `insert` / `append` / `publish` / `enqueue` / `post`
/ `send` / `stop` / `destroy` / `update`). NIO's API vocabulary
(`write`, `writeAndFlush`, `wrapOutboundOut`, `completeResponse`,
`flush`, `add`, `clear`, `slice`, `unwrap`) simply doesn't
overlap with idempotency-violating adopter-layer patterns
(`send*`, `insert*`, `create*`, etc.).

The `append` keyword is on our list but NIO uses `writeString`,
`writeBuffer`, `writeInteger`, etc. — never `.append` on
`ByteBuffer`. `ByteBuffer.writeString(_:)` returns the number of
bytes written; the name doesn't prefix-match anything our
heuristic recognises.

**The vocabulary mismatch is the primary finding.** NIO's
layer-of-abstraction names things by protocol action (write,
flush, wrap, unwrap, slice, clear), not by business-logic
semantic (create, send, publish, update). The heuristic
targets the latter; NIO lives firmly in the former.

## Run B — strict_replayable context

**24 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

**Carried from Run A** (2): same `handleFile` catches.

**Strict-only** (22): fires on every unannotated NIO callee
inside `channelRead`. This is not an adoption-gap finding —
strict mode is doing exactly what it's designed to do on an
un-annotated codebase at this architectural level. Sample
callees firing:

- `unwrapInboundIn` / `wrapOutboundOut` (generic-dispatch
  methods from `ChannelInboundHandler` conformance)
- `completeResponse` (class method)
- `dynamicHandler` (class method)
- `chopPrefix` (String extension)
- `handler` (closure invocation via instance property)
- Various `context.write(...)` / `context.writeAndFlush(...)`
  sites (NIOCore `ChannelHandlerContext` methods)
- `slice`, `clear`, `writeString` on ByteBuffer
- `state.requestReceived` / `state.requestComplete` (State
  enum mutations)

The strict-mode count scales with the method body's call graph
depth. None of these fires are slice candidates — they are
"adopter should annotate their own code" situations, except
pointing at third-party (NIOCore) surface that NIO itself would
need to annotate for adopters to benefit.

## The `handleFile` catches — semantically correct, contextually wrong

Body inference's two `handleFile` catches are the round's most
interesting data point. Taken out of context, they're correct:
`handleFile` writes bytes to the socket, allocates memory, and
has observable side effects. Re-calling it produces double-sent
bytes.

But the **context is wrong**. NIO does not retry `channelRead`.
The method is called at most once per received HTTP chunk; the
socket's TCP retransmission is handled below NIO's layer, and
the HTTP retry semantics (if any) are handled above NIO's layer
(by the adopter application). The `@lint.context replayable`
annotation is a **lie at the NIO level** — no retry happens here.

The catches, therefore, flag something that's not actually a bug
in the NIO example. If anything, they are a demonstration that
the linter's rule suite trusts the annotation rather than
reasoning about whether the annotation makes sense. That's
defensible behaviour (the linter can't know the annotation is
wrong) but it does mean **NIO-layer code should not carry these
annotations in production**. Any catches would be misleading.

## Comparison to prior adopter rounds

| Round | Target | Replayable | Strict | Catches shape |
|---|---|---|---|---|
| 1 | hummingbird-examples/todos-fluent | 4 | 6 | framework-catchable, sliceable |
| 2 | pointfreeco | 6 | 38 | adopter-local + 2 genuine bugs |
| 3 | swift-nio | 2 | 24 | all contextually wrong (annotation is a lie) |

swift-nio is qualitatively different: the few catches it
produces are semantically correct on their face but architecturally
misapplied. Catches-per-annotation is low (2 with 1 annotation)
and they don't point at real bugs — they point at the annotation
itself being misplaced.

## Next-slice candidates

**None.** This is a null-result round by design. The measurement
confirms the proposal's claim that NIO is the wrong target.
No linter changes are warranted by this round's findings.

The only follow-up worth noting is the **full-corpus scan
timeout** observation (see `trial-scope.md`). If a future
measurement requires a clean full-repo scan, a single-process
attempt with a generous timeout would be worth trying before
declaring a performance issue. This round deliberately scoped
to a single directory to stay bounded.
