# Round 6 Trial Retrospective

One page. First cross-project validation of the receiver-type + prefix-matching slices.

## Did the scope hold?

**Yes, fully.** Zero rule changes on the linter. Nine annotations on named-function Lambda handlers, one new scaffold file. No source modifications beyond what the plan's Run B/C explicitly enumerated. `trial-inference-round-6` branch, local only. Run D skipped with reasoning recorded. Policy note "document skips" honoured.

## Answers to the four pre-committed questions

### (a) Inference-without-anchor cleanliness persists post-prefix-matching?

**Yes.** Run A produced 0 diagnostics on bare `swift-aws-lambda-runtime` — identical result to R5 Run E on the pre-prefix-matching linter. The prefix slice widened the *match* surface but not the *fire-without-anchor* surface. This is the behaviour the design required.

### (b) What's the real-code catch yield on the un-tuned corpus?

**0 catches from 9 annotations.** Not a precision failure — a corpus-structural fact. Lambda examples are pure compute/IO handlers (read event → write response → log). The current inference whitelist is calibrated to business-app shapes (webhooks calling `sendEmail`, `publishEvent`, `insertRow`) that the examples don't contain.

The honest framing: R5's "4/5 yield on pointfreeco" finding was shape-specific, not linter-general. On a corpus whose handlers don't reach external side-effect surface, the current inference is *correctly silent*, not *failing to find hazards*. A Lambda application that actually called `mailgun.sendEmail(...)` from its handler (rather than just logging and writing a response) would produce pointfreeco-shape yields; the examples don't.

### (c) What new false-positive surface did prefix matching expose?

**None observed.** Five negative cases in the Run C scaffold cover the expected risk shapes (`str.appending(x)`, `publisher(for:)`, `postpone(task)`, bare `publish` inside `Task {}`, filter on Array) and all stayed silent. Run B on un-tuned real code produced zero false positives.

This doesn't guarantee zero false positives on every codebase — a corpus with different idioms could still surface something — but across the pointfreeco and Lambda corpora, two distinct code styles, the camelCase gate + stdlib-exclusion gate have held.

### (d) Does stdlib-exclusion coverage miss any patterns the Lambda corpus uses?

**No shapes surfaced that would need new exclusion entries.** Lambda handlers use `Array.filter`, `JSONEncoder.encode`, `Task.sleep`, `context.logger.*` — none of which match the whitelist, so the exclusion table isn't load-bearing here. The one pattern that *does* touch the exclusion surface is `String.appending(...)` (Foundation's copy-returning form) which Run C case 5 confirmed stays silent.

## The unplanned finding — closure-based handler annotations

Roughly half the `Examples/` surface is out of reach of the current `/// @lint.context` grammar because the handlers are closures rather than function declarations. Every `LambdaRuntime(body: { event, context in ... })`-style example (HelloWorld, HelloJSON, both APIGateway variants, JSONLogging, HummingbirdLambda, CDK, Authorizer, ServiceLifecycle+Postgres, _MyFirstFunction) cannot currently be annotated. Nine of the ten are objectively replayable by invocation semantics.

Pointfreeco's corpus hit zero closure-handler shapes, so R5 didn't surface this gap. It's a real adoption-friction point for the modern-Swift-server ecosystem. Three possible fixes, ordered by plausibility:

1. **Parse `@lint.context` from leading trivia on a closure expression assigned to a typed variable.** If the variable's type matches a known Lambda handler signature, treat the closure as annotatable. Narrow, reasonable.
2. **Introduce a `@lint.context` attribute-style annotation** alongside the doc-comment annotation, and allow it to attach via `@Sendable @lint.context.replayable { ... }` or similar. Broader grammar change.
3. **Document the gap and leave it.** Teams wanting coverage on closure-based handlers refactor to `func` declarations. Honest but adoption-hostile.

Worth elevating as an open-issue in the proposal doc (OI-7 or similar). Not scoped for round 7 unless evidence demands it.

## What comes next

With R5 and R6 both clean (zero noise on two corpora spanning different code styles), the adoption-readiness bar for the linter is cleared on the evidence side. Three candidate next-units, reshuffled by post-R6 priorities:

1. **`SwiftIdempotency` macro package** (proposal Phase 5) — now the highest-priority remaining work. Every linter-side precision fix has a compounding ceiling; compile-time enforcement via `IdempotencyKey` strong type is qualitatively stronger than any heuristic. R6's yield finding on Lambda (0 catches despite clean precision) reinforces this — linter inference is only as useful as its whitelist's overlap with each team's code; the macro package's strong-type enforcement applies uniformly.
2. **Closure-handler annotation grammar** — directly motivated by R6's scope-gap finding. Bounded work (~1-2 days), delivers coverage for modern Swift-server apps. Reasonable parallel track to the macro package.
3. **Third-corpus validation (Vapor or internal microservice)** — deferred again. Two-corpus cleanliness is a defensible adoption signal; a third pointfreeco-shape codebase would produce mostly duplicative evidence. More valuable if done *after* either (1) or (2) ships, to test the new surface.

## Cost summary

- **Estimated:** 3 days, budget 4.
- **Actual:** one focused session, ~60 minutes of model time. Lower than prior rounds — the linter baseline was pre-cached, annotation campaign was mechanical across 9 mostly-identical files, Run B produced a clean zero requiring minimal triage, Run D skipped.
- **Biggest time sink:** none worth naming. The closure-handler finding emerged from the annotation survey during Phase 0, not from a surprise mid-run.

## Net output after six rounds

- 3909 file-scans of un-annotated source (rounds 1-4) + swift-aws-lambda-runtime (round 5 + round 6) = **four distinct corpora, all producing 0 inference-without-anchor diagnostics**.
- Intentional-violation fixtures across rounds 1, 3, 4, 5, 6 all match expected diagnostic counts with correct line numbers and correct provenance prose. The rule mechanics are validated at corpus scale five different times.
- **One confirmed zero-noise result on a corpus the precision fixes were not tuned against** (round 6). The overfitting risk named in the round-5 post-fix is retired.
- **One new open issue surfaced:** closure-based handler grammar gap. Documented, not fixed.

The R5 honest-assessment line still stands: *the structural rule (`actorReentrancy`) earns its keep on day zero; the annotation-gated rules and Phase-2 inference machinery are well-built and waiting for users.* R6 adds: *the precision claim generalises to a second corpus style, and the yield claim is more narrowly scoped than R5 implied — inference catches are proportional to how much the team's code overlaps with the whitelist calibration, not a uniform "catches per annotation" constant.*

## Policy notes

- **Skipping Run D was the right call.** Widening annotations on a corpus that doesn't exercise the rules wouldn't have produced new information. The "document skips with reasoning" policy from R4 continues to pay off.
- **The closure-handler finding surfaced in Phase 0 prep, not in a run.** That's a pattern worth repeating: the annotation-candidate survey is a small-cost, high-leverage step that catches scope issues before a measurement does.
- **Per-corpus yield heterogeneity deserves explicit framing.** The R5 post-fix doc's "4/4 correct catches" line should be read as "4/4 of the catches that fired were correct" not "the rule catches 80% of replayable hazards." The two claims are different; the R6 data makes the distinction sharper.

## Recommended path after round 6

Don't run round 7. Build either:

- **The macro package.** Fastest path to the next qualitative step-change. 5-8 weeks.
- **Closure-handler annotation grammar.** Small, targeted, directly motivated by R6 evidence. 1-2 days.

Either one makes the next measurement round (whenever it happens) measure something novel. Another full trial on a third codebase before either ships would be a more-of-the-same exercise.
