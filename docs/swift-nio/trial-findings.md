# swift-nio — Trial Findings

Slot-8 full-corpus remeasurement of the swift-nio round. Replaces
the prior round's single-file scoped measurement.

## Scan completion (primary structural answer)

**Full-corpus scan completes in ~95 seconds** on the 549-file /
43-module corpus at `apple/swift-nio` tag `2.98.0`. That's a
≥17× improvement over the prior round's 27-minute non-completion.

Per-run wall-clock (MacBook Pro, release build):

| Run | Scope | Wall-clock | Files |
|---|---|---|---|
| Run A (replayable) | full corpus | 95s | 549 |
| Run A (replayable) | `Sources/NIOHTTP1Server` | <1s | 1 |
| Run B (strict) | full corpus | 96s | 549 |
| Run B (strict) | `Sources/NIOHTTP1Server` | <1s | 1 |

The PR #16 wall-clock budget (default 30s per inference pass) is
**not exercised** at this corpus size — the scan completes before
the budget engages. Slot 5 (real perf fix on the inference loop)
has no triggering evidence from this round.

## Run A — replayable context

**Full-corpus: 0 diagnostics.** Transcript:
[`trial-transcripts/replayable.txt`](trial-transcripts/replayable.txt).

Scoped-scan breakdown (per-target diagnostic counts):

| Target | Scoped diagnostics |
|---|---|
| `Sources/NIOEchoServer` | 0 |
| `Sources/NIOChatServer` | 0 |
| `Sources/NIOHTTP1Server` | 2 |

The 2 `NIOHTTP1Server` catches are `handleFile` body-inference
catches at lines 533 and 537 — the same pair the prior round
surfaced. Both fire because the scoped scan cannot see the
NIOPosix / NIOFileSystem surface that `handleFile` depends on, so
its body-inference result falls back to `non_idempotent`.

**Yield:**
- 2 catches / 4 handlers = 0.50 including silent
- 2 catches / 1 non-silent handler = 2.00 excluding silent
- When measured against the full corpus: 0 / 4 = 0.00

## Run B — strict_replayable context

**Full-corpus: 0 diagnostics.** Transcript:
[`trial-transcripts/strict-replayable.txt`](trial-transcripts/strict-replayable.txt).

Scoped-scan breakdown:

| Target | Scoped diagnostics |
|---|---|
| `Sources/NIOEchoServer` | 1 (`context.write`) |
| `Sources/NIOChatServer` | 15 (8 on `channelActive`, 7 on `channelRead`) |
| `Sources/NIOHTTP1Server` | 24 (2 `handleFile` body catches + 22 `Unannotated`) |

Total scoped: **40 diagnostics**. Over the 30-diagnostic audit
cap, so decomposition-only per the template.

Scoped strict-mode diagnostics decompose into two classes:

- **2 × body-inference catches** (`handleFile`, carried from Run A).
- **38 × `Unannotated In Strict Replayable Context`** on callees
  whose effect cannot be resolved from a single-target scope:
  NIO framework primitives (`write`, `writeAndFlush`,
  `wrapOutboundOut`, `unwrapInboundIn`, `writeString`,
  `writeBuffer`), ByteBuffer mutators (`clear`, `slice`, `buffer`),
  HTTPHeaders mutators (`add`), Swift stdlib types
  (`ObjectIdentifier`, `String.starts`), DispatchQueue primitives
  (`async`), and example-local state-machine methods
  (`requestReceived`, `requestComplete`, `dynamicHandler`,
  `chopPrefix`, `httpResponseHead`, `completeResponse`, `handler`
  closure invocation).

None of these are adoption-gap candidates — they are "adopter
should annotate their own code, and the framework should
annotate its public surface" situations. On the full corpus,
all of them resolve and go silent.

## The scoped-vs-full-corpus divergence (the round's primary finding)

Full-corpus scans return 0 diagnostics in **both** modes while
scoped scans reproduce the prior round's counts almost exactly
(2 replayable, 24 strict — vs prior 2 and 24). This is not a
measurement artefact. The inference pass reasons differently when
the full module graph is visible:

- **Scoped scan.** NIOHTTP1Server's `handleFile` body sees calls
  to NIOPosix / NIOFileSystem functions that aren't in scope;
  conservative inference resolves to `non_idempotent`. Every
  NIO-framework callee inside `channelRead` is `unknown` (never
  declared, body unreachable from the scoped source set), which
  strict mode flags as `Unannotated`.
- **Full-corpus scan.** Those same callees are now reachable.
  Body inference walks their definitions. None of them contain a
  trigger name (`send`, `insert`, `create`, `update`, `post`,
  `enqueue`, etc.), so each resolves to `idempotent`. Once
  inferred, they are no longer "unannotated" under strict mode
  — the catches evaporate. `handleFile` itself re-resolves the
  same way: its internals inferred idempotent, its aggregate
  inferred idempotent, the channelRead catch withdrawn.

**This means inference quality is scope-dependent in a
consequential way.** An adopter running the linter on a single
example folder gets noisy strict-mode output; running on the
full monorepo gets clean output. The result is not conservative
vs. permissive — the full-corpus result is *more* correct
because the inference sees more code.

Adoption-guidance consequence: scoped scans are not a reliable
preview of the full-corpus outcome. A scoped sample is the wrong
signal for "is my annotation safe to ship?" The recommended
practice is to run the linter against the full repo once (even
if the concern is a single new handler) and rely on the
multi-module inference.

## What DIDN'T fire on NIO's vocabulary

Carried over from the prior round for completeness — the per-file
heuristic trigger inventory on `channelRead` shows:

Callees inside `HTTPHandler.channelRead`:
- `Self.unwrapInboundIn(data)` — NIO generic-dispatch unwrap
- `self.handler(context, reqPart)` — closure invocation
- `self.dynamicHandler(request:)` — helper
- `request.uri.chopPrefix(...)` — String extension
- `self.state.requestReceived()` — state-machine mutation
- `self.buffer.clear()` — ByteBuffer mutation
- `self.buffer.writeString(...)` — ByteBuffer append
- `responseHead.headers.add(...)` — HTTPHeaders mutation
- `Self.wrapOutboundOut(response)` — NIO generic-dispatch wrap
- `context.write(...)` — channel write
- `self.state.requestComplete()` — state-machine mutation
- `self.buffer.slice()` — ByteBuffer read
- `self.completeResponse(...)` — helper

None match the bare-name `non_idempotent` heuristic (`create`,
`insert`, `append`, `publish`, `enqueue`, `post`, `send`, `stop`,
`destroy`, `update`). The `append` keyword is on our list, but NIO
consistently uses `writeX` rather than `.append` on ByteBuffer
(`writeString`, `writeBuffer`, `writeInteger`), so even the
potential overlap doesn't materialise.

The three additional handlers added in this round confirm the
same pattern:
- `EchoHandler.channelRead` — `context.write` only.
- `ChatHandler.channelActive` — `writeToAll`, `writeAndFlush`,
  `wrapOutboundOut`, `writeString`, `ObjectIdentifier`, `async`.
- `ChatHandler.channelRead` — `ObjectIdentifier`, `unwrapInboundIn`,
  `writeString`, `writeBuffer`, `async`, `filter`, `writeToAll`.

Zero of the ~30 distinct callee identifiers across all four
handlers match the bare-name heuristic. **NIO's vocabulary
mismatch reproduces at 100%.**

## The `handleFile` catches — semantically correct, contextually wrong

The prior round flagged this and the framing still holds:
`handleFile` genuinely writes bytes and has observable side
effects, so "body inference says non_idempotent" is defensible
taken out of context. But **NIO does not retry `channelRead`** —
the method is called at most once per received HTTP chunk; TCP
retransmission lives below NIO, and HTTP retry semantics live
above (adopter-layer). The `@lint.context replayable` annotation
is a **lie at the NIO level**, so any catches are architecturally
misapplied.

What this round adds: on the full corpus, `handleFile` itself is
no longer inferred as `non_idempotent` because its NIOPosix/
NIOFileSystem internals now resolve. So the catch that the
scoped scan produces — and the prior round relied on — is
already withdrawn by full-corpus inference. **The annotation is
still a lie, but the linter no longer punishes it.** Adopters
mistakenly annotating NIO-layer code get silent output, which
is also wrong, but in a less-noisy way.

## Comparison to prior adopter rounds

| Round | Target | Replayable | Strict | Note |
|---|---|---|---|---|
| 1 | hummingbird-examples/todos-fluent | 4 | 6 | framework-catchable, sliceable |
| 2 | pointfreeco | 6 | 38 | adopter-local + 2 genuine bugs |
| 3a | swift-nio (scoped, prior round) | 2 | 24 | rescope artefact — scoped scan only |
| **3b** | **swift-nio (full corpus, this round)** | **0** | **0** | **cleaner null than 3a** |
| 4 | TCA (post-PR #18) | 0 | 11 | 3-of-3 via PR #18 closure param |
| 5 | swift-aws-lambda-runtime (post-slot-10) | 0 | 11 | 5-drop after slot 10 |

swift-nio full-corpus is now the **cleanest** null result in the
round set. The design claim ("NIO is the wrong target") is
reinforced, not just by the heuristic-miss story the prior round
told, but by the *inference pass itself* concluding "everything
in scope here is idempotent, nothing to flag."

## Pre-committed questions — answered

Compact answers; full retrospective lives in
[`trial-retrospective.md`](trial-retrospective.md).

1. **Full-corpus scan bounded time?** Yes — ~95s, unchanged between
   replayable and strict. Wall-clock budget not triggered. Slot 5
   stays deferred.
2. **Full-corpus aggregates vs scoped sums?** Different, not equal.
   Scoped sum (Run A: 2, Run B: 40) collapses to 0 when run as a
   single full-corpus scan. The inference pass resolves more with
   more code visible — not a dropped-signal bug, an inference-
   quality improvement.
3. **Heuristic vocabulary mismatch reproduces?** Yes. Zero of ~30
   distinct callee identifiers across four handlers match the
   bare-name heuristic. "Wrong target" is structural to NIO's
   vocabulary, not specific to one example.
4. **New cross-adopter slice candidates?** **None.** Null-result
   framing holds.

## Next-slice candidates

**None.** As in the prior round, this is a null-result round by
design and the null holds.

The one **adoption-guidance** finding worth flagging (the
scoped-vs-full-corpus divergence) is not a slice — it's documentation.
The road-test plan and the README already say to run the linter
from the repo root, and the Lambda round's multi-package recipe
is the only counterexample. This finding strengthens that
guidance without requiring code changes.
