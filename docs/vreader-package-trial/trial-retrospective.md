# vreader — Package Integration Trial Retrospective

Session-end summary. See [`trial-findings.md`](trial-findings.md)
for the empirical record; this doc is the "what would change
next time + what ships" layer.

## Did the scope hold?

**Yes.** Test-target-only, three tests, one new test file.
External-adoption signal for SwiftData is now positive — the
macro surface integrates cleanly with real-adopter iOS-app code.
The v0.2.0 → vreader integration is a reproducible shape for
future iOS-app trials.

**What scoped in unexpectedly:** the XcodeGen round-trip
friction (Finding 2) cost ~15 min of exploratory detour before
falling back to hand-edited pbxproj. Not a trial-scope expansion
— a reminder that "use the project's native tooling"
assumptions don't always hold on hybrid XcodeGen-plus-checked-in-pbxproj
projects.

**What scoped out:** a main-target handler migration. The
package_adoption_test_plan's "one handler, one test" shape was
covered by the luka-vapor/hellovapor trials; this trial
validates the **test-surface** path against real adopter code
without requiring the handler-refactor overhead.

## What would have changed the outcome — counterfactuals

### "If TeymiaHabit had compiled cleanly"

TeymiaHabit was the first-pick candidate (17 stars vs vreader's
6) but had a pre-existing baseline bug (a stray `TODO` literal
on `WeeklyHabitChart.swift:69`). Had TeymiaHabit been pickable,
the trial would have landed on its habit-tracking
domain — arguably a cleaner fit for idempotency discussion
("log habit completion" is a canonical dedup-gate shape). The
end-result macro-surface findings likely would have been
similar (AnnotationNote's business-named-UUID → also appears in
TeymiaHabit's `Habit.uuid: UUID`).

### "If vreader had only a Package.swift, no XcodeGen"

The XcodeGen round-trip friction would not have surfaced.
pbxproj hand-editing would still have been required, but the
trial would have had one less ergonomic finding. Trade-off:
we'd have learned less about the XcodeGen adopter pattern.

### "If we had used Xcode GUI to add the Package Dependency"

Would have been a 30-second task (Package Dependencies tab,
paste URL, pick version). But the trial was run from Claude
Code CLI, no GUI. The pbxproj hand-edit is the machine-automated
equivalent. Documenting the six-step sequence as a repeatable
procedure is a trial deliverable worth preserving.

## Recommendations for the package

Prioritised, highest value first.

### P1 — README doc update: SwiftData business-named-UUID pattern

**Evidence:** Finding 1. vreader's `AnnotationNote` has
`annotationId: UUID` — `fromEntity:` doesn't reach it, adopter
needs `fromAuditedString:` over the stringified UUID OR an
explicit `typealias ID = UUID; var id: UUID { annotationId }`
opt-in.

**Recommended edit:** add a "Using with SwiftData" section to
the README, mirroring the existing "Using with Fluent ORM"
section. Cover:

1. **Clean path** — adopter names their identifier `id: UUID`
   or `id: String` directly. `fromEntity:` works out of the box.
   Synthetic-swiftdata trial's `OfflineAlbum` is the reference.
2. **Business-named-UUID path** — adopter names identifier
   something else (`annotationId`, `uuid`, `pk`). Two options:
   (a) `IdempotencyKey(fromAuditedString: model.annotationId.uuidString)`
   (canonical path, zero boilerplate);
   (b) opt into `fromEntity:` via `typealias ID = UUID` +
   `var id: UUID { annotationId }` + `: Identifiable`
   conformance (three lines per Model).
3. **`@Attribute(.unique)` on `id`** — recommend this pattern
   so the SwiftData-layer dedup invariant matches the
   IdempotencyKey-layer guarantee.

**Ship vector:** direct-to-main (docs). No API change. Deferred
post-v0.2.0; targets a v0.2.1 docs-only bump or rolls into the
next feature release.

### P2 — Consider `IdempotencyKey.init(fromUUID:)` if friction recurs

**Evidence:** Finding 1's workaround is verbose
(`fromAuditedString: uuid.uuidString`). Not a v0.3.0 must-ship
— the verbosity is bearable — but worth re-evaluating if a
third iOS-adopter trial surfaces the same business-named-UUID
friction and pushes on it.

**Ship vector:** post-v0.3.0 API slice, gated on a second
independent piece of friction evidence.

### P3 — Fold the six-step pbxproj procedure into the test plan

**Evidence:** Finding 3's pbxproj-edit procedure is currently
documented only in this trial's findings. Future iOS-app
adopter trials would benefit from having it in
`package_adoption_test_plan.md` §"Per-trial protocol" /
§"Migration" as a checklist:

```
For iOS-app / xcodebuild-based trials:
1. Edit .xcodeproj/project.pbxproj to add:
   (a) `XCRemoteSwiftPackageReference` section
   (b) `XCSwiftPackageProductDependency` section
   (c) `packageReferences = ...` on `PBXProject`
   (d) `packageProductDependencies = ...` on the target
   (e) `PBXFrameworksBuildPhase` with a `PBXBuildFile`
       referencing the product (if target has no existing
       Frameworks phase)
   (f) Target's `buildPhases` array entry for (e)
2. `plutil -lint` after each edit to catch syntax errors.
3. `xcodebuild … -resolvePackageDependencies` to fetch and
   verify the package graph resolves.
4. `xcodebuild … build-for-testing` to compile with the new
   dep.
5. `xcodebuild … test-without-building -only-testing:...` to
   run only the new tests.
```

**Ship vector:** small docs edit to
`package_adoption_test_plan.md`. Direct-to-main.

## Policy notes for the test plan

Fold into `package_adoption_test_plan.md` §"Per-trial
protocol" / §"Pick target + feature combination":

1. **iOS-app trials are a legitimate shape** alongside
   SPM-based trials. xcodebuild + simulator test loop costs
   ~25s per iteration, ~2:25 cold full build — workable.
2. **Hybrid XcodeGen+pbxproj projects** (project.yml *and*
   checked-in .xcodeproj) may not round-trip cleanly on
   `xcodegen generate`. Verify by regenerating and building
   baseline BEFORE using xcodegen to add the dep; hand-edit
   pbxproj if regen breaks resource handling.
3. **Baseline-build verification filter** continues to be the
   right first-step gate. TeymiaHabit was filtered out by this
   check (Finding 2's sibling in the scope-doc's candidate
   table) — saved an open-ended debugging session.

## Follow-ups on what we found

### README SwiftData section (P1)

Drafts the structural parallel to the v0.2.0 "Using with Fluent
ORM" section. Worth shipping direct-to-main as a v0.2.x docs
update.

### Cross-adopter friction tally

The business-named-UUID pattern:

- **Confirmed in:** vreader (this trial), TeymiaHabit (baseline
  didn't build, but the `Habit.uuid: UUID` pattern was
  observed during inspection).
- **Not observed in:** synthetic (deliberately used
  `id: String`), luka-vapor (no SwiftData), hellovapor (Fluent
  Optional UUID, not SwiftData).

**Cross-trial evidence: 2 of 2 real iOS SwiftData adopters use
the business-named pattern.** One more independent adopter
(post-v0.2.0, e.g. a future SwiftData trial on a third iOS app)
would take this from "empirical pattern" to "shape-strong
recommendation for a dedicated API path." Not there yet.

### Trial artifact index

All four package-adoption trials + attempts now have artifact
sets:

- `luka-vapor-package-trial/` — first trial (Redis + APNS,
  trivial-return).
- `hellovapor-package-trial/` — second trial (Fluent Model,
  Optional UUID).
- `synthetic-swiftdata-package-trial/` — third trial (synthetic
  with `id: String`).
- `ampfin-package-trial/` — attempted, pivoted (Swift 6.3
  toolchain drift on legacy @Model).
- **`vreader-package-trial/`** — fourth, complete (this).

## Open questions this trial did NOT answer

- **Does `@ExternallyIdempotent(by:)` work on a real-adopter iOS
  handler?** Not exercised; the trial stayed test-target-only.
  A handler-migration trial on the same vreader fork would
  answer this — probably a future slice if adopter-engagement
  becomes a priority.
- **SwiftProjectLint scan on SwiftData @Model code.** No SwiftData-
  specific linter slices exist yet. If one gets proposed
  (e.g., a linter rule detecting `ModelContext.insert` in a
  `retry_safe` context without a dedup gate), the vreader fork
  would be a good validation target.

None of these gate a future release. The trial closes its
scope cleanly and its findings are all doc-update-shaped or
future-slice candidates.
