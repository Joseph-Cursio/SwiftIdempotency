import Foundation
import SwiftData
import SwiftIdempotency

/// Mirrors the public-API shape of `AmpFin.OfflineManager.download(album:)`:
/// a dedup-guarded handler that either returns an existing SwiftData row or
/// inserts a new one, keyed on the album's stable `id`. The `@ExternallyIdempotent(by:)`
/// annotation declares the handler idempotent when routed through the
/// named `idempotencyKey` parameter — the linter's `missingIdempotencyKey`
/// rule verifies callers pass a stable value there (not `UUID()` /
/// `Date()` / similar).
///
/// Non-idempotency that this shape catches:
/// - A caller that forgets the dedup gate and inserts directly would
///   duplicate rows (blocked at the DB level here by `@Attribute(.unique)`
///   on `OfflineAlbum.id`, but that's defence-in-depth, not the gate).
/// - A retry without a stable `idempotencyKey` (passing a fresh `UUID()`
///   each time) would make the type-level contract a lie — the linter's
///   `missingIdempotencyKey` rule is the check.
///
/// Structured as an `enum` with static members to keep the sample focused
/// on the macro surface — a real adopter (AmpFin-shape) might instead
/// use an `@MainActor class OfflineManager` or an `actor`. The macro
/// expansion doesn't care about enclosing type shape.
public enum OfflineManager {

    /// In-memory SwiftData container — tests configure this fresh per
    /// test to avoid cross-test state bleed. The sample exposes a
    /// factory rather than a shared singleton so the test harness stays
    /// deterministic.
    public static func makeContainer() throws -> ModelContainer {
        let schema = Schema([OfflineAlbum.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Downloads an album for offline use (here: persists into SwiftData).
    /// The `@ExternallyIdempotent(by: "idempotencyKey")` annotation
    /// declares idempotency relative to the named key parameter. A
    /// stable `idempotencyKey` + the dedup gate together make
    /// retry-safe replay observable at the DB level: two invocations
    /// with the same key return the same `OfflineAlbum` row.
    ///
    /// Returning `OfflineAlbum` (a non-Equatable `@Model` reference
    /// type) intentionally reproduces the
    /// [hellovapor trial](../../docs/hellovapor-package-trial/trial-findings.md)
    /// finding that `#assertIdempotent` can't compare two references
    /// of a non-Equatable `@Model` directly — the test target wraps
    /// the result in a tuple of value fields for the assertion,
    /// documenting the workaround the README's "Using with Fluent ORM"
    /// section recommends for non-Equatable Models.
    @ExternallyIdempotent(by: "idempotencyKey")
    public static func download(
        album: Album,
        idempotencyKey: IdempotencyKey,
        in container: ModelContainer
    ) throws -> OfflineAlbum {
        let context = ModelContext(container)
        let albumId = album.id
        var descriptor = FetchDescriptor<OfflineAlbum>(
            predicate: #Predicate { $0.id == albumId }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            return existing
        }

        let offline = OfflineAlbum(
            id: album.id,
            name: album.name,
            favorite: album.favorite
        )
        context.insert(offline)
        try context.save()
        return offline
    }
}
