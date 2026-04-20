# swift-nio — Trial Scope

Slot-8 remeasurement of the swift-nio adopter round. The original
round (April 2026, linter SHA `deb5b44`) **could not complete a
full-corpus scan** — three concurrent invocations were pegged at
100% CPU for 27+ minutes — and was rescoped mid-stream to a single
example directory. PR #16 (wall-clock budget on the inference
fixed-point loop) shipped as the immediate response. Slot 8 of
`../next_steps.md` flagged a clean full-corpus remeasurement as
cheap-to-do and worth closing the loop on.

This document **overwrites** the prior round's scope per the
project-named-dir convention; git history carries the audit trail.

The expected outcome is unchanged: per `../../CLAUDE.md`'s
validation-target guidance, "SwiftNIO is explicitly called out as
the wrong target (reference-type handlers, runtime enforcement
already in place, below the business-logic layer)." A null result
on the full corpus would confirm the claim with sharper data than
the prior single-file scoped scan.

## Research question

> "With the PR #16 wall-clock budget in place, does a full-corpus
> SwiftNIO scan complete in bounded time, and do the four
> annotated example handlers (echo / chat / HTTP1) produce
> measurably different aggregate diagnostics than the prior
> single-handler scoped scan?"

## Pinned context

- **Linter:** `Joseph-Cursio/SwiftProjectLint` @ `main` at `6c611c7`
  (post-slot-10 — Lambda response-writer framework whitelist).
  Includes PR #16 (wall-clock inference budget, default 30s).
- **Upstream target:** `apple/swift-nio` @ tag `2.98.0` (April 2026
  stable tip, 549 Swift source files across 43 modules).
- **Fork:** `Joseph-Cursio/swift-nio-idempotency-trial`,
  pre-provisioned and hardened (issues / wiki / projects disabled).
- **Trial branch:** `trial-swift-nio` on the fork, default-branch
  switched. Fork-authoritative — scans run against a fresh clone of
  the fork, not an ambient checkout.
- **Build state:** not built — SwiftSyntax-only scan, no SPM
  resolution required on the adopter.

## Annotation plan

Four handlers across three example targets, chosen for shape
diversity within NIO's ChannelInboundHandler vocabulary. None of
these is genuinely in a replayable retry context (NIO does not
retry channelRead; TCP retransmission lives below NIO and HTTP
retry semantics live above) — but **annotation correctness is not
the round's concern**. The point is measuring whether the
heuristic and inference paths fire on NIO-shaped code, regardless
of whether the catches would be actionable.

| # | File | Handler | Shape |
|---|------|---------|-------|
| 1 | `Sources/NIOEchoServer/main.swift:21` | `EchoHandler.channelRead` | Pure read-echo. Single `context.write(...)`. Smallest possible body — minimum-fire baseline. |
| 2 | `Sources/NIOChatServer/main.swift:56` | `ChatHandler.channelActive` | Registration-with-broadcast. Mutates a shared `[ObjectIdentifier: Channel]` dictionary inside a serial queue, broadcasts via fan-out, plus an inline `context.writeAndFlush`. Branch-heavy by Dispatch closure. |
| 3 | `Sources/NIOChatServer/main.swift:92` | `ChatHandler.channelRead` | Broadcast fan-out. ByteBuffer construction + `writeString`/`writeBuffer`, then `writeToAll` loop calling `writeAndFlush` on each connected channel. The fan-out shape that's most analogous to webhook-broadcast adopter patterns. |
| 4 | `Sources/NIOHTTP1Server/main.swift:518` | `HTTPHandler.channelRead` | Rich HTTP request handling. Switch-routed to `handleFile` / `handleEcho` / `handleInfo` / `handleJustWrite`. Carried over from the prior round so the handleFile body-inference catches are directly comparable. |

`/// @lint.context replayable` for Run A, flipped to
`strict_replayable` for Run B.

Shape coverage:

- **Pure read-echo:** #1.
- **Registration / broadcast:** #2.
- **Fan-out broadcast:** #3.
- **Branch-routed switch:** #4.

Deliberately excluded:

- The `NIOTCPEchoServer` and `NIOWebSocketServer` async-channel
  handlers. These use `NIOAsyncChannel` rather than
  `ChannelInboundHandler`; a fifth shape isn't worth the
  complexity for a confirm-the-claim round.
- `NIOHTTP1` library handlers (`HTTPServerPipelineHandler`,
  `HTTPServerUpgradeHandler`, etc.). These are NIO-internal,
  not example-shaped — annotating them would conflate
  "adopter-layer measurement" with "library-layer measurement."
- Per-`channelInactive` annotations. The `ChatHandler.channelActive`
  annotation already covers the registration-side write surface;
  inactive's mirror shape adds no new signal.

## Scope commitment

- **Measurement-only.** No linter changes in this round.
- **Source-edit ceiling.** Annotations only — doc-comment form
  `/// @lint.context replayable` on each handler. No logic edits,
  no imports, no new types. README banner identifying the fork
  as a validation sandbox.
- **Audit cap.** 30 diagnostics max per mode. If aggregate
  exceeds 30, decompose by class without per-diagnostic verdicts.

## Pre-committed questions

1. **Does the full-corpus scan complete in bounded time post PR #16?**
   The prior round's scoped-scan rescue makes this the round's
   primary structural question. If yes, slot 5 (real perf fix on
   the inference loop) loses immediate triggering evidence and
   stays deferred. If the scan completes but diagnostics differ
   suspiciously from the scoped runs (e.g., zero where the prior
   round had non-zero), the wall-clock budget is masking a
   correctness issue and slot 5 promotes to the next session.

2. **Do full-corpus aggregates differ from per-handler scoped scans?**
   Scoping the prior round to one directory was a measurement
   compromise. With four annotated handlers across three targets
   in one corpus, the aggregate should equal the sum of the
   per-handler scopes — otherwise something about the multi-target
   walk is dropping signals.

3. **Does the heuristic vocabulary mismatch reproduce?** The prior
   round documented that NIO's `write` / `writeAndFlush` /
   `wrapOutboundOut` / `slice` / `clear` vocabulary doesn't trigger
   the bare-name heuristic. Confirming this on three additional
   handlers raises confidence that "wrong target" is structural
   to the framework, not specific to one example file.

4. **Any new cross-adopter slice candidates?** The expected answer
   is "no" — this round's purpose is closing the loop, not
   surfacing new gaps. If the answer is "yes," document the gap
   and downgrade the round's null-result framing.
