# vreader — Package Integration Trial Findings

Fourth package-adoption trial. See
[`trial-scope.md`](trial-scope.md) for pinned context and
pre-committed questions.

## Overall outcome

**3/3 tests passing on iPhone 17 simulator (Xcode 26.4.1, iOS
26, Swift 6.3.1).** External-adoption signal for SwiftData is now
positive — SwiftIdempotency v0.2.0 compiles in a real iOS
adopter's dep graph and runs the macro surface against
adopter-authored `@Model` types.

**Two substantive findings beyond the synthetic trial:**

1. **P1 — `IdempotencyKey(fromEntity:)` hits a compile-time
   ceiling on business-named UUIDs.** AnnotationNote's `@Attribute(.unique)
   var annotationId: UUID` (not named `id`) means Swift's
   `Identifiable` synthesis falls through to SwiftData's default
   `id: PersistentIdentifier`, which isn't `CustomStringConvertible`.
   The synthetic trial's "`fromEntity:` works on SwiftData @Model"
   finding applies only when the adopter names their identifier
   `id` — not when they use a business name (which is common in
   iOS apps).
2. **P2 — XcodeGen regen doesn't round-trip vreader's pbxproj.**
   Regenerating via `xcodegen generate` produces ~4 additional
   resource file refs that collide with the existing pbxproj's
   resource handling ("Multiple commands produce" errors on 5
   JS files). Hand-editing pbxproj is the reliable path for
   this project. Adopters using XcodeGen natively (no
   pre-existing pbxproj) wouldn't hit this; adopters with a
   checked-in pbxproj that they *also* have a project.yml for
   (vreader's pattern) should not assume xcodegen regenerate
   is a clean path to add a Package dep.

**Trial-fork commit:** [`Joseph-Cursio/vreader-idempotency-trial@8c010ea`](https://github.com/Joseph-Cursio/vreader-idempotency-trial/commit/8c010ea)
on `package-integration-trial`.

## Compilation log

| Attempt | Result | Friction |
|---|---|---|
| Baseline build (`xcodebuild … build`) | ✅ BUILD SUCCEEDED | No changes needed; vreader compiles cleanly on current Xcode 26.4.1. |
| XcodeGen regen after adding `packages:` block | ❌ Duplicate-output errors on 5 JS resource files | xcodegen added resources as individual files while the pre-existing pbxproj had folder-ref'd them. Reverted to hand-edit path. |
| Hand-edit 1 — add `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + `packageReferences` (PBXProject) + `packageProductDependencies` (vreaderTests) | ❌ "unable to resolve module dependency: 'SwiftIdempotency'" at test-file import site | Swift Package product listed in target's productDependencies wasn't enough — Xcode also required a `PBXFrameworksBuildPhase` linking the product via a `PBXBuildFile` (`productRef = …`). |
| Hand-edit 2 — add `PBXFrameworksBuildPhase` to vreaderTests target + `SwiftIdempotency in Frameworks` BuildFile | ✅ `** TEST BUILD SUCCEEDED **` | — |
| Test run (`-only-testing:vreaderTests/AnnotationNoteIdempotencyTests`) | ✅ 3/3 pass | Wall clock: ~25s (simulator boot + test execution). |
| Experimental `IdempotencyKey(fromEntity: annotation)` | ❌ compile error as predicted | Exact error recorded in Finding 1. |

## Build-time delta

| State | Cold build (test target) |
|---|---|
| Baseline (vreader main target only) | ~1:45 |
| With SwiftIdempotency dep (vreader + vreaderTests) | ~2:25 |
| **Delta** | **~+40s** |

Resolved package graph: 13 transitive packages
(`swift-collections, swift-distributed-tracing,
swift-service-context, swift-async-algorithms, swift-log,
swift-syntax, swift-atomics, swift-nio, sql-kit, swift-system,
fluent-kit, swift-service-lifecycle, SwiftIdempotency`). The
FluentKit + NIO + SQL-Kit subgraph is pulled in *at resolution
time* even though vreaderTests only imports `SwiftIdempotency`
(not `SwiftIdempotencyFluent`) — these are transitive deps of
the v0.2.0 package graph. Resolution is not zero-cost for
non-Fluent adopters, but **compile cost remains zero** for
non-Fluent adopters (FluentKit's targets are not compiled since
nothing depends on the `SwiftIdempotencyFluent` product).

Test-loop time (after initial build): ~25s per
`test-without-building` cycle. Heavier than `swift test`'s <1s,
but acceptable for an iOS-app trial.

## API friction log

### Finding 1 (P1) — `fromEntity:` unreachable on business-named UUID Models

**Evidence:** experimental compile attempt (removed before
commit; documented inline in the trial's test file).

```swift
let annotation = AnnotationNote(
    annotationId: UUID(),
    locator: AnnotationNoteIdempotencyTests.sampleLocator,
    content: "test"
)
let key = IdempotencyKey(fromEntity: annotation)  // ❌
```

**Exact error** (Xcode 26.4.1 / Swift 6.3.1):

```
error: initializer 'init(fromEntity:)' requires that
'PersistentIdentifier' conform to 'CustomStringConvertible'
  let key = IdempotencyKey(fromEntity: annotation)
public init<E>(fromEntity entity: E) where E : Identifiable,
                                            E.ID : CustomStringConvertible
```

**Root cause:** AnnotationNote's stable identifier is
`annotationId: UUID`, not `id`. Swift's `Identifiable`
synthesis does **not** pick up a differently-named property —
it requires either a member named `id` or an explicit
`typealias ID = ...`. Absent both, SwiftData's `@Model` macro
provides a default `id` via `PersistentIdentifier` (the per-row
SwiftData identity). `PersistentIdentifier` does not conform to
`CustomStringConvertible`, so the `IdempotencyKey(fromEntity:)`
constraint rejects this at compile time.

**Cross-trial comparison:**

- Synthetic trial's `OfflineAlbum` declared `var id: String`
  explicitly → `fromEntity:` worked.
- vreader's `AnnotationNote` declares `var annotationId: UUID`
  → `fromEntity:` fails.

The synthetic trial's positive finding does not generalize to
the business-named-UUID pattern that's typical of real iOS
apps. This isn't a bug in the API — it's an adopter-side
constraint with three workaround paths:

1. **`IdempotencyKey(fromAuditedString: model.annotationId.uuidString)`**
   — the canonical path for business-named UUIDs. This is what
   the trial's passing tests use.
2. **`typealias ID = UUID` + `var id: UUID { annotationId }`
   + `: Identifiable` conformance** — ~3 lines of adopter-side
   boilerplate per Model. Makes `fromEntity:` work but costs
   per-Model repetition.
3. **Future API addition:** a dedicated `IdempotencyKey.init(fromUUID:)`
   overload that takes a UUID directly would be a
   one-line call site with no adopter-side boilerplate. See
   "Implications for post-v0.2.0 API" below.

**Recommendation:** README update. The v0.2.0 README's "Using
with Fluent ORM" section documents the Fluent-adapter pattern;
a similar SwiftData section should call out the business-named-UUID
friction and recommend `fromAuditedString:` as the canonical
path. This was an inferrable finding from the synthetic trial
(which used `id: String` deliberately), but the **empirical
evidence against a real iOS adopter's actual code shape** makes
the friction concrete.

### Finding 2 (P2) — XcodeGen regen doesn't round-trip pre-existing pbxproj

**Evidence:** `xcodegen generate` followed by `xcodebuild build`
produced:

```
error: Multiple commands produce '…Debug-iphonesimulator/vreader.app/epubcfi.js'
error: Multiple commands produce '…/footnotes.js'
error: Multiple commands produce '…/overlayer.js'
error: Multiple commands produce '…/text-walker.js'
error: Multiple commands produce '…/tts.js'
```

**Root cause:** vreader's source tree has `vreader/Services/Foliate/JS/*.js`
AND `vreader/Services/EPUB/FoliateJS/overlayer.js` (and others).
xcodegen's `sources: [{path: vreader, excludes: [...]}]` pattern
adds ALL `.js` files under `vreader/` as distinct Resources
entries. Xcode's Copy Resources build phase then sees two files
with the same basename (`overlayer.js` in two different dirs)
copying to the same `.app/overlayer.js` destination and raises
"Multiple commands produce". The pre-existing pbxproj (checked
in at upstream `64dd940`) must have excluded one of the two
directories, but xcodegen doesn't automatically preserve that
exclusion.

**Consequence:** adopters with a pre-existing Xcode project AND
an `xcodegen` project.yml in the repo (a hybrid pattern vreader
uses) cannot rely on `xcodegen generate` to add a Package dep
cleanly — the regenerated pbxproj may subtly differ on resource
handling. Hand-editing the pbxproj to add just the package
stanzas is the reliable path.

**Scope:** this is an XcodeGen + vreader-specific issue, not a
SwiftIdempotency issue. Documented here because it costs ~15 min
of trial budget on any future XcodeGen-using adopter.

### Finding 3 — Swift Package product requires a Frameworks build phase (even when target has none)

**Evidence:** adding `packageProductDependencies = (AA01...002
/* SwiftIdempotency */);` to the vreaderTests PBXNativeTarget
was insufficient — Xcode reported `unable to resolve module
dependency: 'SwiftIdempotency'` at the test file's
`import SwiftIdempotency`.

**Root cause:** vreaderTests had buildPhases `(Sources,
Resources)` only, no Frameworks phase. `packageProductDependencies`
alone declares the product as a dep of the target but does not
link it — Xcode requires a `PBXFrameworksBuildPhase` containing
a `PBXBuildFile` entry that references the product
(`productRef = … /* SwiftIdempotency */;`). Once added, the
module resolves cleanly.

**Consequence:** documentation-only. Adopters using Xcode's UI
to add a Package Dependency get the Frameworks phase created
automatically; the friction is specific to hand-editing pbxproj.

## Pre-committed questions — answers

### 1. SwiftIdempotency v0.2.0 on iOS — clean compile?

**Yes.** After the pbxproj wiring was correct, SwiftIdempotency
compiled in vreader's iOS dep graph without iOS-specific gotchas.
No platform-guard issues, no module-resolution issues once the
Frameworks phase was in place (Finding 3).

### 2. `IdempotencyKey(fromEntity: annotationNote)` — compile-success or compile-error?

**Compile-error** per Finding 1. The prediction held; the exact
error text is captured. vreader's business-named-UUID pattern
doesn't reach `fromEntity:` without adopter-side boilerplate.

### 3. xcodebuild test loop viability

**Acceptable.** Initial full build ~2:25, test-without-building
subsequent iterations ~25s. Usable for a development loop, not
near `swift test`'s <1s. Full-session wall-clock budget for the
trial: ~45 min (baseline verify + fork + pbxproj wiring +
test-writing + running + doc).

### 4. Xcode Package Dependency integration via pbxproj edit

**Workable but fragile.** Four sections of the pbxproj needed
edits:

1. Add `XCRemoteSwiftPackageReference` (package URL + version
   requirement).
2. Add `XCSwiftPackageProductDependency` (product name).
3. Add `packageReferences = (...)` to `PBXProject`.
4. Add `packageProductDependencies = (...)` to target.
5. Add `PBXFrameworksBuildPhase` with a `PBXBuildFile`
   referencing the product — only needed if the target has no
   existing Frameworks phase (Finding 3).
6. Add `AA01.../Frameworks` to target's `buildPhases` array.

Any missed step causes a build error with a different error
surface — misleading until debugged. `plutil -lint` catches
syntax errors but not semantic issues.

## Comparison to predicted outcomes

| Prediction | Actual | Match? |
|---|---|---|
| SwiftIdempotency compiles cleanly in iOS dep graph | Confirmed | ✅ |
| `fromEntity:` on business-named UUID fails compile | Confirmed — exact error captured | ✅ |
| xcodebuild test loop ~30-60s | ~25s steady-state, ~2:25 cold | ✅ |
| pbxproj edit is fragile | Confirmed + Finding 3 added a sixth step | ✅ |

**Unpredicted findings:**

- XcodeGen regen breakage (Finding 2).
- Frameworks build phase required for `packageProductDependencies`
  to resolve module imports (Finding 3).

## Implications for post-v0.2.0 API roadmap

Finding 1 suggests a candidate API addition worth evaluating:

### Candidate — `IdempotencyKey.init(fromUUID:)` or similar

A dedicated UUID-typed initializer would close the
business-named-UUID friction in one call-site line:

```swift
// Current workaround (canonical, works today):
let key = IdempotencyKey(fromAuditedString: annotation.annotationId.uuidString)

// Candidate (post-v0.2.0):
let key = IdempotencyKey(fromUUID: annotation.annotationId)
```

**Trade-offs:**

- **For:** removes a `.uuidString` + audit-hatch cognitive load.
  UUID is a sufficiently-specific type that the "audit" step
  (inherent in `fromAuditedString:`) is redundant for it.
- **Against:** `IdempotencyKey(fromAuditedString: uuid.uuidString)`
  is 13 characters longer. Not much friction in absolute terms.
- **Against:** another initializer to learn. The API surface
  grows.
- **Against:** other stable ID types (Int, String) would have
  parallel claims. Ends up as N initializers or a generic path
  that's equivalent to `fromEntity:` — which already exists.

**Verdict:** not a v0.3.0 must-ship. Leave the friction
documented; `fromAuditedString: uuid.uuidString` is a fine
canonical path. Re-evaluate if a second adopter-trial surfaces
the same friction and pushes on the ergonomic ceiling.

### Candidate — document the typealias-based fromEntity path

A simpler, no-API-change fix is to document the adopter-side
typealias pattern in the README:

```swift
@Model
final class AnnotationNote: Identifiable {
    @Attribute(.unique) var annotationId: UUID
    // ...

    // Opt in to `IdempotencyKey(fromEntity:)`:
    typealias ID = UUID
    var id: UUID { annotationId }
}
```

Three lines of boilerplate, per Model. Worth documenting as an
opt-in for adopters who want `fromEntity:` ergonomics without
waiting on a new initializer. **This is recommended as a v0.2.x
README doc update** — cross-adopter friction across the
synthetic + vreader trials is enough to justify surfacing the
pattern.

## Trial-completion status

Per [`../package_adoption_test_plan.md`](../package_adoption_test_plan.md)
§"Completion criteria":

1. ✅ **Three adopter integrations complete, each with a
   distinct shape** — this trial is the *fourth* (luka-vapor +
   hellovapor + synthetic-swiftdata + vreader). Iterates on
   the criterion: iOS-app trial shape validated.
2. ✅ **No new P0 API-change requirements** — Finding 1 is a
   README doc update candidate (typealias pattern) or a P2
   API candidate; not P0.
3. ✅ **Linter parity** — met by prior trials. Not re-verified
   here (no SwiftProjectLint slice gates on SwiftData yet).

**Methodology validation:** xcodebuild + simulator trials are a
viable shape for iOS-app adopter trials going forward. The
pbxproj hand-edit procedure is documented as Finding 3's six
steps for any future iOS-app trial.
