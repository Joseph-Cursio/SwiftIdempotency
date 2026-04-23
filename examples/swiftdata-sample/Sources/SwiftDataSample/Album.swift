import Foundation

/// Plain reference-type `Identifiable` with non-Optional `id: String`,
/// mirroring `AmpFin.AFFoundation.Item` / `Album` (`Codable, Identifiable`
/// base class with `let id: String`). No ORM in play — this is the
/// purest non-Fluent case for `IdempotencyKey(fromEntity:)`.
///
/// The two-type separation (`Album` as the in-memory domain type;
/// `OfflineAlbum` as the SwiftData-persisted projection) is deliberate
/// and mirrors the AmpFin layering. In the trial's migration scope,
/// `Album` is what the caller hands to `download(...)` and
/// `OfflineAlbum` is what SwiftData persists after the dedup gate.
/// Either type's `id` can in principle source an `IdempotencyKey`;
/// the trial tests both.
public final class Album: Codable, Identifiable {
    public let id: String
    public let name: String
    public let favorite: Bool

    public init(id: String, name: String, favorite: Bool) {
        self.id = id
        self.name = name
        self.favorite = favorite
    }
}
