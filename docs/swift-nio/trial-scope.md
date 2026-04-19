# swift-nio — Trial Scope

Third adopter round. **Expected null-result target** per the
design proposal:

> "SwiftNIO is explicitly called out as the wrong target
> (reference-type handlers, runtime enforcement already in
> place, below the business-logic layer)."
> — [`CLAUDE.md`](../../CLAUDE.md) "Validation Target" section

The round exists to confirm the claim empirically, not to surface
new linter slices.

## Research question

> "When an NIO-layer channel handler is annotated `@lint.context
> replayable`, does the linter produce catches that are
> semantically defensible at the byte-mutation level, or does
> NIO's API vocabulary diverge enough from the heuristic
> vocabulary that the round is effectively a null result?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `deb5b44`
  (post-PR-15; includes all Fluent / Hummingbird / non-Fluent
  update* slices).
- **Target:** `apple/swift-nio` @ tag `2.79.0`, shallow-cloned
  to `/Users/joecursio/xcode_projects/swift-nio`. 258 Swift
  source files across 40+ modules.
- **Annotation target:** `Sources/NIOHTTP1Server/main.swift` —
  the HTTP/1.1 echo-style server example. Single-file example
  target; scanning is scoped to this directory only (see
  "Scoping" below).
- **Trial branch:** `trial-swift-nio` forked from `2.79.0`.
  Local-only, not pushed.

## Scoping — full-corpus scan did not complete

An initial scan against the full `swift-nio` repo did not
complete within a 27-minute observation window. Three concurrent
`swift run CLI` invocations were pegged at 100% CPU with empty
output files; this may have been contention between the
concurrent runs rather than a pathological single-process case,
but the observation is recorded here as-is. All measurements in
this round use a **scoped scan** of
`Sources/NIOHTTP1Server/` (the single-file example) so the round
stays bounded. A follow-up round could attempt a single clean
full-corpus scan; not a blocker for the null-result question.

## Annotation plan

One annotation:

1. `HTTPHandler.channelRead(context:data:)` — the class's
   `ChannelInboundHandler` conformance's main request-processing
   method. Reference-type handler (class, not struct) that
   mutates `self.handler`, `self.state`, `self.buffer`, and
   performs `context.write(...)` / `context.writeAndFlush(...)`
   side effects per request chunk.

`/// @lint.context replayable` for Run A, flipped to
`strict_replayable` for Run B.

## Scope commitment

- **Measurement only.** No linter changes this round. The
  hypothesis says no changes are warranted.
- **One-file annotation campaign.** Deliberately narrow — the
  point is confirming the design claim, not producing a rich
  measurement surface.
- **Throwaway branch, not pushed.**

## Pre-committed questions for the retrospective

1. Do the heuristic name-based triggers fire at all on NIO's
   API vocabulary (`write`, `writeAndFlush`, `wrapOutboundOut`,
   `completeResponse`, `channelRead`, `flush`, `add`, `clear`)?
2. Does body-based upward inference produce catches in NIO-layer
   code, even when the name-based heuristic stays silent?
3. Does the round produce any new cross-adopter slice candidates,
   or does it confirm "NIO is the wrong target" without surfacing
   new gap work?
4. What, if anything, should change about the CLAUDE.md guidance
   based on the measurement?
