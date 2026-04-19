# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Status

This repo contains both the `SwiftIdempotency` Swift package (macros + `IdempotencyKey`) and the design documents that drove its shape. The global "clean + test on session start" rule applies — run `swift package clean && swift test` at session start.

**Package layout** (see `Package.swift` for full target graph):

- `Sources/SwiftIdempotency` — public API: `@Idempotent`, `@NonIdempotent`, `@Observational`, `@ExternallyIdempotent`, `@IdempotencyTests`, `#assertIdempotent`, `IdempotencyKey`
- `Sources/SwiftIdempotencyMacros` — compiler plugin implementing the above
- `Sources/SwiftIdempotencyTestSupport` — runtime helpers for `#assertIdempotent` (linked only from test targets)
- `Tests/SwiftIdempotencyTests` — macro expansion + runtime tests

**Design documents** under `docs/`:

- `docs/idempotency-macros-analysis.md` (~1850 lines) — the primary design proposal: adding idempotency modeling to SwiftProjectLint via doc-comment annotations, a phased static analyzer, Swift macros, and protocol-based type safety. **This is the authoritative document.**
- `docs/idempotency_updated_critique.md` — a ChatGPT-generated critique of the proposal. Useful as external perspective, not as a spec. Some of its points are already resolved in the proposal body or explicitly rebutted in the Q&A section; evaluate each on its own merits and feel free to disagree. When the two docs conflict, the proposal wins.
- `docs/claude_phase_*_plan.md` + `docs/phase*-round-*/` — round-by-round implementation plans that tracked the package's build-out. Historical context only; the README and shipped source are authoritative for the current shape.

## The Split This Repo Is Designing

The proposal explicitly splits into **two deliverables** (see "Scope: What Belongs in This Repo"). Keep this split intact in any implementation work:

1. **`SwiftIdempotency` package** (this repo): defines the `@Idempotent` / `@NonIdempotent` / `@Observational` / `@ExternallyIdempotent` attribute macros, the `@IdempotencyTests` extension macro, the `#assertIdempotent` freestanding expression macro, and the `IdempotencyKey` strong type.
2. **SwiftProjectLint rules** (in a separate repo): consumes the annotations and enforces them. Ships as `IdempotencyVisitor` + rule identifiers (`idempotencyViolation`, `nonIdempotentInRetryContext`, `actorReentrancyIdempotencyHazard`, etc.) plugged into `CrossFileAnalysisEngine`.

A linter is a *consumer* of contracts, not a *definer* of them. Do not bundle the macro library into the lint rules.

## Core Design Concepts (needed to edit either doc coherently)

**Effect lattice** — five positions, not binary:
```
pure < idempotent < { transactional_idempotent, externallyIdempotent } < non_idempotent
                                                                  unknown (incomparable)
```
`transactional_idempotent` and `externallyIdempotent` sit at the same tier — both are conditionally idempotent via different mechanisms (transaction boundary vs. idempotency key). Neither is strictly stronger than the other. `unknown` is treated conservatively as `non_idempotent` in strict mode.

**Annotation surface** — doc comments are deliberately the shared interoperability surface between humans, the linter, and macros. All three consumers read the same token. This is why the proposal rejects protocol-only modeling.

- `/// @lint.effect <tier>` — declared effect (with optional `(by: <param>)` or `reason:`)
- `/// @lint.context <replayable|retry_safe|once|dedup_guarded>` — execution context
- `/// @lint.assume <symbol> is <effect>` — auditable third-party claims
- `/// @lint.unsafe reason: "..."` — *semantic* escape hatch
- `// swift-idempotency:disable[-next-line|-file] <rule>` — *mechanical* suppression (distinct from `@lint.unsafe`; do not conflate)

**Minimum viable system** — per the critique and the "Start With Two Effects" section, the recommended Phase 1 is just `@lint.effect idempotent` + `@lint.effect non_idempotent` + basic call-graph validation. Treat the rest of the document as a menu, not a checklist. New design work that expands surface area before Phase 1 has shipped is the main failure mode the critique warns against.

**Branch-sensitive inference** — a function's inferred effect is the lattice *join* of its branches (usually the weakest). The distinct diagnostic `effectVariesByBranch` surfaces disagreement rather than silently collapsing to `non_idempotent`.

**Actor reentrancy rule** — `actorReentrancyIdempotencyHazard` is the highest-value original contribution. It's AST-detectable (guard on stored-property membership → `await` → insert into same property, inside an actor method) and fires on structural grounds independent of any annotation. It's the one rule that delivers value before any team has annotated anything.

## Validation Target

When the proposal eventually gets validated against a real codebase, the recommended first target is `apple/swift-aws-lambda-runtime` — every SQS/SNS handler is objectively `@context replayable`, so annotation correctness is unambiguous. SwiftNIO is explicitly called out as the wrong target (reference-type handlers, runtime enforcement already in place, below the business-logic layer).

## Editing Conventions

- Rule identifiers are defined alongside the rules that introduce them. When adding a new lint rule to the proposal, also add its `case name` at the end of the section (see existing examples: `effectVariesByBranch`, `closureArgumentFailsEffectRequirement`, `unusedSuppression`, `unknownAnnotationVersion`).
- The proposal uses em-dashes and occasional non-ASCII characters (⸻, ✅, ❌, ⚠️). Preserve them.
- Grammar versioning is via `.swift-idempotency.yml` `grammar_version: <n>`. A new annotation tier is a grammar bump, not a silent extension.
- The document is dated "April 2026" in its footer. Update if the proposal is substantively revised.
