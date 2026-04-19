# Trial Round 3: Swift Idempotency Linter vs. an application-scale Swift codebase

Companion plan to [`claude_phase_1_plan.md`](claude_phase_1_plan.md) (round 1 — `apple/swift-aws-lambda-runtime`) and [`claude_phase_1_round_2_plan.md`](claude_phase_1_round_2_plan.md) (round 2 — `hummingbird-project/hummingbird`). Round 3 road-tests the **same** post-follow-up Phase 1 linter against a third codebase — an **application**, not a framework or runtime — before making any further changes to the linter or moving on to Phase 2.

## First: correcting the round-2 retrospective's framing of pointfreeco

Round 2's retrospective named three round-3 candidate targets. For pointfreeco specifically, it said:

> "This would exercise the externallyIdempotent tier, IdempotencyKey strong type, and #assertIdempotent macro — all of which round 2 left untouched."

**That framing is wrong.** Those three features are **Phase 2 deliverables that don't exist in code.** The scope commitment across rounds 1 and 2 explicitly lists them as out of scope:

- `externallyIdempotent` tier → not in the lattice today
- `IdempotencyKey` strong type → not declared anywhere
- `#assertIdempotent` macro → not built
- `@Idempotent` macro → not built

Running round 3 on pointfreeco with today's linter cannot produce signal about features that don't exist. The retrospective wrote past its own scope commitment and named downstream-Phase artefacts as round-3 targets. This plan corrects that before acting on it.

## What round 3 can actually test (given Phase 1 is all that exists)

With the round-2 linter unchanged, three genuinely new research questions are available:

1. **Does parser cleanliness hold at application scale?** Rounds 1 and 2 ran against ~100–140-file corpora. A real application codebase is typically 500–2000+ files. Does `EffectAnnotationParser` misread any doc comment in a corpus an order of magnitude larger? Round 2's Run A held at zero on 137 files — a round-3 zero-on-1000+-files result is a stronger claim.
2. **Can a single objectively-replayable context in real application code produce a meaningful diagnostic when annotated?** Round 2's Run C.2 proved cross-file resolution works on synthetic function pairs. Round 3's equivalent test annotates **one real function that really is replayable in production** (e.g., a Stripe webhook handler, an SES bounce notification handler, a CloudKit push-token refresh handler), and the callees it actually hits. The question: does the linter's output quality in this setting match its output quality on synthetic demos?
3. **Do any new `actorReentrancy` Bucket-B subtypes surface in application actors vs. framework/runtime actors?** Round 1's Bucket B was the state-machine-invariant guard subtype (one subtype, three findings). Round 2 produced zero findings. Application actors — session caches, request-coalescing caches, debounce controllers — may or may not share round 1's subtype. A new subtype would refine OI-1; absence of new subtypes strengthens round 1's one-subtype claim.

Round 3 is **not** a Phase 2 trial. Phase 2 requires Phase 2 code. This is still a Phase 1 generalization test — now across three points on the codebase-type axis (serverless runtime, HTTP-server framework, real application).

## Target selection

### The three options from the retrospective, honestly assessed

| Target | Retrospective claim | Honest assessment |
|---|---|---|
| **`pointfreeco/pointfreeco`** | "Would exercise externallyIdempotent, IdempotencyKey, #assertIdempotent" | **False as stated.** Correct claim: it's the only publicly-verifiable application-scale Swift codebase with real webhook handlers. It does *not* exercise the Phase-2 features named. |
| `vapor/vapor` | "Actor-heavy, non-runtime" | **Self-contradicts the retrospective.** Vapor is a framework; the retrospective's closing sentence explicitly rules out another framework. |
| `swift-server/async-http-client` | "Stresses actorReentrancy hardest" | **Also a framework** (client library). Correctly framed as "lowest information gain per day" in the retrospective itself. |

### Additional candidate — not in the retrospective

The user has several local repos that might fit "a small internal microservice or application":

- `/Users/joecursio/xcode_projects/Sitrep` — open-source Swift tool (lint-adjacent)
- `/Users/joecursio/xcode_projects/MacCloud_server` — name suggests a server; unknown codebase
- `/Users/joecursio/xcode_projects/MacCloud_client_iOS` and `MacCloud_client_MacOS` — client apps
- `/Users/joecursio/xcode_projects/MusicStore` — unknown

These are candidate targets **only if the user wants to volunteer one.** Without knowing their size, state, and whether they exercise replayable contexts, they can't be recommended sight-unseen. The author does not pick a target from the user's private repos uninvited.

### Recommendation: `pointfreeco/pointfreeco`

Three reasons, with the framing corrected:

1. **Only application-class Swift codebase that's publicly verifiable.** Both prior trials were library/runtime code. The single biggest axis round 3 can move along is "framework vs. real application." pointfreeco is the clean choice.
2. **Real replayable contexts exist.** pointfreeco is a Stripe-integrated subscription site. Stripe webhooks are **objectively at-least-once** — Stripe explicitly retries on non-2xx responses. The site's Stripe webhook handler is a real `@context replayable` target in the same way Lambda SQS handlers were in round 1. Annotating it is not speculative.
3. **Order-of-magnitude corpus size.** pointfreeco is 500+ Swift files across multiple SPM targets. Running the linter there answers the parser-scaling question that rounds 1 and 2 could not.

### Fallback

If pointfreeco's toolchain (Swift version, compiler flags, deprecated syntax) is incompatible with SwiftSyntax 602 — check at Phase 0 — fall back to `swift-server/async-http-client` at its latest tag. The retrospective correctly flagged its low-info-per-day profile, but it's at least Phase-1-linter-compatible by virtue of being a modern swift-server project. Vapor is **not** a valid fallback (same "another framework" objection the retrospective raised).

## Scope commitment (unchanged from round 2)

Everything on rounds 1–2's out-of-scope list still applies. Specifically:

- Still out of scope: effect inference, all Phase-2 tiers (`externallyIdempotent`, `transactional_idempotent`, `pure`, etc.), all macro/protocol work (`@Idempotent`, `IdempotencyKey`, `IdempotencyTestable`, `#assertIdempotent`), all suppression grammar, strict mode, `@lint.assume`, `@lint.unsafe`.
- **No rule changes on the trial branch.** Carry round 2's "pure measurement round" guardrail forward. Any issue surfaced → recorded as an Open Issue in the proposal, not fixed on `idempotency-trial-round-3`. Parser bugs remain the one carve-out.
- **No signature-aware collision fix.** Round 2 surfaced this as a deferred refinement; it is **not** pulled forward into round 3. Keeping it deferred means round 3 measures the same linter as round 2, which is the only way the generalization claim is meaningful.
- **Local-only annotation experiments.** Same policy as round 2: throwaway branch in the target clone, don't push, don't fork upstream.

## Phases

Linter and fixtures are already built. Same phase-numbering parallel to rounds 1 and 2:

### Phase 0 — Prep (≈0.5 day)

- On primary machine: `cd /Users/joecursio/xcode_projects/SwiftProjectLint && git checkout idempotency-trial-round-2 && git pull && swift package clean && swift test`. Baseline must still be green (expected: 1844 tests / 251 suites / 0 known issues).
- Create branch: `git checkout -b idempotency-trial-round-3 && git push -u origin idempotency-trial-round-3`. Forked from the round-2 tip (no code delta between rounds).
- Clone `pointfreeco/pointfreeco` at its latest stable tag (or `main` at a pinned SHA — pointfreeco does not tag releases in the traditional sense; pin by commit SHA). Local clone at `/Users/joecursio/xcode_projects/pointfreeco`. Record the SHA.
- **Toolchain-compatibility spot-check.** pointfreeco has historically been aggressive about Swift version bumps. Before committing, verify the clone's `Package.swift` swift-tools-version is ≤ 6.1 and that `swiftc -version` matches. If the clone requires a toolchain we don't have, pivot to async-http-client per fallback plan.
- Write `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase1-round-3/trial-scope.md` — mirrors round-2 scope doc with pointfreeco-specific target details and the corrected research questions above.

**Acceptance:** green baseline; pinned clone; toolchain compatible; branch pushed; scope note committed.

### Phases 1 & 2 — SKIPPED

Linter and fixtures already built and passing. No changes on this branch.

### Phase 3 — Positive demonstration on a webhook-shaped handler (≈0.5 day)

Round 1's demo was Lambda-shaped. Round 2's demo was Hummingbird-route-shaped. Round 3's demo is **webhook-shaped** — the most production-relevant shape of "replayable by upstream retry."

- Extend `/Users/joecursio/xcode_projects/swift-hummingbird-idempotency-demo/` — **or** create a sibling `swift-webhook-idempotency-demo`. Recommend the sibling: cleaner separation, keeps the round-2 demo frozen.
- Handler annotated `/// @lint.context replayable` taking a (stubbed) Stripe webhook event. Before state: calls `billing.applyCharge(...)` (`@lint.effect non_idempotent`) + a `logger.info` (observational). After state: call routed through `billing.applyChargeIdempotent(event.id, ...)` (`@lint.effect idempotent`).
- Acceptance: before → 1 diagnostic on the charge call, 0 on the logger; after → 0 diagnostics. Transcripts into `docs/phase1-round-3/trial-transcripts/`.

### Phase 4 — False-positive baseline on pointfreeco (≈1 day)

**Run A — full pointfreeco, no annotations.**

```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
```

Expected: **zero diagnostics**. Round 3's key parser-scaling claim: zero on a 500+-file corpus. Any non-zero is a parser bug; same carve-out as round 2.

**Run B — structural `actorReentrancy` on pointfreeco.**

```
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories codeQuality --threshold warning
```

Filter to `actorReentrancy`. Triage each finding into A/B/C buckets per rounds 1 and 2. **Specifically look for new Bucket-B subtypes** beyond round 1's state-machine-invariant pattern. Application actors (session caches, rate limiters, request-coalescing caches) may produce distinct AST-match/design-intent mismatches that the rule can't distinguish. Any new subtype feeds OI-1.

**Run C — annotate one real replayable context.**

On a throwaway branch of the pointfreeco clone (`trial-annotation-local`, don't push):

1. Locate the Stripe webhook handler (likely under a path like `Sources/App/Routes/Webhooks.swift` or similar). Annotate its entry function `/// @lint.context replayable` with a comment citing Stripe's retry policy.
2. Identify 2–3 functions that handler calls which mutate persistent state (e.g., inserting a subscription record, charging a card, sending a confirmation email). Annotate each `/// @lint.effect non_idempotent` — these annotations should be **honestly correct**, not invented to produce diagnostics.
3. Re-run `--categories idempotency`. Count diagnostics.

This is the only round of the three trials that exercises annotations on **real, not synthetic, replayable code.** The result is the strongest single piece of "would this be useful in practice?" evidence the trial record can produce.

Expected shapes:

- Best case: N diagnostics (one per non-idempotent callee) that read as genuinely informative. Evidence for adoption.
- Middle case: some diagnostics fire, some don't — triage per run C.1 vs. C.2 in round 2. Collision policy may again suppress protocol-method calls; if so, that's the same OI-4 refinement candidate as round 2, now surfaced a second time (evidence strengthens the case for the fix).
- Worst case: zero diagnostics despite annotations on caller and callees — would indicate a parser or resolver bug that rounds 1 and 2 missed. Unlikely but recordable.

**Run D — observational tier in real application middleware context.**

Identical in structure to round 2's Run D, but: pick 2–3 real middlewares or controller methods in pointfreeco that already call `logger.info` / metrics primitives. Annotate those middleware functions `/// @lint.context replayable` and declare the specific logging/metrics entry points as `/// @lint.effect observational` via local wrapper functions (same wrapper-shim pattern as round 2 — pointfreeco likely uses swift-log directly, which can't be annotated in-place without `@lint.assume`).

Expected: zero false positives on the observational calls in a real-code setting (not just the synthetic 5-callers × 20-call-sites round-2 setup). Same verdict criteria as round 2.

### Phase 5 — Write-up (≈0.5 day)

Three artefacts, under `docs/phase1-round-3/`:

1. **`trial-findings.md`** — counts per rule, triaged `actorReentrancy` buckets with **delta table vs. rounds 1 and 2** (three columns now, not two), quoted Run C diagnostics from the real webhook handler annotation, parser-scaling verdict for Run A.
2. **Updates to `../idempotency-macros-analysis.md` Open Issues section** — only if round 3 surfaces patterns rounds 1 and 2 did not. OI-4's collision-fix case strengthens if protocol-name collisions appear in pointfreeco. New Bucket-B subtypes under OI-1 if found.
3. **`trial-retrospective.md`** — one page. Two specific questions to answer:
   - "After three trials, is Phase 1 defensible for adoption?" The answer determines whether Phase 2 work can start.
   - "Was the round-2 retrospective's framing of pointfreeco actually useful, or did it waste a round?" If pointfreeco turned out to surface nothing rounds 1–2 hadn't, flag the cost of trusting a retrospective's speculative next-target framing. The correction at the top of this plan is the prior art; the retrospective tests whether the correction was also right.

**Acceptance:** user can answer "is Phase 1 ready to ship, and what are the two or three concrete refinements that would most improve it?" with evidence from three codebases.

## Verification end-to-end

```
cd /Users/joecursio/xcode_projects/SwiftProjectLint
git checkout idempotency-trial-round-3 && git pull
swift package clean && swift test                        # 1844+ tests green, unchanged from round 2

# Phase 3 webhook demo
cd /Users/joecursio/xcode_projects/swift-webhook-idempotency-demo
swift run --package-path ../SwiftProjectLint CLI . --categories idempotency
# Expect 1 diagnostic (before) or 0 (after).

# Phase 4 Runs A, B (on pointfreeco, un-annotated)
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
# Expect zero.
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories codeQuality --threshold warning
# Triage actorReentrancy subset.

# Phase 4 Run C: after annotating the real webhook handler on throwaway branch
swift run --package-path /Users/joecursio/xcode_projects/SwiftProjectLint CLI \
  /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
# Expect N diagnostics where N = non-idempotent callees annotated
```

## Critical files

- `/Users/joecursio/xcode_projects/SwiftProjectLint` @ `idempotency-trial-round-3` — linter, branched from round 2 tip with zero code delta
- `/Users/joecursio/xcode_projects/pointfreeco` — target, pinned SHA (pointfreeco doesn't version-tag; pin by commit)
- `/Users/joecursio/xcode_projects/swift-webhook-idempotency-demo/` — new Phase-3 demo (webhook-shaped)
- `/Users/joecursio/xcode_projects/swiftIdempotency/docs/phase1-round-3/` — deliverables folder

## Total estimated effort

Phase 0: 0.5 day • Phase 3: 0.5 day • Phase 4: 1 day • Phase 5: 0.5 day • **~2.5 days, budget 3.5 with slack.** Same as round 2. Run C annotating real code is the biggest time investment and the phase where the most can go wrong (pointfreeco's actual layout and dependency graph may differ from what this plan assumes).

## What a clean round 3 unlocks

If round 3 reproduces the parser-cleanliness result at 5–10× corpus size, and if Run C produces an informative diagnostic count on a real replayable handler, Phase 1 is validated on three stylistically different codebases (runtime, framework, application). At that point:

- Phase 1 is shippable for adoption with confidence.
- The two or three concrete refinements (signature-aware collision policy; architecture-dependent rule-value adoption note; any new Bucket-B subtype surfaced) can be implemented as separate, small, focused commits — not as a trial-branch mix.
- Phase 2 work (`externallyIdempotent`, `IdempotencyKey`, `#assertIdempotent`, `@Idempotent` macro) becomes the next meaningful prize. The road-test for Phase 2 is categorically different — it requires Phase 2 code to exist before testing can start.

If round 3 produces surprises (new parser bug, new Bucket-B subtype, collision policy failing in a new way), those get recorded, and the "three-codebase validation" claim gets qualified accordingly. Honest outcomes either way.
