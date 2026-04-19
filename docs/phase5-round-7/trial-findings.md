# Round 7 Trial Findings

First cross-package validation of the `SwiftIdempotency` macros package integrated with `SwiftProjectLint`. Sample package at `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/`, consuming the macros via a local-path dependency and producing 0 linter diagnostics on a realistic webhook-handler shape.

## Mechanism-by-mechanism result

| Mechanism | Status | Notes |
|---|---|---|
| Attribute-form annotations (`@Idempotent` et al.) | ✅ **works** | Linter's `EffectAnnotationParser` recognises the attribute form; 0 spurious diagnostics on the sample |
| `IdempotencyKey` strong type | ✅ **works** | `fromEntity:`-renamed construction path avoids the Codable `init(from:)` collision found during Phase 7 |
| `#assertIdempotent { body }` expression macro | ✅ **works** | Sample integration tests pass using both trailing-closure and explicit-paren forms |
| `@Idempotent` peer-macro test generation | ❌ **deferred** | Four cumulative Swift-macro-ecosystem frictions block the originally designed path |

Three of four mechanisms green end-to-end. The fourth has a complete unit-test surface (the macros package's `IdempotentPeerMacroTests` — 9 expansion tests pass) but fails in real integration. Root-cause analysis below.

## Swift-macro-ecosystem frictions surfaced

Each discovered during the trial by writing a sample and iterating on compile errors.

### Finding 1 — `IdempotencyKey(from:)` collides with `Codable.init(from:)`

**Discovered:** First compile attempt on the sample's `WebhookHandler.swift`.

**Symptom:**
```
error: argument type 'Gift' does not conform to expected type 'Decoder'
    idempotencyKey: IdempotencyKey(from: gift)
```

**Root cause:** The macros package declared two initialisers with external label `from`:

```swift
public init<E: Identifiable>(from entity: E) where E.ID: CustomStringConvertible
public init(from decoder: Decoder) throws   // synthesised by Codable conformance
```

Inside the macros package's own test suite, the Codable init was not reachable from the test module's scope, so `IdempotencyKey(from: event)` unambiguously selected the Identifiable initialiser. In a *consumer* module, the Codable conformance is fully visible and Swift's overload resolution preferred the concrete `Decoder` match over the generic `Identifiable` match — producing the "Gift does not conform to Decoder" error.

**Resolution:** Renamed the Identifiable initialiser's external label from `from` to `fromEntity`. Call sites become `IdempotencyKey(fromEntity: gift)`. Documentation, tests, and the sample all migrated.

**Lesson:** overload resolution in macro-consumer modules differs from macro-internal test modules. A design that "works in our tests" may fail in real adopter modules because Codable conformance visibility differs. Future public APIs should use explicit labels that can't collide with synthesised conformances.

### Finding 2 — `@attached(peer, names: arbitrary)` forbidden at global scope

**Discovered:** First build attempt of `WebhookHandler.swift` with `@Idempotent` on a top-level function.

**Symptom:**
```
error: 'peer' macros are not allowed to introduce arbitrary names at global scope
@Idempotent
^
```

**Root cause:** Swift's peer-macro name-coverage rules require `arbitrary`-named peers to be emitted at type-member scope. At global scope, the compiler cannot statically verify the peer's name, so it rejects the declaration.

**Initial fix attempt:** Switched to `@attached(peer, names: prefixed(testIdempotencyOf))`. This allows global-scope usage but constrains the emitted name to exact concatenation `testIdempotencyOf<name>` with no case change — producing names like `testIdempotencyOfpureMultiplier` that violate Swift naming convention.

**Subsequent fix attempt:** Reverted to `names: arbitrary` and moved the `@Idempotent` demo into a `@Suite struct` (type-member scope). This sidestepped the global-scope rule but triggered Finding 4.

**Current state:** `names: arbitrary` declared, but `@Idempotent` is no longer demonstrated in the sample's production code. The attribute still works as a linter-consumed annotation; only the peer-test-generation feature is deferred.

### Finding 3 — Macros cannot emit `import` statements

**Discovered:** While trying to wrap the generated `@Test` peer in `#if canImport(Testing) / import Testing / @Test func … / #endif` so production code without a Testing dependency would build cleanly.

**Symptom:**
```
error: macro expansion cannot introduce import
```

**Root cause:** Swift explicitly forbids macro-introduced imports to avoid confusion about which modules a file actually depends on. The rule is reasonable in isolation but removes a natural solution to the "this peer needs Testing, but production code doesn't import Testing" problem.

**Resolution:** The wrapping attempt was reverted. The `@Idempotent` peer-macro design therefore requires the enclosing module to have `import Testing` at file scope — which is natural for test targets but wrong for production modules. Documented as "`@Idempotent` belongs in test targets, not production code."

**Lesson:** peer macros that emit framework-dependent code (`@Test`, `#expect`) force the entire enclosing file to depend on that framework. There's no macro-emitted-import escape hatch. Users must pre-arrange the dependency at file scope.

### Finding 4 — Swift Testing's `@Test` interacts poorly with macro-emitted peers at type-member scope

**Discovered:** After moving the `@Idempotent` demo into a `@Suite struct` to satisfy Finding 2's constraints.

**Symptom:**
```
error: cannot use instance member '$s21…testIdempotencyOfPureMultiplier…generator…'
       within property initializer; property initializers run before
       'self' is available
error: properties with attribute @used must be static
error: properties with attribute @section must be static
```

**Root cause (partial):** Swift Testing's `@Test` macro expansion generates hidden properties annotated `@used` / `@section` for test discovery. When `@Test` is itself generated by another macro (peer expansion of `@Idempotent`), the nested expansion produces these properties in a context Swift Testing's machinery doesn't expect — specifically, inside a struct where `self` isn't yet available for the nested macros' internal state setup.

Hand-written `@Test` methods inside a `@Suite struct` work fine. Macro-emitted `@Test` methods inside the same context don't. The difference is likely about expansion ordering or macro-inside-macro scope tracking in Swift Testing, but the exact reproducer is deep in the Swift Testing / macro-expansion pipeline.

**Resolution:** Removed `@Idempotent` usage from the sample's test file. The macro's unit-test surface in the macros package remains green (`IdempotentPeerMacroTests` uses `assertMacroExpansion`, which doesn't trigger Swift Testing's runtime expansion). Real-integration usage is documented as a known limitation.

**Lesson:** macros that emit other-macros'-annotated code (especially `@Test`) have interaction fragility. The `assertMacroExpansion`-based test surface is necessary but not sufficient proof of correctness. Future macro work that emits `@Test`-decorated code should explicitly integration-test in a consumer-target context before shipping.

## Sample-level acceptance (what green looks like)

| Acceptance criterion | Result |
|---|---|
| Sample package builds clean | ✅ |
| Sample's test suite passes | ✅ (6/1 green) |
| Linter scans sample with 0 diagnostics | ✅ (post-lattice, replayable → externally_idempotent is legal) |
| All four mechanisms demonstrated in the sample | Partial — three work, `@Idempotent` peer-test documented as deferred |
| Every runtime / compile error recorded as a finding with resolution | ✅ (four findings above) |

## Macros package — post-R7 deltas

Edits landed during the trial:

- **`IdempotencyKey.init(fromEntity:)` rename** (Finding 1). Updated the macros package's own unit tests, the README, and the sample. 13/1 tests still green.
- **`names: arbitrary` restored on `@Idempotent`** after the round-trip through `prefixed(testIdempotencyOf)`. Expansion tests updated to match CamelCase emitted names.
- **Macro expansion no longer wraps in `#if canImport(Testing)`** (Finding 3 dictates this is the only viable shape). Expansion tests simplified back to bare `@Test func` emission.

Full macros package suite: **39 tests across 4 suites green** at trial end.

## Linter — post-R7 state

No edits required. The attribute-recognition work shipped in `SwiftProjectLint` `58d302d` remained correct under trial load — the attribute-form annotations on the sample fed the `idempotencyViolation` and `nonIdempotentInRetryContext` rules equivalently to doc-comment annotations, producing the expected 0-diagnostic result on the sample's valid call graph.

## Cross-round context

Round 7 is structurally different from rounds 1-6. Prior rounds measured the idempotency *rules* against real corpora (3909 file-scans, four distinct codebases). Round 7 measures *mechanism integration* — whether the macros package + linter fit together — against a purpose-built sample.

Findings valence also differs. Rounds 1-6 mostly confirmed shipped mechanisms; round 7 surfaced four architectural constraints that required in-trial fixes or documented limitations. The shift reflects the different maturity: the idempotency rules were designed against known real-code patterns; the macros package is a new distribution surface with Swift-macro-ecosystem boundaries nobody had exercised yet.

## Data committed

All trial artefacts:

- `docs/phase5-round-7/trial-scope.md` — this trial's contract
- `docs/phase5-round-7/trial-findings.md` — this document
- `docs/phase5-round-7/trial-retrospective.md` — next-step thinking
- `docs/phase5-round-7/trial-transcripts/linter-scan.txt` — `SwiftProjectLint` output on the sample (0 diagnostics)

Sample package retained at `/Users/joecursio/xcode_projects/SwiftIdempotencyPhase7Sample/` for future follow-up work. Not pushed anywhere. Macros and linter post-R7 edits committed separately to their respective main branches.
