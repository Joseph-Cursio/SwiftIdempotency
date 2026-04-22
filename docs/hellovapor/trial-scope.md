# HelloVapor — Trial Scope

Second-adopter corroboration round for **slot 17 (Vapor routing
DSL whitelist)**. First-adopter evidence landed on
[`luka-vapor`](../luka-vapor/trial-scope.md) this session: 2
`app.post` fires under replayable + 1 `app.get` under strict.
HelloVapor is a scout-identified second Vapor adopter using
inline-trailing-closure shape, selected specifically because its
`routes.swift` has 5× `app.get` + 1× `app.post` inline closures —
the inverse distribution from luka-vapor — so a confirming scan
pins the slot-17 shape from two complementary angles.

## Research question

> **Does `app.post` inline-closure registration fire consistently
> across two independent Vapor adopters, and does the `app.get`
> silent-under-replayable / fires-under-strict asymmetry from
> luka-vapor reproduce? If both reproduce, slot 17 has 2-adopter
> ship-eligibility under the same 5-verb scope as slot 16.**

## Pinned context

- **Linter:** `SwiftProjectLint` @ `29e9069` (slot-16 tip, same
  as luka-vapor round).
- **Target:** `sinduke/HelloVapor` @ `87fa436` (main, 2026-04-20,
  "[Fix] 修复 Docker 真实编译测试路径").
- **Trial fork:**
  [`Joseph-Cursio/HelloVapor-idempotency-trial`](https://github.com/Joseph-Cursio/HelloVapor-idempotency-trial)
  (hardened; issues/wiki/projects disabled, sandbox description,
  default-branch switched).
- **Trial branch:** `trial-hellovapor` on the fork.
  - **Run A tip:** `05e5433` (`routes(_:)` @ `@lint.context replayable`).
  - **Run B tip:** `4b2bea2` (same function flipped to `@lint.context strict_replayable`).
- **Scan corpus:** whole project — single SPM package, ~20 Swift
  files, Fluent + Vapor + Leaf. Single target: `HelloVapor`.
- **Toolchain:** swift-tools-version 6.0.
- **Stack:** Vapor 4.115 + Fluent 4.9 + FluentSQLite 4.6 + Leaf
  4.3 + NIO 2.65. All deps version-pinned (no branch deps —
  reproducibility cleaner than luka-vapor).

## Annotation plan

Same shape as luka-vapor: one annotation on `routes(_ app:)` at
`Sources/HelloVapor/routes.swift:4`. Enclosing function walks into
all 6 inline trailing closures:

| Closure site | Line | DSL call | Handler shape |
|---|---|---|---|
| 1 | 5 | `app.get { }` | Leaf view render (observational-ish) |
| 2 | 9 | `app.get("hello")` | literal return |
| 3 | 13 | `app.get("hello", "vapor")` | literal return |
| 4 | 17 | `app.get("hello", ":name")` | `parameters.get("name")` + literal interpolation |
| 5 | 24 | `app.get("info")` | `content.decode` + literal interpolation |
| 6 | 31 | `app.post("api", "acronym")` | Fluent `acronym.save(on: req.db)` — **create-path, candidate real bug** |

Additionally: 4× `app.register(collection:)` calls at lines 38-41.
Those are `register` — non-idempotent-by-prefix-lexicon from slot
13 — and will fire under replayable; logged as sibling-pair
candidate `(app, register) → Vapor`, not blocking slot 17.

## Scope commitment

- **Measurement-only.** No linter changes this round.
- **Source-edit ceiling**: ≤ 2 files — one doc-comment line on
  `routes(_:)` (+1 for tier flip between runs), plus README fork
  banner.
- **Audit cap**: 30 diagnostics. Run B likely under cap (predicted
  ≤ 30).
- **Single sub-package.**

## Pre-committed questions

1. **`app.post` reproduction.** Does the single `app.post("api",
   "acronym")` registration fire under replayable? (Expected: yes,
   at line 31/32.) Confirms luka-vapor's shape is receiver-
   agnostic-name-heuristic, not corpus-specific.
2. **`app.get` strict-mode asymmetry.** Do the 5× `app.get`
   registrations fire under strict_replayable? (Expected: yes,
   5 fires. luka-vapor's 1× `app.get` strict fire would then
   generalise to "every `app.get` inline registration fires under
   strict regardless of handler body.") If yes, slot-17 scope
   matches slot 16 at 5 verbs.
3. **Acronym save — real-bug candidate.** Does the Fluent
   `acronym.save(on: req.db)` diagnostic survive the SQL
   ground-truth pass? Check `CreateAcronym` migration for
   `.unique(on: "short")` or equivalent. If no unique constraint
   exists, retry = duplicate row; correct catch. If unique
   constraint exists, defensible-by-design.
4. **`(app, register)` sibling-pair evidence.** How many
   `register` fires under replayable? (Expected: 4, one per
   controller registration.) First-adopter evidence for a
   possible sibling slice; note but don't promote.

## Predicted outcome

- **Run A (replayable):** 1 `app.post` fire + 4 `app.register`
  fires = 5 total.
- **Run B (strict):** Run A's 5 carried + strict-only cluster of
  `app.get` (×5) + handler-body stdlib/Fluent/Leaf fires + ctor
  fires on controllers. Predicted 20–30.

If both slot-17 predictions confirm (`app.post` replayable-fire +
`app.get` strict-only cluster), slot 17 is 2-adopter ship-eligible
at 5-verb scope. Expected behaviour: same as slot 16 cross-tier
silencing.
