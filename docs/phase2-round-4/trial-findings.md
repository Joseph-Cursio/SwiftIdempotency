# Round 4 Trial Findings — Phase 2.1 (externally_idempotent + missingIdempotencyKey) vs. `pointfreeco/pointfreeco`

First measurement round to validate **Phase 2** features on a real codebase. Scope was fixed in advance by [`trial-scope.md`](trial-scope.md). Retrospective in [`trial-retrospective.md`](trial-retrospective.md). This report is strictly descriptive.

## Test vehicle

- **Linter:** `SwiftProjectLint` @ `main` SHA `2c1c702` (post-`missingIdempotencyKey`). No branching, no code changes — measurement-only.
- **Target:** `pointfreeco/pointfreeco` @ SHA `06ebaa5276485c5daf351a26144a7d5f26a84a17`, swift-tools-version 6.3.
- **Trial branch:** `trial-annotation-phase2-local` in the pointfreeco clone, forked from round 3's `trial-annotation-local`. Not pushed.
- **Baseline:** 1890 tests across 256 suites, verified green at Phase 0.
- **Corpus shape unchanged from round 3:** 918 Swift source files, 74,588 lines, zero actors.

## Source modifications (per scope doc)

Three categories of edit on the throwaway branch:

1. **`Sources/PointFree/Gifts/GiftEmail.swift`** — effect-annotation tier changed from `non_idempotent` (round 3's Phase-1 choice) to `externally_idempotent` (Run B) and `externally_idempotent(by: idempotencyKey)` (Runs C and later). An `idempotencyKey: String` parameter added to `sendGiftEmail(for:)` for the `(by:)` qualifier to name. Parameter is not consumed in the body — trial scaffolding.
2. **`Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift`** — the single call site of `sendGiftEmail` updated to pass the key. Two variants used across Runs C.1 / C.2.
3. **`Sources/PointFree/Webhooks/TrialPhase2Anti.swift`** — new file (Run D) with six intentional violations and two documented-limitation negatives. No edits to existing pointfreeco code.

No other files touched. Every edit is a scope-doc-listed category.

## Phase 4 Run A — parser cleanliness at Phase 2.1

On pointfreeco with `PaymentIntentsWebhook.swift` and `GiftEmail.swift` temporarily reverted to their pinned-SHA state (unannotated):

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
No issues found.
```

**Zero diagnostics on 918 files.** The Phase-2.1 grammar extension — the new `(by: paramName)` qualifier — did not misread any doc comment on this corpus. Delta vs round 3's Run A: **0 → 0**. Parser cleanliness claim generalises to the extended grammar. Transcript: [`trial-transcripts/runA.txt`](trial-transcripts/runA.txt).

## Phase 4 Run B — the disappearing diagnostic

Restored round-3's three `@lint.context replayable` annotations on the webhook chain. Changed only the `sendGiftEmail` tier from `non_idempotent` → `externally_idempotent` (documentary, no `(by:)`). Everything else identical to round 3.

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
No issues found.
```

**Zero diagnostics. Round 3 produced one.**

### Delta

| | Round 3 | Round 4 Run B |
|---|:-:|:-:|
| `nonIdempotentInRetryContext` on `handlePaymentIntent → sendGiftEmail` | **1** | **0** |
| Annotation on `sendGiftEmail` | `@lint.effect non_idempotent` | `@lint.effect externally_idempotent` |
| Lattice row consulted | `replayable → non_idempotent` | `replayable → externally_idempotent` |
| Lattice verdict | violation | trust key routing (future-verified) |

This is **the headline round-4 finding.** Round 3's one real-code diagnostic was a phase-appropriate artifact — Phase 1 had only two tiers to describe `sendGiftEmail` (`idempotent` was dishonestly permissive; `non_idempotent` was honest but over-restrictive). Phase 2's three-way tier distinction gives teams the correct intermediate position: "keyed-idempotent if routed correctly," which the lattice trusts and the `missingIdempotencyKey` rule then verifies when the key-routing parameter is present.

### Adoption-education takeaway

Teams migrating from Phase-1 annotations to Phase-2 tiers should expect some diagnostics to disappear as they pick the more-accurate tier. **This is correct behaviour, not a regression.** A Phase-1-era `@lint.effect non_idempotent` on a function that is actually keyed-idempotent-capable should be upgraded to `@lint.effect externally_idempotent(by: ...)`, and the previously-fired retry-context violation should silence because the lattice no longer considers it a violation.

The implication: the *count* of findings is not a monotonic measure of adoption progress. A team can be strictly *more* correct after an annotation-tier refinement that reduces their diagnostic count to zero.

Transcript: [`trial-transcripts/runB.txt`](trial-transcripts/runB.txt).

## Phase 4 Run C — verifier on real code

Added `idempotencyKey: String` parameter to `sendGiftEmail`. Updated its annotation to `@lint.effect externally_idempotent(by: idempotencyKey)`. Updated the call site in `handlePaymentIntent`.

### Run C.1 — stable key (`gift.id.uuidString`)

```swift
_ = try await sendGiftEmail(idempotencyKey: gift.id.uuidString, for: gift)
```

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
No issues found.
```

**Zero diagnostics.** `gift.id.uuidString` is a `MemberAccessExprSyntax` chain rooted at a function parameter — opaque to the rule's narrow-and-precise design. The rule cannot prove `gift.id` is stable across retries (that would need data-flow analysis), but it also has no reason to flag it. Happy-path confirmation on real production code. Transcript: [`trial-transcripts/runC1.txt`](trial-transcripts/runC1.txt).

### Run C.2 — unstable key (`UUID().uuidString`)

```swift
_ = try await sendGiftEmail(idempotencyKey: UUID().uuidString, for: gift)
```

```
$ swift run CLI /Users/joecursio/xcode_projects/pointfreeco --categories idempotency
Sources/PointFree/Webhooks/PaymentIntentsWebhook.swift:68: error: [Missing Idempotency Key] Idempotency-key argument to 'sendGiftEmail' is derived from `UUID()` (`.uuidString` of a fresh value): each invocation produces a different key, so retries do not converge. The key must be derived from a stable upstream identifier that is the same on replay.
  suggestion: Route a stable upstream identifier into the `idempotencyKey:` argument — e.g. an event ID, request ID, or message ID received from the caller. If no such identifier is available, consider weakening 'sendGiftEmail' to `@lint.effect non_idempotent` or introducing a deduplication guard at this site.

Found 1 issue (1 error)
```

**Exactly one diagnostic**, on `PaymentIntentsWebhook.swift:68` — the real production line — with the Phase-2.1 rule prose naming `sendGiftEmail`, citing `idempotencyKey:` as the parameter, identifying `UUID()` as the cause, and offering the tier-aware remediation suggestion.

This is the **adoption-story confirmation.** The only thing distinguishing a legitimate production adoption from this trial is that `sendGiftEmail`'s body would actually route the key to Mailgun — a change outside the linter's scope. Everything the linter can verify, it verified. Transcript: [`trial-transcripts/runC2.txt`](trial-transcripts/runC2.txt).

## Phase 4 Run D — anti-pattern injection

On the stable-key variant (Run C.1 state), added `Sources/PointFree/Webhooks/TrialPhase2Anti.swift` with six intentional violations and two documented-limitation negatives.

### Expected vs. observed

| Case | Shape | Expected line | Observed | Rule |
|---:|---|---:|---:|---|
| 1 | observational → externally_idempotent | ~40 | line 35 ✅ | `idempotencyViolation` |
| 2 | externally_idempotent → non_idempotent | ~51 | line 48 ✅ | `idempotencyViolation` |
| 3 | `UUID()` at keyed arg | ~65 | line 62 ✅ | `missingIdempotencyKey` |
| 4 | `UUID().uuidString` at keyed arg | ~75 | line 72 ✅ | `missingIdempotencyKey` |
| 5 | `Date.now` at keyed arg | ~85 | line 85 ✅ | `missingIdempotencyKey` |
| 6 | `arc4random()` at keyed arg | ~95 | line 98 ✅ | `missingIdempotencyKey` |
| **Negative 1** | externally_idempotent without `(by:)` + UUID() | silent | silent ✅ | — |
| **Negative 2** | local let-binding of UUID() | silent | silent ✅ | — |

**Six diagnostics total — exactly one per intentional violation.** Zero from the two documented-limitation negatives. Line numbers shifted slightly from my header-comment predictions because the file's actual layout differed from my estimate; that's a minor bookkeeping drift, not a semantic one. The rule identifiers, callee names, parameter names, generator names, and suggestion prose all match the rule doc at `Docs/rules/missing-idempotency-key.md`.

Transcript: [`trial-transcripts/runD.txt`](trial-transcripts/runD.txt).

## Summary

| Run | Expected | Observed | Pass? |
|---|---|---|---|
| Run A (idempotency / un-annotated) | 0 | 0 | ✅ |
| Run B (round-3 annotations, Phase-2 lattice) | 0 (disappearing diagnostic) | 0 | ✅ — key finding |
| Run C.1 (stable key `gift.id.uuidString`) | 0 | 0 | ✅ |
| Run C.2 (unstable key `UUID().uuidString`) | 1 | 1 | ✅ |
| Run D (six injected violations, two negatives) | 6 / 0 | 6 / 0 | ✅ |

## Four-round delta table

| Dimension | Round 1 (Lambda) | Round 2 (Hummingbird) | Round 3 (pointfreeco) | Round 4 (pointfreeco, Phase 2) |
|---|---|---|---|---|
| Target | serverless runtime | HTTP-server framework | real application | same target, Phase 2 features |
| Files | ~100 | 137 | 918 | 918 |
| Swift tools | 6.0 | 6.1 | 6.3 | 6.3 |
| Run A (annotation-gated on un-annotated) | 0 | 0 | 0 | **0** — parser clean at Phase 2.1 grammar |
| `actorReentrancy` | 3 (Bucket B) | 0 | 0 | n/a (not re-run; same corpus as round 3) |
| Cross-file resolution | synthetic | corpus (unique names); protocol-method collision | cross-directory real code | same as round 3 + verifier on keyed arg |
| Real-code diagnostic on annotated webhook | n/a | n/a | **1** (`replayable → non_idempotent`) | **0** (same chain, Phase-2 tier → trusted) |
| Phase-2 `missingIdempotencyKey` on real code | — | — | — | **1** (UUID() at idempotencyKey: in production handler) |
| Phase-2 lattice rows fire on injection | — | — | — | **6/6** (Run D) |

## Findings with proposal implications

None of the four runs surfaced patterns that rounds 1–3 didn't predict. Per the scope doc, no proposal amendments are filed by round 4. The notes below are for the Phase-5 retrospective's use, not proposal-level findings.

### R4-1 — The "disappearing diagnostic" is the expected Phase-2 behaviour

The one Phase-1 diagnostic round 3 produced on real code silences under Phase 2's lattice. Two honest readings coexist:

- **The lattice refinement is correct.** A function that is keyed-idempotent-capable should be tagged `externally_idempotent`, not `non_idempotent`, and the retry-context rule should trust the keyed tier at the lattice level. Run B confirms this end-to-end.
- **Round 3's real-code diagnostic was a phase-appropriate artifact, not a bug catch.** The annotation was honest given Phase-1's two-tier lattice; it became sub-optimal when Phase 2 added the third position. Teams upgrading annotations as Phase-2 lands should expect similar transitions.

This is not an open issue. It's an adoption-education point that the rule docs already cover, but the trial record now validates at corpus scale.

### R4-2 — Adoption story holds end-to-end

Run C.2 is the closest the trial record comes to a real adoption event:

- Real production Swift file, not a synthetic demo.
- Real callee (`sendGiftEmail`) with realistic argument expressions.
- Realistic annotation campaign (four edits total: annotation + parameter + call-site + `(by:)`-qualifier grammar use).
- Real-code diagnostic with prose that a team member could act on without needing to re-read the rule doc.

Every Phase-2.1 design choice that the unit-fixtures couldn't fully validate — prose quality on real callee names, parameter-label matching against real arguments, absence of grammar regressions on production-scale doc-comment volume — holds up in this run. No follow-ups surface.

### R4-3 — What the rule still cannot catch, demonstrated on real code

Run C.1's stable case and Run D's Negative 2 between them document the rule's real limits:

- `gift.id.uuidString` (C.1, member-access chain rooted at a parameter): passes silently. The rule can't verify stability across retries without data-flow analysis. Reasonable silence.
- `let key = UUID().uuidString; call(idempotencyKey: key, ...)` (Negative 2): passes silently. Same limitation — the rule doesn't follow let-bindings.

Both cases are documented in the rule doc's "Known Limitations" section. Run D's real-code Negative 2 promotes this from "synthetic fixture" to "confirmed on realistic webhook-chain layout."

## Conclusion

Phase 2.1 is validated on real production Swift. Every design claim the rule doc makes — lattice rows, tier trust semantics, generator detection, opaque-expression silence, documentary-annotation mode — behaves as specified on the pointfreeco corpus. The "disappearing diagnostic" finding is the one non-obvious adoption-education point; the rule docs already cover it, but having corpus-scale evidence for it strengthens the framing.
