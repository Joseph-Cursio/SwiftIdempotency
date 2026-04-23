import Foundation
import Testing
import SwiftData
import SwiftIdempotency
@testable import SwiftDataSample

/// Exercises the `@ExternallyIdempotent(by: "idempotencyKey")` annotation
/// on `OfflineManager.download(album:idempotencyKey:in:)`. The handler
/// shape mirrors `AmpFin.OfflineManager.download(album:)`: fetch-or-insert
/// an SwiftData row under a stable key.
///
/// The checks are runtime, not macro-expansion (macro-expansion
/// coverage lives in `Tests/SwiftIdempotencyTests/` at the root). What
/// this suite verifies:
/// - The annotated handler compiles on a SwiftData-returning signature.
/// - Two invocations with the same `IdempotencyKey` return rows with
///   identical persistent identity (the dedup gate holds).
/// - The `#assertIdempotent` runtime check compiles and runs on a
///   throwing-sync closure over this handler, using the hellovapor-
///   documented tuple-wrapping workaround (non-Equatable `@Model`
///   reference return).
@Suite("OfflineManager.download(album:idempotencyKey:in:) runtime checks")
struct DownloadHandlerTests {

    @Test("Two calls with the same key return the same row (dedup gate holds)")
    @MainActor
    func dedupGateHolds() throws {
        let container = try OfflineManager.makeContainer()
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let key = IdempotencyKey(fromEntity: album)

        let first = try OfflineManager.download(
            album: album,
            idempotencyKey: key,
            in: container
        )
        let second = try OfflineManager.download(
            album: album,
            idempotencyKey: key,
            in: container
        )

        // SwiftData identity: persistentModelID is stable per row.
        // Two successful calls with the same key → same row.
        #expect(first.persistentModelID == second.persistentModelID)
        #expect(first.id == second.id)
        #expect(first.id == "album-42")
    }

    @Test("Row count stays at 1 after two invocations under the same key")
    @MainActor
    func rowCountInvariant() throws {
        let container = try OfflineManager.makeContainer()
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let key = IdempotencyKey(fromEntity: album)

        _ = try OfflineManager.download(album: album, idempotencyKey: key, in: container)
        _ = try OfflineManager.download(album: album, idempotencyKey: key, in: container)

        let context = ModelContext(container)
        let count = try context.fetchCount(FetchDescriptor<OfflineAlbum>())
        #expect(count == 1)
    }

    @Test("#assertIdempotent with dedicated Equatable-struct workaround (correct pattern)")
    @MainActor
    func assertIdempotentWithStructWorkaround() throws {
        let container = try OfflineManager.makeContainer()
        let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
        let key = IdempotencyKey(fromEntity: album)

        // `OfflineAlbum` is a non-Equatable `@Model final class`, so
        // `#assertIdempotent { ... returning OfflineAlbum }` would not
        // type-check (the macro's runtime helper requires `Equatable`
        // on the closure's return). The adopter-facing workaround is
        // to construct a small Equatable projection struct and return
        // it from the closure.
        let identity = try #assertIdempotent {
            let row = try OfflineManager.download(
                album: album,
                idempotencyKey: key,
                in: container
            )
            return AlbumProjection(id: row.id, name: row.name, favorite: row.favorite)
        }

        #expect(identity == AlbumProjection(id: "album-42", name: "Kind of Blue", favorite: true))
    }

    /// Small value-type projection used as the `#assertIdempotent`
    /// return — concrete `struct` with synthesized `Equatable`
    /// conformance, satisfying the macro's `Result: Equatable`
    /// constraint cleanly.
    ///
    /// Why not a tuple — the hellovapor trial's findings recommended
    /// `return (row.id, row.name, row.favorite)` on the grounds that
    /// "tuples of Equatable types are synthesised-Equatable." The
    /// synthetic-SwiftData trial discovered that claim is wrong:
    /// tuples have synthesized `==` but do NOT conform to the
    /// `Equatable` *protocol*. The macro's generic constraint
    /// `Result: Equatable` rejects them at compile time with
    ///
    ///     error: type '(String, String, Bool)' cannot conform to 'Equatable'
    ///     note: only concrete types such as structs, enums and classes
    ///           can conform to protocols
    ///
    /// See `docs/synthetic-swiftdata-package-trial/trial-findings.md`
    /// for the evidence chain and README update.
    struct AlbumProjection: Equatable {
        let id: String
        let name: String
        let favorite: Bool
    }
}

// MARK: - Tuple-return finding, preserved as an illustrative compile error
//
// The block below is the exact code the hellovapor-trial findings and
// the pre-fix README recommended. It does NOT compile. The synthetic
// trial produced the following diagnostic on tip `fff6f08`:
//
//     type '(String, String, Bool)' cannot conform to 'Equatable'
//     note: only concrete types such as structs, enums and classes can
//           conform to protocols
//     note: required by macro 'assertIdempotent' where
//           'Result' = '(String, String, Bool)'
//
// Keep this commented block to document the pattern that does not
// work, so a future reader reaching for the tuple shape sees the
// failure mode recorded next to the working struct-based fix.
//
//     @Test("#assertIdempotent with tuple return — DOES NOT COMPILE")
//     @MainActor
//     func tupleReturnFailsToCompile() throws {
//         let container = try OfflineManager.makeContainer()
//         let album = Album(id: "album-42", name: "Kind of Blue", favorite: true)
//         let key = IdempotencyKey(fromEntity: album)
//         let identity = try #assertIdempotent {
//             let row = try OfflineManager.download(
//                 album: album, idempotencyKey: key, in: container
//             )
//             return (row.id, row.name, row.favorite)
//         }
//         #expect(identity == ("album-42", "Kind of Blue", true))
//     }
