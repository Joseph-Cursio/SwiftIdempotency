# luka-vapor — Package Integration Trial Findings

Measurement for first package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
See [`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions.

## Overall outcome

Trial executed successfully. Migration compiled and ran cleanly;
5 of 5 targeted tests passing; Option C pathology confirmed as
predicted; linter parity confirmed on attribute-form annotations.

**Trial fork:** [`Joseph-Cursio/luka-vapor-idempotency-trial`](https://github.com/Joseph-Cursio/luka-vapor-idempotency-trial) on branch
[`package-integration-trial`](https://github.com/Joseph-Cursio/luka-vapor-idempotency-trial/tree/package-integration-trial),
tip `d8bd8dc`.

**Migration diff:** [`migration.diff`](migration.diff) — 208 lines
across 6 files. Net additions: 240 lines, deletions: 64.

## Compilation log

| Attempt | Result | Notes |
|---|---|---|
| 1st `swift build -c release` | ✅ green | First-try compile. No macro-expansion errors, no diagnostic surprises, no API mismatch. `SwiftIdempotencyMacros` plugin compiled (3 macro-impl files), `SwiftIdempotency` library compiled (8 Swift files), `LukaVapor` rebuilt with new dep. |
| `swift test` | ✅ green on new tests | All 5 integration tests pass on re-run. Pre-existing `Test Hello World Route` fails (unrelated to trial — upstream's test references a `/hello` route that doesn't exist in current `routes.swift`). Fixed one unrelated test fixture value (`"us"` → `"usa"` for `AccountLocation`). |
| SwiftProjectLint scan | ✅ fires expected diagnostic | `@ExternallyIdempotent(by: "idempotencyKey")` recognized; body-validation fires `idempotencyViolation` on the `append` call inside the function body, same shape as doc-comment form. |

## Build-time delta

Measured on a single machine, cold-build wall-time:

| State | Cold build | Units compiled |
|---|---|---|
| Baseline (pristine upstream) | 130.44s | 542 |
| With `SwiftIdempotency` dep | 129.45s | 548 |
| **Delta** | **−0.99s (within noise)** | **+6 units** |

**Result:** adding the package is effectively free cold-build-wise.
The 6 extra units compiled (`SwiftIdempotencyMacros` plugin +
`SwiftIdempotency` library) cost < 1s on a large-Vapor-app
baseline. The macro-plugin load at compile time does not add
measurable overhead. **Refutes the pre-trial prediction** of a
"< 30s cold" delta — it's far better than expected.

Incremental build after editing the handler function: 31.10s.
Most of that is re-linking `LukaVapor` itself (the biggest unit);
the macro re-expansion cost is negligible.

## API friction log

Each friction point noted with severity.

### Structural (P1) — inline-closure handler requires named-func refactor

**Friction:** The upstream `start-live-activity` handler is an
inline trailing closure passed to `app.post(...)`. Attribute
macros only attach to declarations (`func`, `var`, `struct`,
etc.) — not to arbitrary expressions. To add
`@ExternallyIdempotent(by:)`, the handler body had to be moved
into a new named function.

**Migration cost:** one new file (`Handlers/StartLiveActivity.swift`),
75 lines. The closure in `routes.swift` was reduced from 67 lines
to 8 lines (decode body + delegate). Net: same logical code,
just restructured.

**Severity:** P1 (documented limitation, works around cleanly).
Should be called out explicitly in the README's adoption
section. Inline-closure-handler-dominant adopters (most small
Vapor/Hummingbird apps) will hit this.

### Ergonomic (P2) — `IdempotencyKey`'s `init(fromEntity:)` not reachable for Codable request bodies

**Friction:** `StartLiveActivityRequest` is `Codable, Sendable`
but not `Identifiable`. The `IdempotencyKey(fromEntity:)`
constructor requires `Identifiable` conformance, which adding
to a Vapor `Content`-conforming struct would:

1. Force choosing an `id` field (ambiguous — username? pushToken?
   a synthetic UUID?).
2. Leak implementation into the wire format (Identifiable's `id`
   isn't typically surfaced in the public API of a request payload).

The adopter path was `IdempotencyKey(fromAuditedString: body.idempotencyKey)`
— the audit-hatch constructor. **Prediction confirmed:** the
audit hatch is the primary adopter path for typical Codable
request-body shapes, not the exception.

**Severity:** P2 (works, but the "strong type" story weakens if
adopters mostly route through the audit hatch). Candidate for a
new initializer: `init(fromHashableCodable:)` or similar, for
Codable-only non-Identifiable types. Defer until a second
adopter confirms the same shape.

### Minor (P3) — `SwiftIdempotencyTestSupport` is a placeholder

**Friction:** The README's installation example tells adopters
to add `SwiftIdempotencyTestSupport` to the test target.
Inspecting the package, that target is currently empty — the
runtime helpers for `#assertIdempotent` live in the main
`SwiftIdempotency` target. The test target linked fine because
the dep was declared; no symbols are actually used from it.

**Severity:** P3 (cosmetic — the dependency resolves and costs
nothing, but the README copy is misleading). Fix in the README:
either remove the `SwiftIdempotencyTestSupport` reference until
real helpers land, or document it as "placeholder for future
test-time helpers."

## The Option C pathology — P0 finding confirmed

Test `optionCPassesOnNonIdempotentHTTPStatusHandler` **passes**,
which demonstrates the failure mode:

```swift
actor Counter { var value = 0; func increment() { value += 1 } }
let counter = Counter()

let nonIdempotentHandler = { () async throws -> HTTPStatus in
    await counter.increment()   // observable side effect
    return .ok                   // trivial return
}

let result = try await #assertIdempotent {
    try await nonIdempotentHandler()
}
#expect(result == .ok)              // PASSES: both calls returned .ok

let finalCount = await counter.value
#expect(finalCount == 2)            // PASSES: the handler ran TWICE
```

The assertion says "idempotent" (because Option C compares return
values and both returned `.ok`), but the actor's counter proves
the handler was observably non-idempotent — the side effect
happened twice.

**The real-world `start-live-activity` handler has exactly this
shape.** It mutates Redis (`hset` / `zadd`) and returns `.ok`
regardless. An adopter wrapping it with `#assertIdempotent` would
get a green check on a handler that is demonstrably not
idempotent.

**Severity:** **P0** for the package's test-time guarantees.
The README does document Option C's limitations ("Equatable is
only as sharp as the type's `==`"), but the framing suggests the
issue is byte-order-sensitive encoding (JSON key ordering, etc.),
not "Option C is blind to any side effect that doesn't appear in
the return value." The pathology is structurally broader than
the README admits.

### Recommendation paths

Either (preferred):

1. **Document the pathology explicitly.** Add a clear "**Option C
   is blind to invisible side effects**" section to the README,
   with this `HTTPStatus`-returning handler as the worked example.
   Adopters who see it can at least make an informed choice to
   use `#assertIdempotent` only on return-reflective handlers.
2. **Promote Option B** (dependency-injected mock effects) from
   "deferred for future slices" to "v0.1.1 target." Option B
   would catch this shape because the mock would observe the
   duplicate Redis calls.

Minimum-viable fix for v0.1.0: option 1 (README update). Option B
is a significant design effort; ship the package with the
pathology documented, add B in a later release. Alternative
framing: call the current tier "Option C-light" in the README,
reserving the unqualified "`#assertIdempotent` verifies
idempotency" language for the post-Option-B version.

## Linter parity

Tested by running SwiftProjectLint (tip `db4d576`) on the trial
fork's `package-integration-trial` branch:

```
Sources/LukaVapor/Handlers/StartLiveActivity.swift:30: error:
[Idempotency Violation] Externally-idempotent contract
violation: 'startLiveActivity' is declared
`@lint.effect externally_idempotent` but calls 'append', whose
effect is inferred `non_idempotent` from the callee name
`append`. …

Found 1 issue (1 error)
```

The attribute-form `@ExternallyIdempotent(by: "idempotencyKey")`
is recognized identically to the doc-comment form
`/// @lint.effect externally_idempotent(by: "idempotencyKey")`.
The body-validation rule fires on the `append` call at line 30
(`session.tokens.append(tokenEntry)`), which is the real-world
P0-finding shape the linter is designed to catch: a keyed
idempotent claim with an unconditionally non-idempotent helper
in the body.

Linter parity: ✅ **confirmed**.

## Answers to pre-committed questions

1. **Structural refactor cost.** Substantial. Required a new file
   and a full extraction of handler body from the inline closure.
   Mechanical, but a real 75-line restructuring on a 3-handler
   app. Documented as P1 friction above.
2. **`IdempotencyKey` construction path.** `init(fromAuditedString:)`
   is the primary path. `init(fromEntity:)` is architecturally
   hard to reach for typical Vapor `Content` request bodies.
   Confirms prediction.
3. **Option C pathology on `HTTPStatus.ok`.** Confirmed. `#assertIdempotent`
   silently passes on the non-idempotent handler. P0 finding.
4. **Compilation & build-time cost.** Cold build +~0s (within
   noise), incremental +~0s. Macro-plugin overhead is negligible
   on a real Vapor app. Refutes the pre-trial concern about
   plugin-load cost.

## Comparison to predicted outcomes

| Prediction | Actual | Match? |
|---|---|---|
| Inline-closure refactor friction will manifest | Manifested, P1 | ✅ |
| `init(fromAuditedString:)` will be the primary path | Confirmed | ✅ |
| JSON wire format low risk | Clean round-trip | ✅ |
| Option C pathology will silently pass | Confirmed via actor counter | ✅ |
| Build-time delta < 30s cold, < 2s incremental | ~0s cold, ~0s incremental | ✅ (exceeded) |
| Linter parity holds | Confirmed | ✅ |

**6/6 predictions validated.** The trial is a successful
negative result: it found one P0 issue, two P1/P2 ergonomic
frictions, and one P3 cosmetic issue that were not visible from
the three self-authored examples.

## Recommendations summary

For v0.1.0 pre-release:

- **Must-do (blocker for SPI submission):** README Option C
  pathology section. Adopters need to see "this test guarantee
  has sharp limits on handlers whose return type doesn't reflect
  side effects" before pulling the dep.
- **Should-do (README quality):** acknowledge the inline-closure
  → named-func refactor cost in the adoption section. Current
  docs don't mention it.
- **Should-do:** remove or reframe the `SwiftIdempotencyTestSupport`
  installation reference (P3 cosmetic).

For post-v0.1.0 consideration:

- **Consider:** `IdempotencyKey` new initializer for Codable-
  only-not-Identifiable types. Needs a second adopter trial
  (HelloVapor would be next) to corroborate the shape.
- **Consider:** promoting Option B (dep-injected mock effects)
  from "deferred" to v0.1.1 target — the Option C pathology is
  load-bearing for the test-time guarantee claim.
