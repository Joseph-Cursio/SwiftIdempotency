# Design: Fluent-Shaped `IdempotencyKey` Constructor

Pre-implementation design doc for the post-v0.1.0 API extension
deferred out of the synthetic-swiftdata trial
([`synthetic-swiftdata-package-trial/trial-retrospective.md`](synthetic-swiftdata-package-trial/trial-retrospective.md)
§"P2").

## Problem

The hellovapor trial surfaced two P0 findings on
`IdempotencyKey.init(fromEntity:)` when used against Fluent
Models:

1. **`Fluent.Model` does not conform to `Identifiable`** — the
   generic constraint `<E: Identifiable>` rejects every Fluent
   Model as written.
2. **`Fluent.Model.id` is typed `IDValue?` (Optional)** — the
   constraint `where E.ID: CustomStringConvertible` rejects
   Optional types regardless of the wrapped type.

The adopter-side workaround documented in the hellovapor findings
(and in the README's "Using with Fluent ORM" section) is a
per-Model adapter struct:

```swift
struct IdentifiableAcronym: Identifiable {
    let acronym: Acronym
    var id: UUID { acronym.id! } // safe only post-save
}

let key = IdempotencyKey(fromEntity: IdentifiableAcronym(acronym))
```

This boilerplate scales linearly with the number of Fluent Models
an adopter keys idempotency on. The synthetic-swiftdata trial
confirmed the Optional-ID pattern is **Fluent-specific** — non-Fluent
Identifiable types reach `fromEntity:` cleanly. Hence the targeted
fix: a dedicated Fluent-shaped constructor, not a global
constraint relaxation.

## Non-goals

- Solving the **create-handler bootstrap problem** (pre-save id
  is nil regardless of constructor shape). For create handlers,
  the idiomatic path remains `IdempotencyKey(fromAuditedString:)`
  over a header-sourced or business-key string.
- Supporting `@CompositeID` composite-primary-key Models in the
  initial shape. Composite IDs are custom struct types that
  don't conform to `CustomStringConvertible` by default; the
  initial constructor will constrain `IDValue: CustomStringConvertible`
  and leave composite-ID Models to add their own conformance or
  to route through `fromAuditedString:` on a composed string.
- Supporting pre-Fluent-5 / legacy shapes. Target: current
  `vapor/fluent-kit >= 1.48.0` (the current stable major at the
  time of writing).

## Design decisions

### Decision 1 — Dependency strategy: separate product

Three options considered:

| Option | Shape | Verdict |
|---|---|---|
| A: `#if canImport(FluentKit)` in `SwiftIdempotency` | Single import; conditional on FluentKit being in the adopter's module graph. | ❌ Symbol silently invisible if FluentKit import is missing. Debugging "why doesn't this init exist?" is hostile. |
| **B: separate `SwiftIdempotencyFluent` product** | New SPM library in the same package. Depends on `SwiftIdempotency` + `FluentKit`. Adopters opt in with one extra Package.swift line. | ✅ Explicit; clean package graph for non-Fluent adopters; matches the existing `SwiftIdempotencyTestSupport` product pattern. |
| C: fully separate repo | `github.com/Joseph-Cursio/SwiftIdempotencyFluent` | ❌ Over-engineered for ~1 file of code. Dep-version coordination across two repos. |

**Recommended: Option B.**

Impact on Package.swift:

```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
    .package(url: "https://github.com/vapor/fluent-kit", from: "1.48.0"),
],
products: [
    .library(name: "SwiftIdempotency", ...),
    .library(name: "SwiftIdempotencyTestSupport", ...),
    .library(name: "SwiftIdempotencyFluent", targets: ["SwiftIdempotencyFluent"]),
],
targets: [
    // ...existing targets...
    .target(
        name: "SwiftIdempotencyFluent",
        dependencies: [
            "SwiftIdempotency",
            .product(name: "FluentKit", package: "fluent-kit"),
        ]
    ),
],
```

Adopter-side Package.swift gains one product line:

```swift
.product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
.product(name: "SwiftIdempotencyFluent", package: "SwiftIdempotency"),  // ← new
```

Non-Fluent adopters don't touch this. They never pay the FluentKit
compile cost.

### Decision 2 — Constructor shape: `IdempotencyKey.init(fromFluentModel:)`

Three options:

| Option | Call site | Verdict |
|---|---|---|
| **B1: init on IdempotencyKey** | `try IdempotencyKey(fromFluentModel: acronym)` | ✅ Consistent with existing `init(fromEntity:)`, `init(fromAuditedString:)`. Discoverable from the type's API surface. |
| B2: extension on Model | `try acronym.makeIdempotencyKey()` | Readable but: (a) pollutes every Fluent Model's method surface, (b) adopters looking in `IdempotencyKey`'s API surface won't find it. |
| B3: free function | `try idempotencyKey(from: acronym)` | Swift idioms discourage top-level functions for this. Least discoverable. |

**Recommended: Option B1.**

Implementation:

```swift
// Sources/SwiftIdempotencyFluent/IdempotencyKey+Fluent.swift
import FluentKit
import SwiftIdempotency

public extension IdempotencyKey {

    /// Construct a key from a Fluent Model's primary key. Use this on
    /// post-save Models — the Model's `id` must be non-nil when the
    /// initializer runs. For create handlers (pre-save), use
    /// `init(fromAuditedString:)` over a client-supplied or business
    /// key instead (the pre-save id is nil; there's no stable key to
    /// source here).
    ///
    /// This initializer exists because Fluent Models don't conform
    /// to `Identifiable` and their `id: IDValue?` Optional makes them
    /// unreachable by the generic `init(fromEntity:)` constructor.
    /// The synthetic-swiftdata trial confirmed this gap is
    /// Fluent-specific; non-Fluent Identifiable types reach
    /// `fromEntity:` cleanly.
    ///
    /// - Throws: `FluentError.idRequired` if the Model's id is nil
    ///   (the same error `model.requireID()` throws).
    init<M: Model>(fromFluentModel model: M) throws
    where M.IDValue: CustomStringConvertible {
        let id = try model.requireID()
        self.init(fromAuditedString: String(describing: id))
    }
}
```

Generic constraints:
- `M: Model` — the FluentKit Model protocol (imports FluentKit).
- `where M.IDValue: CustomStringConvertible` — covers UUID, Int,
  String, and typed wrappers around those (the common cases).
  Composite IDs are rejected at the call site with a clean
  compile error; adopters using composite IDs route through
  `fromAuditedString:` on a manually-composed string.

### Decision 3 — Failure mode: throwing initializer

Three options on handling the nil-id case (pre-save Model passed
to a post-save-assuming constructor):

| Option | Signature | Verdict |
|---|---|---|
| C1: precondition-crash | `init(fromFluentModel:)` silent crash on nil | ❌ Drops the entire test process on misuse. Silent failure mode. |
| **C2: throwing init** | `init(fromFluentModel:) throws` | ✅ Uses FluentKit's own `requireID()` throw; callers see explicit `try` at the call site. Matches Fluent's ergonomic conventions. |
| C3: failable init | `init?(fromFluentModel:)` | Less informative than throwing (loses the error cause); adopter has to check + manufacture their own error. |

**Recommended: Option C2 (throwing).**

`FluentError.idRequired` is Fluent's canonical error for this
case. Routing through it keeps the error type stable across
Fluent versions.

## Call-site shape + hellovapor migration

**Before (current hellovapor trial migration.diff @ line 80-90):**

```swift
struct IdentifiableAcronym: Identifiable {
    let acronym: Acronym
    var id: UUID { acronym.id! } // post-save force-unwrap
    init(_ acronym: Acronym) { self.acronym = acronym }
}

func createAcronymHandler(...) async throws -> Acronym {
    let acronym = Acronym(short: short, long: long)
    try await acronym.save(on: req.db)
    let key = IdempotencyKey(fromEntity: IdentifiableAcronym(acronym))
    // ... use key
    return acronym
}
```

**After (with `SwiftIdempotencyFluent`):**

```swift
import SwiftIdempotencyFluent

func createAcronymHandler(...) async throws -> Acronym {
    let acronym = Acronym(short: short, long: long)
    try await acronym.save(on: req.db)
    let key = try IdempotencyKey(fromFluentModel: acronym)
    // ... use key
    return acronym
}
```

Removes: the `IdentifiableAcronym` adapter struct (~5 LOC per
Model the adopter keys on), the force-unwrap, the import mental
model ("Identifiable adapter for Fluent") — replaced with the
direct `try` that documents the failure mode inline.

**Cross-Model scaling:** an adopter with N Fluent Models to key
on previously needed N adapter structs. With the Fluent
constructor, zero additional per-Model code is required. The
savings compound linearly.

## Compile-time story

`IdempotencyKey(fromFluentModel: someNonFluentType)` produces:

```
error: initializer 'init(fromFluentModel:)' requires that
       'SomeType' conform to 'Model'
```

Clear compile-error, adopter knows exactly which constraint they
violated.

`IdempotencyKey(fromFluentModel: compositeIDModel)` produces:

```
error: initializer 'init(fromFluentModel:)' requires that
       'CompositeIDModel.IDValue' conform to 'CustomStringConvertible'
```

Again clean. The adopter then reaches for `fromAuditedString:`
on a composed string, which is the right path for composite IDs
anyway.

## Testing strategy

Three levels:

1. **Unit tests in SwiftIdempotencyFluent.**
   New `Tests/SwiftIdempotencyFluentTests/` target covering:
   - Post-save Model → constructor succeeds with expected rawValue.
   - Pre-save Model → constructor throws `FluentError.idRequired`.
   - UUID / Int / String IDValue types → each produces the expected
     stringification.
   - Composite-ID Model → compile error (verified via a negative-
     compile-test documented in comments, not executed).

2. **Examples sample under `examples/fluent-sample/`.**
   Small SPM package exercising the Fluent constructor end-to-end
   against an in-memory SQLite Fluent database. Mirrors the
   existing `webhook-handler-sample/` / `assert-idempotent-sample/`
   pattern.

3. **hellovapor package-trial re-run.**
   Re-migrate the `package-integration-trial` branch on
   `Joseph-Cursio/HelloVapor-idempotency-trial` to use the new
   constructor. Verify:
   - Remove the `IdentifiableAcronym` adapter struct.
   - Update the `IdempotencyKey` construction site.
   - Re-run the existing 5 tests; confirm still-passing.
   - Measure the migration.diff delta (LOC removed).

The hellovapor re-run is the "real-adopter validation" gate from
the retrospective. Must pass before the v0.2.0 (or wherever it
lands) tag.

## Version + release plan

Target: **v0.2.0** (additive API; no breaking changes).
Rationale: introducing a new public product and a new init is a
SemVer minor bump. Existing v0.1.0 adopters continue compiling
without change.

Release-note changelog entry shape:

- **New:** `SwiftIdempotencyFluent` product provides
  `IdempotencyKey.init(fromFluentModel:)` for Fluent `Model`
  types. Removes the need for per-Model `Identifiable`-adapter
  structs documented in the v0.1.0 README.
- **Migration note:** no action required for v0.1.0 adopters.
  Fluent adopters who added `IdentifiableAcronym`-style adapter
  structs can remove them; the bare Fluent Model now suffices.

## Open questions

1. **FluentKit minimum version.** `from: "1.48.0"` is a recent
   stable. Should we pin more conservatively
   (`from: "1.40.0"`) for broader Fluent adopter compatibility?
   The `Model.requireID()` + `IDValue` associated-type have been
   stable for years; a conservative pin is likely fine.
2. **Documentation target for SPI.** Should `.spi.yml` be
   updated to also build docs for `SwiftIdempotencyFluent`?
   Probably yes — keep discovery of the Fluent init paired with
   the main target.
3. **Bump SwiftIdempotency's deployment targets?** No — the
   Fluent-kit target-compatibility story is independent; Fluent
   adopters have their own platform floor. `SwiftIdempotencyFluent`
   can inherit the existing `SwiftIdempotency` platform list.

## Implementation estimate

- Design doc (this): done.
- Package.swift + target + source file: ~30 min.
- Unit tests: ~30 min.
- examples/fluent-sample: ~45 min.
- hellovapor re-run: ~45 min.
- Release prep + tag + SPI update: ~20 min.

**Total: ~2.5-3 hours.** A single-session slice.

## Decision checklist

Before implementation, confirm:

- [ ] **Dep strategy:** separate product `SwiftIdempotencyFluent`
      (vs conditional compile / separate repo)?
- [ ] **Constructor shape:** `IdempotencyKey.init(fromFluentModel:)`
      (vs extension on Model / free function)?
- [ ] **Failure mode:** throwing via `requireID()`
      (vs precondition / failable)?
- [ ] **Version bump:** v0.2.0 (additive)?
- [ ] **Validation gate:** hellovapor re-run required before tag?
- [ ] **FluentKit min pin:** `from: "1.48.0"` or more conservative?
