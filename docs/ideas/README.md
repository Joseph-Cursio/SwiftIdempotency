# Deferred ideas — index

One line per idea, with the concrete trigger that would promote it from
"parked" to "plan it." Every file in this folder carries a
**Status** and **Trigger for promotion** section; the one-liners below
are the minimum signal for deciding whether a given round's findings
justify reopening anything.

Ordering is roughly by how likely the trigger is to fire next, not by
file name.

| Idea | Status | Promote when… |
| --- | --- | --- |
| [closure-binding-cross-reference](closure-binding-cross-reference.md) | Deferred — real silent gap | an adopter annotates a `let handler = { ... }` binding and expects the caller to fire, or a Vapor/Hummingbird app stresses cross-file closure-binding references. |
| [inline-trailing-closure-annotation-gap](inline-trailing-closure-annotation-gap.md) | Known scope gap (~37% of Lambda examples) | a real adopter brings a codebase dominated by `LambdaRuntime { ... }` trailing-closure form and refuses the named-binding refactor. |
| [fire-and-forget-escape-wrappers](fire-and-forget-escape-wrappers.md) | Real gap, no current noise | a trial round produces a false positive traceable to a non-stdlib escape wrapper (custom `fireAndForget`, `execute`, `schedule`, Vapor `eventLoop.future`, etc.). |
| [pointfreeco-triage-issue](pointfreeco-triage-issue.md) | Deferred — gated on user approval | the user explicitly approves filing, adopter-engagement becomes a named workstream, or an independent upstream report in the area signals maintainer receptiveness. |
| [missing-observability-rule](missing-observability-rule.md) | Idea only, walked back | a real post-mortem surfaces "replayable handler fired twice, nobody noticed" — revisit Shape A as the MVP. |
| [trial-survey-methodology](trial-survey-methodology.md) | Lesson learned, not a feature | a second road-test has a survey miss caught post-facto, **or** a `Scripts/` survey tool would pay back on a planned remeasurement. Otherwise: apply the "match-then-filter" rule in every Phase-0 survey. |
| [doc-comments-after-attributes](doc-comments-after-attributes.md) | **Resolved** — historical record | — (kept as a record of the bug's shape + the scope-discipline reasoning that kept the fix out of the Phase-1.1 OI-4 commit). |

## Shape of a good idea-doc

Any new file added here should carry at minimum:

- **Status** — is this parked, idea-only, speculative, or historical?
- **Origin** — the trial round or discussion that surfaced it.
- **Trigger for promotion** — the concrete signal that would reopen it.
- **Design sketches** — enough shape that a future session can estimate
  cost without re-derivation.

The discipline is the point. An idea doc without a trigger is a
wish-list entry, which rots faster than it ages.
