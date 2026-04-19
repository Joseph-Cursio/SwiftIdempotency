# Deferred idea: `missingObservability` — flag replayable contexts with no observation calls

**Status.** Idea only. Not scheduled, not implemented. Saved here so it isn't forgotten.

## Origin

During the OI-5 (`observational` tier) design discussion, I briefly suggested making "observation is expected, not exceptional" an explicit premise of the proposal. The user correctly walked that back — they did not mean to argue that the linter should *enforce* the presence of logging, only that observational calls are common. The observational tier as shipped classifies calls when they appear and does not mandate that they appear.

This doc preserves the discarded sibling idea for possible future revisit.

## What the rule would flag

A function declared `@lint.context replayable` (or `retry_safe`, or `dedup_guarded`) whose body contains **no call** to any known observation primitive. The motivating intuition: if a handler is replayable, something in production is replaying it, and at least one observation call is how an operator notices duplicates, correlates retries to upstream triggers, or debugs dedup-guard misses.

## Why it could be useful

- **Duplicate-delivery diagnostics.** A replayable handler that fires twice and leaves no trace behind is invisible in retrospect. A single `logger.info("handling messageID: \(id)")` turns "duplicate charge mystery" into a grep.
- **Dedup-guard commissioning.** Adding a `@context dedup_guarded` function and forgetting to log the skip-path hides the guard's whole value from operations. One observation call is cheap; its absence is expensive at 3 a.m.
- **Compositional hygiene.** If every retry-safe context eventually logs, the rule is a tripwire for functions that were marked replayable as a copy-paste of the annotation without the operational thinking behind it.

## Why it's *not* implemented

- **Not every team wants their linter nagging about log coverage.** Test helpers, pure transforms behind a `@context replayable` adapter, and any handler whose observation goes through a custom framework the rule doesn't know about would all hit false positives.
- **Defining "observation primitive" is the hard part.** `Logger.info` and `os.Logger` and metrics SDKs each have their own entry-point names; the rule would either ship with a curated list (brittle) or depend on the team declaring them via `@lint.assume Logger.info is observational` first (fine, but then the rule presupposes an annotation campaign that most teams haven't done).
- **User's explicit direction:** "I did not mean to say that we should lint/catch missing logging." The observational tier is a classifier, not a mandate.

## Candidate rule shapes, if it ever lands

### Shape A — structural, whitelist-based (cheap)

Flag a `@context replayable` / `retry_safe` body that contains **zero** `FunctionCallExprSyntax` whose callee's declaration name is in a configured whitelist (e.g. `info`, `debug`, `warning`, `error`, `increment`, `observe`, `startSpan`). Conservative, purely structural, no annotations required on observation primitives.

- Pro: works out of the box, no annotation campaign prerequisite.
- Con: coupled to specific primitive names; misses teams with custom observability layers; probably wants a per-project configuration override.

### Shape B — tier-based (requires observational-tier adoption)

Flag a `@context replayable` / `retry_safe` body that contains no call resolving (via `EffectSymbolTable`) to an `@lint.effect observational` callee. Reuses the existing cross-file resolution machinery.

- Pro: clean semantics, no whitelist in the rule itself.
- Con: requires teams to have annotated at least their logging primitives (directly or via `@lint.assume`) before the rule produces any signal; without that coverage it's 100% false-positive.

### Shape C — opt-in attribute

Flag only when the function carries a *second* annotation such as `/// @lint.requires observation`. The linter fires when the declared requirement isn't met. No default behaviour; teams opt in per-function.

- Pro: zero false positives by default; ships-compatible with any codebase.
- Con: requires teams to remember the annotation on every replayable function — which defeats part of the point (noticing when someone *forgot*).

## Open questions

- **What counts as "one call"?** A single `logger.info` on a rarely-taken path (e.g., inside a `guard else` branch) might satisfy the rule structurally but not the operational intent. Counting observation calls by control-flow coverage rather than raw presence is much harder.
- **Dedup-guard skip path.** For `@context dedup_guarded` specifically, the operational need is different: the bug is usually not "nothing logs" but "the skip path doesn't log the skip." That's a more specific rule (observation call must exist in the branch that returns early from the dedup guard) and might stand alone from the general replayable-context rule.
- **Relationship to SwiftProjectLint's existing `printStatement` rule.** `print(...)` is discouraged by one existing rule; the missing-observability rule might accept it as "better than nothing" or might specifically reject it. Needs a deliberate call.
- **Severity.** Info-level nudge ("you may want observability here") is plausibly fine everywhere. Warning- or error-level risks being the second-loudest rule in the suite. Default should almost certainly be info.

## Relationship to shipped work

- `@lint.effect observational` (OI-5 resolution) is the classifier tier this rule would build on if implemented via Shape B.
- `@lint.context replayable` / `retry_safe` (Phase 4 shipped) are the contexts this rule would trigger on.
- The `EffectSymbolTable`'s cross-file resolution (OI-4 resolution) already handles the "callee in a sibling file" case required for Shape B.

Nothing more to do until there's evidence a real codebase wants this check. If that evidence appears — typically a post-mortem of a retry that nobody noticed — revisit Shape A as the minimum viable rule.
