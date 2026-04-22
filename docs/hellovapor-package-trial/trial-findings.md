# hellovapor — Package Integration Trial Findings

Second package-adoption trial. See
[`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions.

Paired counter-case to the
[luka-vapor trial](../luka-vapor-package-trial/trial-findings.md):
luka-vapor stress-tested the `HTTPStatus.ok` pathology; hellovapor
stress-tests the Fluent-Model-returning shape. Findings compose —
each trial surfaces API gaps the other couldn't, and together they
define where `IdempotencyKey` + `#assertIdempotent` land on the
API-ergonomics map.

## Overall outcome

Migration compiled after **three compile errors** (all on the
`IdempotencyKey` side) and one SwiftPM filename collision. 5 of 5
targeted tests passing. **Four new findings** — two P0 (API
constraints on `fromEntity:`), one P1 (linter FluentKit gate
mismatch), one P3 (file basename collision). Linter parity
**partially confirmed** — works when forced with `import FluentKit`,
silent on the idiomatic `import Fluent`.

**Trial fork:** [`Joseph-Cursio/HelloVapor-idempotency-trial`](https://github.com/Joseph-Cursio/HelloVapor-idempotency-trial) on branch [`package-integration-trial`](https://github.com/Joseph-Cursio/HelloVapor-idempotency-trial/tree/package-integration-trial).

**Migration diff:** [`migration.diff`](migration.diff), 307 lines,
5 files. Net +227 / -3.

## Compilation log

| Attempt | Result | Friction |
|---|---|---|
| 1st `swift build -c release` | ❌ SwiftPM error | `Handlers/CreateAcronym.swift` collided with existing `Migrations/CreateAcronym.swift` — "multiple producers" error. Same-basename files in the same target confuse SwiftPM. Renamed to `CreateAcronymHandler.swift`. |
| 2nd build | ✅ green | Compile ran clean. |
| 1st `swift test` run | ❌ compile errors | Two errors on `IdempotencyKey(fromEntity:)`: (a) `Acronym` doesn't conform to `Identifiable` (Fluent `Model` doesn't inherit it), (b) `UUID?` doesn't conform to `CustomStringConvertible`. Adopter-side workaround: `struct IdentifiableAcronym: Identifiable` adapter that force-unwraps the UUID. |
| 2nd test run | ✅ 5/5 pass | All adapter-level flows work. |
| SwiftProjectLint scan | ⚠️ silent under `import Fluent` | 0 issues reported, but `save(on:)` is a body non-idempotent. Changing the file's import to `FluentKit` unblocks the diagnostic (1 issue, correct firing). **Linter gate gap** — doesn't recognise the Fluent meta-package alias. |

## Build-time delta

| State | Cold build | Units compiled |
|---|---|---|
| Baseline (pristine upstream) | 172.33s | 949 |
| With `SwiftIdempotency` dep | 176.23s | 955 |
| **Delta** | **+3.9s (+2.3%)** | **+6 units** |

Matches luka-vapor's pattern: +6 units (same SwiftIdempotency
targets) with a modest wall-clock delta. The slight uptick vs.
luka-vapor's ~0s delta is within normal build-time variance across
Vapor dep graphs.

## API friction log

Total: 4 new findings beyond the 3 surfaced on luka-vapor.

### P0 — `IdempotencyKey(fromEntity:)` unreachable for Fluent `Model` types

**Evidence:** compile error on first attempt.

```
initializer 'init(fromEntity:)' requires that 'Acronym' conform to 'Identifiable'
```

Fluent's `Model` protocol does not inherit `Identifiable`,
despite exposing `@ID var id: UUID?`. Every Vapor adopter using
Fluent ORM will hit this. Idiomatic workarounds:

- **Adopter-side `Identifiable` extension** (`extension Acronym: Identifiable { }`) — works, but invasive on every Model the adopter wants to key on. Can't retroactively conform types from libraries the adopter doesn't own.
- **Adapter struct** (`struct IdentifiableAcronym: Identifiable { ... }`) — the path used in this trial. Flexible but requires one adapter type per Model.
- **Route through `init(fromAuditedString:)`** — the audit hatch. Same as luka-vapor's primary path.

**Recommendation:** either drop `fromEntity:`'s `Identifiable`
constraint in favour of a structural check (`entity.id` by KVC or
reflection — more fragile) or add a `fromFluentModel:` or
`fromModelID:` constructor dedicated to Fluent-shaped types.
Neither is cheap; the simplest path is documenting the limitation
in the README.

### P0 — `E.ID: CustomStringConvertible` constraint excludes Optional types

**Evidence:** second compile error, after adapter fix.

```
initializer 'init(fromEntity:)' requires that 'UUID?' conform to 'CustomStringConvertible'
```

`IdempotencyKey.init<E: Identifiable>(fromEntity: E) where E.ID: CustomStringConvertible`
rejects any type whose `ID` is Optional — including every Fluent
Model's `id: UUID?`. Even after bridging to `Identifiable`, the
adapter still has to flatten the Optional (force-unwrap or
substitute a placeholder) to compile.

**Recommendation:** relax the constraint. `String(describing:)` —
which the constructor already calls internally — handles Optionals
without crashing (`String(describing: Optional<UUID>.none)` =
`"nil"`). The constraint could be dropped entirely, or replaced
with a less-demanding requirement. An alternative: accept Optional
IDs but produce a descriptive-but-non-unique `"nil"` key, letting
the adopter's own precondition fire if they try to build a key
before save.

### P1 — Linter FluentKit gate doesn't accept `import Fluent` meta-package

**Evidence:** `SwiftProjectLint` scan returned "No issues found"
on a file importing `Fluent` with a body containing `save(on:)`
inside an `@ExternallyIdempotent`-marked function. Swapping the
import to `FluentKit` flipped the scan to 1 issue (correct
firing).

The gate is currently scoped to the literal import name
`FluentKit`. The standard Vapor adopter imports `Fluent` (the
meta-package that re-exports `FluentKit`). SwiftSyntax's
`ImportCollector` reads the literal import token, so the gate
misses the idiomatic case.

**Recommendation:** SwiftProjectLint slot candidate. Extend the
FluentKit gate to also match `import Fluent`. Either hardcode
both strings or build a meta-package-alias table. Low-cost (same
shape as slots 13–18). Will need cross-adopter evidence — check
whether other adopters who used `import Fluent` (prospero,
myfavquotes-api, SPI-Server) had the same silencing issue in
their linter trial scans.

### P3 — File basename collision with existing adopter source

**Evidence:** SwiftPM error on first build, `"multiple producers"`
for `CreateAcronym.swift.o`. The adopter's `Migrations/CreateAcronym.swift`
and my new `Handlers/CreateAcronym.swift` collided — SwiftPM
flattens all `.swift` files under a target into one compilation
regardless of subdirectory nesting.

**Recommendation:** documentation-only. Add a "watch out for
filename collisions with existing sources" note to the package's
adoption section. Adopters with a Migrations-or-Controllers file
named `CreateX.swift` who add a handler under `Handlers/` with
the same name hit this immediately. Rename convention suggestion:
`CreateXHandler.swift` or similar differentiator.

## Pre-committed questions — answers

### 1. Option C sharpness on Fluent Model returns

`Acronym` (a `final class` without explicit `Equatable` conformance)
does not compile as an `#assertIdempotent` return type — the
compiler requires `Equatable` for return comparison. The adopter
workaround is to return a tuple of the Model's value fields from
the closure: `(id, short, long)`. Tuples of Equatable types are
synthesized-Equatable, so the macro accepts them.

When the tuple includes the mutable `id: UUID?`, Option C
correctly catches the create non-idempotency: two saves produce
distinct UUIDs, the tuples compare unequal, the `#assertIdempotent`
precondition fires. This is a cleaner demonstration of Option C
working than luka-vapor's `HTTPStatus.ok` pathology showed was
impossible.

**Combined with luka-vapor:** Option C is sharpest on
synthesized-Equatable struct / tuple returns that include a
mutable field reflecting state changes. It's blind on trivial
returns (`HTTPStatus.ok`, `Void`, `Bool`) and requires adopter
workarounds (tuple wrapper or `Equatable` extension) on
reference-type returns that are the norm in Fluent.

### 2. `IdempotencyKey(fromEntity:)` reachability

**Not reachable without adopter-side adapter code.** Two
compile errors (Identifiable conformance + CustomStringConvertible
on Optional ID) block the straight-through use. The adopter
writes an adapter struct with force-unwrapped UUID, only usable
post-save. For create handlers, this is the bootstrap problem:
the entity has no id until after save, so `fromEntity` can't be
the source of a pre-save dedup key anyway.

**Practical consequence:** `fromEntity:` is a post-save-read-or-
lookup tool, not a create-handler tool. Create handlers flow
through `init(fromAuditedString:)` on a header or a natural
business key.

### 3. Header-vs-body idempotency-key placement

**Header placement works cleanly.** The migration uses
`req.headers.first(name: "Idempotency-Key") ?? acronym.short` —
REST-idiomatic, Stripe-convention-aligned, and integrates with
Vapor's `Request.headers` API without any special handling. The
fallback to the natural business key (`acronym.short`) makes
clients that don't supply the header still get deterministic
dedup via the adopter's own data.

No `Codable` wrapping of the request body was needed — in
contrast to luka-vapor, where the key had to go in the request
body because there's no standard "attach a side-channel value"
for Vapor `Content`-decoded structs. Header placement is the
cleaner adopter pattern where clients are HTTP-aware.

### 4. Cross-adopter refactor cost

**Comparable in magnitude to luka-vapor.** HelloVapor's handler
body was only 3 lines (decode + save + return) vs. luka-vapor's
67. The refactor produced 13 lines of new handler code + 10-line
registration delegate. Total migration diff 227 additions / 3
deletions; luka-vapor was 240 additions / 64 deletions. Both
are ~1 file's worth of new code per handler migrated. The shape
is structural (inline-closure → named-func), not adopter-specific.

## Linter parity

| Import | Result |
|---|---|
| `import Fluent` (idiomatic) | ❌ 0 issues. `save` is classified as nothing because the FluentKit gate doesn't match the meta-package name. |
| `import FluentKit` (explicit) | ✅ 1 issue. `idempotencyViolation` fires correctly: "calls 'save', whose effect is inferred `non_idempotent` from the FluentKit ORM verb `save`." |

Attribute-form parity (the question: "does the linter recognise
`@ExternallyIdempotent(by:)` the same as the doc-comment form?")
holds — the rule that fires is the correct externally-idempotent-
body rule, same shape as luka-vapor. But the **end-to-end
adopter experience** diverges: the linter is silent on idiomatic
HelloVapor source because of the import-alias gap. Worth a slot
on SwiftProjectLint.

## Comparison to predicted outcomes

| Prediction | Actual | Match? |
|---|---|---|
| Inline-closure refactor friction reproduces | Confirmed, same shape as luka-vapor | ✅ |
| `Acronym` compile error on `#assertIdempotent` | Confirmed via test documentation | ✅ |
| `fromEntity:` compile error on Optional Fluent ID | Confirmed — TWO errors (Identifiable + CustomStringConvertible) | ✅ + an extra finding |
| Pre-save id bootstrap problem | Confirmed — can't build the key from the entity being created | ✅ |
| Header-based key flow works cleanly | Confirmed | ✅ |
| Build-time delta ~0s | Actual +3.9s — marginal but non-zero | ⚠️ slightly higher than predicted |
| Linter parity holds | Parity on attribute parsing; gate mismatch on `import Fluent` | ⚠️ partial |

**Bonus findings not predicted:**

- SwiftPM filename collision with existing Migration file.
- The `CustomStringConvertible` constraint on `E.ID` — predicted only the `Identifiable` gap, didn't anticipate this second layer.
- The `Fluent` vs `FluentKit` import gate mismatch on the linter side.

## Recommendations summary — combined with luka-vapor

For v0.1.0 pre-release (package-side):

- **Should-do (README):** Add a "**Using with Fluent ORM**" section to the README. Document the `Identifiable` conformance workaround, the pre-save bootstrap issue, the header-sourced key flow as the idiomatic path. This is the single biggest documentation gap for Vapor/Fluent adopters — the package's largest potential adoption demographic.
- **Should-do (README):** Note the filename-collision gotcha in the "Migrating inline-closure handlers" section.

For v0.1.0 (linter-side — SwiftProjectLint slot candidate):

- **New slot candidate (slot 19?):** extend the FluentKit gate to also match `import Fluent` (meta-package alias). Cross-adopter evidence: this silencing is present today on every adopter that uses the idiomatic Vapor import. Re-check the HelloVapor linter-trial scans for how much this changes the catch count — probably meaningfully.

For post-v0.1.0:

- **API consideration:** relax `IdempotencyKey(fromEntity:)`'s constraints — either drop `CustomStringConvertible` requirement (use `String(describing:)` which handles Optionals) or add a Fluent-Model-shaped constructor. Needs a third adopter trial to see whether non-Fluent Identifiable users hit the same Optional-ID pattern.
- **Option C sharpness story:** three adopter shapes now characterised —
  - Synthesized-Equatable struct returns: ✅ works (luka-vapor's request-body tests).
  - Trivial returns (`HTTPStatus.ok`, `Void`, `Bool`): ❌ pathology (luka-vapor).
  - Reference-type returns (Fluent `final class` Model): ❌ without adopter workaround (hellovapor).
  The README update drafted for the luka-vapor trial covers pathology case 2 but not case 3. Worth extending.
