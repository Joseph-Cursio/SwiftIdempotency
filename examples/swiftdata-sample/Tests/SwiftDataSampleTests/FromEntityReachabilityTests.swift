import Foundation
import Testing
import SwiftData
import SwiftIdempotency
@testable import SwiftDataSample

/// The deciding-question test set for the `swiftIdempotency` v0.1.0
/// pre-release API decision on `IdempotencyKey(fromEntity:)`.
///
/// The `IdempotencyKey.init<E: Identifiable>(fromEntity:) where
/// E.ID: CustomStringConvertible` initialiser surfaced **two P0
/// findings** in the [hellovapor trial](../../../docs/hellovapor-package-trial/trial-findings.md):
/// Fluent `Model`'s lack of `Identifiable` conformance, and the
/// `CustomStringConvertible` constraint rejecting Fluent's Optional
/// `UUID?` IDs. The open question was whether those constraints bite
/// outside Fluent — specifically on SwiftData `@Model` types and on
/// plain reference-type Identifiables with `id: String` — which this
/// suite answers.
///
/// A clean positive result on both cases confirms the "Optional-ID
/// pattern is Fluent-specific" hypothesis and tilts the v0.1.0 API
/// decision toward a **Fluent-shaped dedicated constructor** rather
/// than a global `CustomStringConvertible` constraint relaxation.
@Suite("IdempotencyKey(fromEntity:) reachability on non-Fluent Identifiable types")
struct FromEntityReachabilityTests {

    // MARK: - Reference-type `Identifiable` (non-SwiftData, non-ORM)

    @Test("Plain reference `Identifiable` with `let id: String` — baseline positive control")
    func referenceTypeIdentifiable_withStringID_succeeds() {
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let key = IdempotencyKey(fromEntity: album)
        #expect(key.rawValue == "album-42")
    }

    @Test("`IdempotencyKey(fromEntity:)` result is Hashable and stable across invocations")
    func referenceTypeIdentifiable_producesStableKey() {
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let key1 = IdempotencyKey(fromEntity: album)
        let key2 = IdempotencyKey(fromEntity: album)
        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)
    }

    // MARK: - SwiftData `@Model` Identifiable — the deciding case

    @Test("SwiftData `@Model` with user-declared `var id: String` — the deciding case")
    @MainActor
    func swiftDataModel_withStringID_succeeds() throws {
        let container = try OfflineManager.makeContainer()
        let context = ModelContext(container)
        let offline = OfflineAlbum(id: "album-42", name: "Kind of Blue", favorite: true)
        context.insert(offline)
        try context.save()

        // Deciding question: does `fromEntity:` reach this type?
        // If SwiftData's `@Model`-synthesized `PersistentModel: Identifiable`
        // uses `PersistentIdentifier` as the `id` type, this call would
        // fail at compile time (`PersistentIdentifier` is not
        // `CustomStringConvertible`). If the user's `var id: String`
        // shadows the synthesized identifier, the call compiles and
        // produces a key over the String.
        let key = IdempotencyKey(fromEntity: offline)
        #expect(key.rawValue == "album-42")
    }

    @Test("SwiftData `@Model` pre-insertion — fromEntity: works without touching the context")
    func swiftDataModel_preInsertion_succeeds() {
        // Construct the `@Model` without inserting into any context
        // (`PersistenceManager.shared` equivalent not yet present). The
        // user-declared `id: String` is set by `init`, so `fromEntity:`
        // should produce a key identical to the post-insertion key.
        let offline = OfflineAlbum(id: "album-42", name: "Kind of Blue", favorite: true)
        let key = IdempotencyKey(fromEntity: offline)
        #expect(key.rawValue == "album-42")
    }

    @Test("Cross-type consistency: Album and OfflineAlbum with equal `id` produce equal keys")
    @MainActor
    func crossTypeKeyConsistency() throws {
        let container = try OfflineManager.makeContainer()
        let context = ModelContext(container)
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let offline = OfflineAlbum(id: "album-42", name: "Kind of Blue", favorite: true)
        context.insert(offline)
        try context.save()

        let keyFromReference = IdempotencyKey(fromEntity: album)
        let keyFromModel = IdempotencyKey(fromEntity: offline)

        // `fromEntity:` hashes only the `Identifiable.id`, ignoring all
        // other fields and the runtime type of the entity. Two distinct
        // types with the same `id` → same key. This is the property
        // that makes `Album → OfflineAlbum` projection safe to key
        // cross-representation in a create handler.
        #expect(keyFromReference == keyFromModel)
        #expect(keyFromReference.rawValue == "album-42")
    }
}

// MARK: - Compile-time and documentation notes (not executed)
//
// 1. The `@Model`-macro + `let`-property regression in Swift 6.3: any
//    attempt to declare stored properties as `let` inside `@Model` with
//    a user-supplied `init` that assigns them will fail to compile
//    with "immutable value 'X' may only be initialized once". This is
//    a SwiftData / compiler constraint, not a `SwiftIdempotency`
//    constraint. The sample uses `var` throughout; any real adopter
//    migrating pre-Swift-6.3 code will have to do the same. First
//    documented in the AmpFin trial pivot (see
//    `../../docs/ampfin-package-trial/trial-scope.md`).
//
// 2. `@Attribute(.unique)` on `id` makes the DB itself the final
//    dedup guard. The macro surface expresses the *type-level*
//    contract ("this handler is idempotent when routed through
//    `idempotencyKey`"); `@Attribute(.unique)` is defence-in-depth
//    at the persistence layer. The linter's `missingIdempotencyKey`
//    rule is the *call-site* check that connects the two.
//
// 3. `Identifiable` synthesis behaviour on `@Model`: SwiftData's
//    `PersistentModel` protocol inherits from `Identifiable`, but
//    the type's `Identifiable.id` requirement is satisfied by the
//    user's `var id: String` in this sample — not by the
//    `persistentModelID: PersistentIdentifier` property. That
//    resolution is what makes `fromEntity:` reachable here; if
//    SwiftData ever changes so that `persistentModelID` wins the
//    synthesis (or deprecates the pattern of declaring a separate
//    `id`), this test fails and the finding would need revisiting.
