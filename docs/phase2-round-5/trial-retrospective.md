# Round 5 Trial Retrospective

One page. First measurement of the inference machinery on real code. The question it has to answer: does heuristic + upward inference deliver on the round-4 retrospective's claim that it would convert un-annotated corpus runs from "parser-clean but uninformative" to "parser-clean AND catches real things"?

## Did the scope hold?

**Yes, with the anticipated source-modification carve-out.** Zero rule changes on the linter. The edits on pointfreeco: one `@lint.context replayable` in Run B, four more in Run D, one new file (`TrialInferenceAnti.swift`) in Run C. One edit on swift-aws-lambda-runtime for Run E'. Every edit is listed in `trial-scope.md` and categorised in `trial-findings.md`. No `@lint.effect` annotations anywhere on either target — the inference machinery is what was being measured, so effect-annotating would have defeated the purpose.

## Answers to the three pre-committed questions

### (a) Did inference deliver on the R4 retro's "catches real things" claim?

**Partially, and not where it matters most.** The machinery works end-to-end — Run C's 5-positive / 4-negative outcome on the 9-case scaffold demonstrates every inference mode fires with correct provenance and chain depth on a realistic project layout. That is a real validation.

But the intended adoption story — "teams add one `@context replayable` to their webhook entry points and inference catches the rest" — did not materialise. Run B was the test: on the identical webhook chain where round 3 needed four annotations to produce one diagnostic, inference + one annotation produced zero. The `sendGiftEmail → sendEmail → mailgun.sendEmail` chain consists of three prefix-`send*` names, none of which match the bare-name whitelist's exact `send` entry. The hypothesised annotation-burden reduction did not happen on the one real-code chain the round was designed around.

Run D made it worse. Adding four more `@context replayable` annotations produced one new diagnostic — on a local Swift `Array.append` mutation. The first diagnostic a hypothetical adopter would see under this pattern was noise. The two actual idempotency hazards in the same function (`sendPastDueEmail`, admin `sendEmail`) were missed for the same root cause as Run B.

So the answer: the machinery is correct; the whitelist precision is wrong on both sides of the line.

### (b) What's the noise rate?

N=1 from real-code Run D. That one diagnostic was *noise*, not *correct catch* or *defensible*. N=1 is too small to report as a statistically meaningful rate, but the direction is clear enough to act on: the whitelist admits at least one common stdlib idiom (`Array.append`) as a false anchor. Adoption-readiness can't be declared from this sample.

Extending the sample via Run E' (annotating a Lambda handler) produced 0 diagnostics — consistent with the "first slice under-reads real hazards" pattern from Run B and Run D. The Lambda's `outputWriter.write(...)` is a business-state write on paper; the linter didn't fire because `write` is explicitly out-of-whitelist. Conservative-by-design in this case, rather than a gap, but the same shape of outcome: real side effects not caught without explicit effect annotations.

### (c) What comes next?

Three convergent pieces of evidence now point in the same direction:

1. Run B: `send*`-prefixed callees miss the bare whitelist. Too narrow.
2. Run D: `append` fires on stdlib local Array mutation. Too broad.
3. Run E': `write` is conservatively out-of-whitelist but real writers go uncaught.

Every one of these is solved by **receiver-type inference**, not by any of the other candidate next-slices:

- **Prefix matching** would make (1) better but (2) worse — more bare-name matches means more noise on stdlib operations sharing those names.
- **YAML-configurable whitelists** push the precision problem onto each adopting team. Teams can't solve (2) per-project because `Array.append` is defined by the stdlib, not their code. YAML also offers no help for (1) until the team has done enough annotation work to know what the right names are — circular with the problem YAML was supposed to solve.
- **Receiver-type inference** distinguishes `users.append(...)` (receiver type `Array<User>`) from a hypothetical `queue.append(...)` (receiver type user-defined). It also distinguishes `mailgun.sendEmail(...)` (receiver type from the Mailgun library) from `String.sendEmail` if any. It is the one unshipped slice that improves both ends of the precision problem.

The recommendation stands up under the "forced to pick" question from the round-4 retrospective, but shifts on *why*: R4 recommended inference because it addressed annotation-burden. R5's evidence says inference is shipped but the whitelist precision is the blocker, and receiver-type inference is the precision fix.

Ordering of the three round-4 named deliverables, updated with R5 evidence:

1. **Receiver-type inference** (roadmap Phase 2 second slice) — now the clearest priority. Addresses both failure modes seen in this round. Likely 3-5 days of implementation: requires resolving the receiver's declared-type name without full type inference (pattern-binding lookahead, parameter-type inspection, stored-property type lookup). Non-trivial but bounded.
2. **`SwiftIdempotency` macro package** (roadmap Phase 5) — unchanged priority. Its value is a runtime verification layer; the round-5 evidence says the linter half still needs a precision slice before it's adoption-ready, which makes the runtime layer more valuable (defence-in-depth matters more when any single layer is imprecise), not less.
3. **Internal microservice `swift-log`-heavy trial** — unchanged priority. OI-5 is still the untested corner. Round 5 produced zero observational-tier fires on either target (neither has `swift-log` usage at volume).

## What would have changed the triage

- **Receiver-type inference already shipped.** Run B would have caught the `mailgun.sendEmail` chain via receiver-type matching on `Mailgun`-namespaced receivers; Run D's `Array.append` noise would be silenced by receiver-type `Array<T>`. Both Run B's "disappointing zero" and Run D's "noisy one" would flip. That's the headline finding of this round — not what inference did, but what its missing piece would have done.
- **YAML whitelist already shipped.** Wouldn't have changed Run B (nothing for the team to whitelist yet) or Run D (no way to remove `append` without breaking Run C's case 5). Confirms YAML is not the right first addition.
- **Prefix matching already shipped.** Would have caught `sendEmail` in Run B. Would also have fired on any function with `create`/`insert`/`publish` as prefix on a stdlib type anywhere in pointfreeco — noise explosion. Confirms prefix matching without receiver-type gating is a net negative.

## Cost summary

- **Estimated:** 3 days, budget 4.
- **Actual:** ~90 minutes of model time, same as rounds 2-4. The "linter + target pre-prepared, work is measurement + writing" pattern held. Bulk of time spent in Run B diagnostic-gap triage and Run D FP classification — both are the kind of time well-spent the plan anticipated.
- **Biggest time sink:** none worth naming. pointfreeco's LFS setup carried over from round 4; swift-aws-lambda-runtime was already cloned as a shallow `2.8.0` checkout; linter baseline held.

## Net output after five rounds

- 1155+918+918+918 = **3909 file-scans of un-annotated source produced 0 false positives from annotation-gated rules** across rounds 1-4.
- Round 5 extends that: **0 inference-without-anchor diagnostics on two independent corpora** (pointfreeco + swift-aws-lambda-runtime). Inference does not fire without some `@context` or `@effect` anchor, as designed.
- Four real-code annotation campaigns across rounds 1, 3, 4, 5 produced the diagnostic counts the rule designs predicted in rounds 1, 3, 4. **Round 5 is the first to produce a diagnostic the rule designer would not endorse** — the `Array.append` noise is not a correct catch, a defensible case, or a phase-appropriate artifact. It is a whitelist-precision failure.
- **Six new inference-mode fixtures exercised end-to-end** at corpus scale (Run C). All six matched unit-test behaviour.

The honest assessment after five rounds: **the structural rule (`actorReentrancy`) still earns its keep on day zero; the annotation-gated rules still catch intentional violations with zero false positives; and the inference machinery works on intentional violations but has a whitelist-precision problem on real code that receiver-type inference would fix.** Round 5's contribution is identifying that precision problem with convergent evidence from two codebases, and ruling out YAML and prefix matching as viable first fixes for it.

## Policy notes

- **"No rule changes on the trial branch" held a fifth time.** Still produces cleaner deliverables. Keep.
- **Source modifications limited to documented annotation edits + one new scaffold file.** Matches round 4's approach. No implementation changes in either target.
- **Cross-project sanity check at a fraction of the effort of the primary target.** Run E + E' took ~10 minutes of model time once the primary runs were cached; the cross-project cleanliness data is a compounding-value artifact. Future rounds should include this pattern — a second corpus at the cost of one shallow clone — rather than treating primary-corpus-only as the default.

## Recommended path after round 5

Don't run round 6 yet. Build receiver-type inference. It's the one slice where R5's evidence, the R4 retro's prioritisation, and the proposal's own "deferred second-slice concerns" all agree. A round 6 on the same three codebases without it would re-measure the same too-narrow / too-broad precision failures. After receiver-type inference ships, round 6 re-runs Run B and Run D on the same pointfreeco branch — two isolated targeted measurements answer "did the fix work?" cheaply.

If receiver-type inference is blocked (needs type-resolution infrastructure that doesn't exist), pivot to the `SwiftIdempotency` macro package instead. The runtime verification layer doesn't depend on the linter's precision problems being solved, and its value only compounds with a linter half that's still short of adoption-ready.
