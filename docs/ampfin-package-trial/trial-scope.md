# AmpFin — Package Integration Trial Scope

Third package-adoption trial per
[`../package_adoption_test_plan.md`](../package_adoption_test_plan.md).
Deliberate non-Fluent counter-case to the two prior trials:

- [luka-vapor](../luka-vapor-package-trial/trial-scope.md) — Fluent
  absent (Redis + APNS), return `HTTPStatus.ok`. Stressed Option C
  pathology.
- [hellovapor](../hellovapor-package-trial/trial-scope.md) — Fluent
  `Acronym` Model with `id: UUID?`. Surfaced two P0 API-constraint
  failures on `IdempotencyKey(fromEntity:)` (`Identifiable`
  conformance + `CustomStringConvertible` on Optional).

AmpFin is the decisive third shape: **SwiftData `@Model` +
reference-type `Identifiable` with non-Optional `id: String`**.
The research question from the hellovapor retrospective's
"Needs a third adopter trial (non-Fluent Identifiable type — Core
Data, SwiftData)" pivots entirely on this case.

## Research question

> **On a SwiftData-backed adopter whose Identifiable types declare
> a non-Optional `id: String` — both the `@Model` persistence type
> (`OfflineAlbumV2`) and the plain reference Identifiable it maps
> from (`AFFoundation.Item` / `Album`) — does
> `IdempotencyKey(fromEntity:)` reach its intended target without
> adopter-side adapter code? And does the answer invalidate or
> confirm the "Optional-ID pattern is Fluent-specific" hypothesis
> that would justify adding a Fluent-shaped constructor rather
> than relaxing the global `CustomStringConvertible` constraint?**

## Pinned context

- **SwiftIdempotency tip:** `fff6f08` (post-Fluent-README section
  ship — [`README.md:"Using with Fluent ORM"`](../../README.md)
  now documents the `IdentifiableAcronym` adapter pattern, the
  `init(fromAuditedString:)` header-sourced idiom, and the
  tuple-return workaround for `#assertIdempotent` on non-Equatable
  Fluent Models).
- **SwiftProjectLint tip:** `70f2d61` (post-slot-19 merge — the
  `import Fluent` meta-package alias gate that closed the
  hellovapor-trial-surfaced gap).
- **Upstream target:** `rasmuslos/AmpFin` @ `7233c63` (main,
  2025-11-14, "Update README.md"). License: `Other` — README
  allows non-commercial forks, sufficient for a research-shaped
  integration trial on a non-contribution fork.
- **Trial fork:** `Joseph-Cursio/AmpFin-idempotency-trial` (new
  — provisioning during the trial).
- **Trial branch:** `package-integration-trial`, forked from
  upstream `main` tip `7233c63`.
- **AmpFinKit platforms:** `iOS 17`, `tvOS 17`, `macOS 14`,
  `watchOS 10`, `visionOS 1`. Pure SPM sub-package with its own
  `Package.swift` — runs `swift test` from the command line on
  macOS 14+.

## Migration plan

**Target handler:** `OfflineManager.download(album:)` at
[`AmpFinKit/Sources/AFOffline/OfflineManager/OfflineManager+Album.swift:70-88`](https://github.com/rasmuslos/AmpFin/blob/7233c63/AmpFinKit/Sources/AFOffline/OfflineManager/OfflineManager%2BAlbum.swift#L70-L88).

This is an iOS-side "download an album for offline playback"
handler — a **dedup_guarded** shape in the lattice. The upstream
body is already idempotency-aware via an `if let existing` check
(lines 76-81); the non-idempotent primitive (`create(album:...)`
at line 16, which inserts into SwiftData without checking
membership) is shielded one level up. This is the boundary where
an `@ExternallyIdempotent(by:)` annotation earns its keep: the
public API is declared idempotent on its key `album.id`, the
private helper remains `non_idempotent`, and the linter flags
any future caller that forgets the dedup gate.

Current shape (upstream):

```swift
public func download(album: Album) async throws {
    let tracks = try await JellyfinClient.shared.tracks(albumId: album.id)
    let context = ModelContext(PersistenceManager.shared.modelContainer)
    let offlineAlbum: OfflineAlbum

    if let existing = try? self.offlineAlbum(albumId: album.id, context: context) {
        offlineAlbum = existing
        offlineAlbum.childrenIdentifiers = tracks.map { $0.id }
    } else {
        offlineAlbum = try create(album: album, tracks: tracks, context: context)
    }

    for track in tracks {
        download(track: track, context: context)
    }

    NotificationCenter.default.post(name: OfflineManager.itemDownloadStatusChanged, object: album.id)
}
```

Target shape (post-migration):

```swift
@ExternallyIdempotent(by: "idempotencyKey")
public func download(
    album: Album,
    idempotencyKey: IdempotencyKey
) async throws {
    // ... existing body unchanged ...
}
```

**Idempotency-key sourcing decision:** `album.id` is the natural
key — it's already what the `offlineAlbum(albumId:)` lookup and
the `NotificationCenter` post use. Caller wraps:

```swift
let key = IdempotencyKey(fromAuditedString: album.id)
try await OfflineManager.shared.download(album: album, idempotencyKey: key)
```

vs. the alternative `IdempotencyKey(fromEntity: album)` — which
is the **API-reachability question this trial is designed to
answer.** The scope includes both paths so the trial can compare.

## Test plan

AmpFinKit has **no existing test target** (per Package.swift at
pinned SHA). Add a new `AFOfflineTests` test target as part of
the migration. This is itself a trial data point — the test plan
has not yet measured the "zero-test adopter" starting friction.

Four test shapes in `Tests/AFOfflineTests/`:

1. **`IdempotencyKey(fromEntity:)` on `OfflineAlbumV2` —
   deciding question.** Construct an `OfflineAlbum` in-memory
   (SwiftData's in-memory `ModelContainer` configuration works
   without disk), pass to `fromEntity:`. Expected outcome:
   compiles cleanly, produces `"OfflineAlbumV2:<album-id-string>"`
   or equivalent deterministic key. If it fails to compile, the
   `@Model`-with-user-declared-`id: String` shape surfaces the
   Optional-ID pattern outside Fluent. If it succeeds, confirms
   the Fluent-specific hypothesis.

2. **`IdempotencyKey(fromEntity:)` on `AFFoundation.Album`.**
   Plain reference-type `Identifiable` with `id: String`. Simpler
   case than #1 — no SwiftData synthesis. Should succeed trivially.
   Positive control.

3. **`#assertIdempotent` on `download(album:idempotencyKey:)`.**
   Two calls with the same key → same `OfflineAlbum` row in
   SwiftData (`@Attribute(.unique)` on `id` makes this DB-level-
   deterministic). `#assertIdempotent` detects the dedup gate
   holding. Note: the body hits the network via `JellyfinClient`
   — the test needs to stub or skip the network call. Option C
   sharpness question — `Void`-returning `async throws` handler,
   so the same pathology as luka-vapor's `HTTPStatus.ok` case
   (Option C can't distinguish two `Void` returns). This is
   expected; the value of this test is **verifying the
   `@ExternallyIdempotent(by:)` annotation-plus-macro expansion
   compiles and flows the key correctly through the closure, not
   catching non-idempotency**.

4. **`#assertIdempotent` on `offlineAlbum(albumId:context:)`
   read path.** A fetch that returns `OfflineAlbum` — which is
   a non-Equatable reference class (no synthesised Equatable).
   Exercises the hellovapor-found workaround shape: must wrap
   in a tuple of value fields (`(album.id, album.name)`) or
   extend `Equatable`. Cross-adopter confirmation that the
   workaround is structural, not Fluent-specific.

## Scope commitment

- **One handler migrated, four tests added.** No other
  handlers (`delete`, `updateLastPlayed`, `download(track:)`,
  the OfflineManager+Playlist variants) migrated.
- **No upstream PR.** Non-contribution fork per the test plan.
- **In-memory SwiftData only.** Tests use
  `ModelConfiguration(isStoredInMemoryOnly: true)` — no disk,
  no network dependency (aside from stubbed `JellyfinClient`).
- **Swift-only test runner.** `swift test -c release` from
  `AmpFinKit/` root. No xcodebuild / simulator detour — the
  macOS 14 platform target already covers `@Model` at command
  line. Pins methodology to the luka-vapor/hellovapor shape.

## Pre-committed questions

1. **Does `IdempotencyKey(fromEntity:)` work out of the box on
   a SwiftData `@Model` with a user-declared `id: String`?**
   SwiftData's `@Model` macro synthesizes conformance to
   `PersistentModel: Identifiable` with `id: PersistentIdentifier`,
   but AmpFin declares its own `id: String`. Which conformance
   wins for `Identifiable` synthesis — the synthesized
   `PersistentIdentifier` one or the user's `String` one? If
   it's the `PersistentIdentifier` path, we hit the same
   `CustomStringConvertible` gap as Fluent (`PersistentIdentifier`
   is not `CustomStringConvertible`). If it's the `String` path,
   it should compile cleanly.

2. **Does `IdempotencyKey(fromEntity:)` work on plain
   reference-type `Identifiable` with `id: String`?** The
   `AFFoundation.Item` superclass conforms to `Identifiable`
   directly with `let id: String`. This is the purest
   non-Fluent case — no ORM layer in play. Expected trivial
   success. If this **fails** for any reason, the generalisation
   hypothesis is broken.

3. **Can `#assertIdempotent` on a reference-type `@Model`
   return work without Equatable extension?** `OfflineAlbum`
   is a non-Equatable `@Model final class`. Expected workaround
   is the tuple-pattern from the hellovapor trial. Capture the
   exact compile-error text + workaround shape.

4. **What's the refactor-scope cost for AmpFinKit's zero-test-
   target state?** Adding a new `.testTarget` in `Package.swift`,
   `Tests/AFOfflineTests/` directory, swift-testing-as-dep wiring.
   Documentation gap question: does the README's "Using without
   SwiftProjectLint" section cover this path?

## Predicted outcome

- **Friction 1 (SwiftData `@Model` `Identifiable` synthesis
  ambiguity):** medium-confidence prediction of a **new
  P0/P1 finding**. When `@Model` sees a user-declared
  `id: String`, the Swift compiler's `Identifiable` synthesis
  path is not obvious. Several scenarios:
  - (a) The user's `id: String` wins → works cleanly, clear
    generalisation signal.
  - (b) The synthesized `id: PersistentIdentifier` wins → the
    user's `id: String` is ignored, `fromEntity:` uses the
    identifier type we have no documented handling for.
  - (c) Ambiguity error → compile failure, adopter forced to
    write an explicit `typealias ID = String` or disambiguate.
  Outcome (b) or (c) produces a **new non-Fluent API constraint
  finding**; outcome (a) is the clean positive control.
- **Friction 2 (reference-type `Album`):** high-confidence
  clean success. No ORM synthesis in play.
- **Friction 3 (non-Equatable Model return in
  `#assertIdempotent`):** high-confidence structural reproduction
  of the hellovapor workaround. Cross-adopter confirmation is
  the value.
- **Friction 4 (zero-test-target adopter):** adds ~30-60 lines
  to `Package.swift` and requires a new `Tests/` directory. Not
  P0 but documentation-relevant.
- **Build-time delta:** ~0-5s cold on AmpFinKit umbrella build.
  Expected within luka-vapor/hellovapor's ±4s range.
- **Linter parity:** FluentKit gate irrelevant (no Fluent
  import); SwiftData gate doesn't exist in SwiftProjectLint yet.
  Worth checking: does the linter currently produce any output
  on the migrated handler at all? The likely answer is no —
  which is a **new 1-adopter candidate for a SwiftData persistence
  whitelist** (`ModelContext.save`, `ModelContext.insert`,
  `ModelContext.delete`). Cross-adopter accumulation via this
  trial; not slice-promote-eligible on one fire.

**Decision lever the trial turns:**

- If question 1 is outcome (a) + question 2 succeeds → the
  Optional-ID pattern is Fluent-specific; the recommended API
  change is a **Fluent-shaped constructor** (`init(fromFluentModel:)`
  or similar), not a global `CustomStringConvertible` relaxation.
- If question 1 is outcome (b) or (c) → non-Fluent Identifiable
  also exhibits constraint friction; favor the global **constraint
  relaxation** path (drop `CustomStringConvertible` in favour of
  `String(describing:)`, or a less demanding requirement).
- If question 2 fails (low probability but catastrophic) → the
  `fromEntity:` API has a fundamental flaw independent of ORM
  shape; rethink the constructor's design surface.

## Why AmpFin specifically

Three alternative candidates were considered. The disqualification
reasons are logged for future sessions:

- **Synthetic SwiftData target:** test plan explicitly notes
  "zero external-adoption signal" as a drawback. Per the
  user's preferred order (real-adopter signal first, synthetic
  later), this is a fallback, not a first pick.
- **`penny-bot` (DynamoDB):** real adopter, fork provisioned,
  but Penny's entity types naturally flow through `Soto`'s
  Codable structs — dedup keys come from business fields
  (e.g., `completedGame.hash`), not `Identifiable` synthesis.
  Wouldn't exercise `fromEntity:` cleanly.
- **`isowords` (raw SQL):** similar story — the in-place
  `insertSharedGame` bug maps to `IdempotencyKey(rawValue:
  completedGame.hash)`, not `fromEntity:`. Positive control
  for the `rawValue:` path but not for `fromEntity:`.

AmpFin is the only real-adopter candidate in the current
evidence set where **the natural source of an idempotency key
is a user-declared non-Optional `id: String` on a non-Fluent
`Identifiable` type** — the exact shape the deciding question
turns on.

## Expected session budget

- Fork + trial branch + first build: 10-20 min.
- Migration + four tests: 45-60 min (SwiftData `@Model`
  friction is the wild card).
- Measurement + findings + retrospective: 30-40 min.

Total: ~1.5-2 hours. If the SwiftData `@Model`
`Identifiable`-synthesis question takes longer than 30 min to
resolve (outcome unclear, multiple compile attempts required),
that itself is a P0 finding worth capturing in-depth —
document the friction rather than rush to a workaround.

## Result: pivoted before reaching the migration step

Trial attempted on 2026-04-23. **Baseline build failed before
the migration step** with compound pre-existing adopter-side
compatibility regressions on current toolchain
(`swift-driver 1.148.6 / Apple Swift 6.3.1 / arm64-apple-macosx26.0`).
Three classes of error surfaced during ~30 min of baseline
patching:

1. **Missing AppKit branch for `PlatformImage` typealias**
   (`AmpFinKit/Sources/AFNetwork/Extensions/Cover+Image.swift`).
   `#if canImport(UIKit)` gated the `UIImage` typealias; there
   was no `#elseif canImport(AppKit)` arm, so macOS CLI builds
   resolved `PlatformImage` to nothing. Patch: one-liner —
   add the AppKit branch. **Resolved.**
2. **Swift 6.3 `@Model` + `let`-property regression** on all
   V2 persistence types (`OfflineAlbumV2`, `OfflineTrackV2`,
   `OfflinePlaylistV2`). The `@Model` macro expansion now
   pre-initialises the `let` stored properties, which makes
   the user-supplied `init`'s `self.x = x` assignments
   re-initialisations — `"immutable value 'X' may only be
   initialized once"`. Fix shape: `let` → `var` across all
   non-mutable stored properties. **Partially resolved** on
   the V2 types. The `LegacyPersistenceManager` V1 shims
   needed the same treatment across 7 inner `@Model` types —
   bulk-rewrite started via a Python regex pass but produced
   incomplete coverage; the build continued to fail on the
   `public let name: String` declarations the simple pattern
   didn't match.
3. **`@Model` macro `Sendable`-availability regressions** —
   cascading diagnostics from the `@Model` expansion marking
   the type as unavailable-Sendable. Not investigated deeply
   once the pivot was decided.

Each rebuild surfaced a fresh class of Swift 6.3 toolchain-drift
regression. The cumulative friction was **not informative about
`SwiftIdempotency`'s API** — it was generic adopter-side
toolchain-debt indistinguishable from what any pre-Swift-6.3
SwiftData codebase would hit. Trial budget was consumed before
reaching the migration step.

**Pivot decision (2026-04-23):** abandoned the AmpFin attempt,
pivoted to a synthetic SwiftData target per the test plan's
option #3 ("Fresh synthetic target — build a small from-scratch
adopter"). The synthetic lives at
[`../examples/swiftdata-sample/`](../../examples/swiftdata-sample/)
and produced the API decision in ~30 min. See
[`../synthetic-swiftdata-package-trial/trial-findings.md`](../synthetic-swiftdata-package-trial/trial-findings.md)
for the answers to the deciding questions.

**Fork retention:** `Joseph-Cursio/AmpFin-idempotency-trial` is
retained. `package-integration-trial` branch has the baseline
fixes committed-but-unpushed; no upstream contribution intent
(per the test plan's "non-contribution fork" note). If a future
session wants to resurrect the AmpFin attempt, the two baseline
fixes are in-place and only item #2's legacy-file completion
would need finishing before the migration step can start.

**Policy note for future trials:** before forking a SwiftData-
backed adopter, spot-check the last-push date. AmpFin's last
commit is Nov 2025 — five months of toolchain drift. Any adopter
predating Swift 6.3's `@Model`-let regression (Q1 2026) will hit
this baseline friction. Preferred filter: `pushedAt > 2026-02-01`
narrows the candidate set to adopters who have rebuilt at least
once under the current `@Model` semantics.
