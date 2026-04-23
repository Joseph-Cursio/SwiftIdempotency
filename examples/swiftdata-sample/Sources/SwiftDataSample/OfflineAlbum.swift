import Foundation
import SwiftData

/// SwiftData-backed offline album, mirroring the shape of
/// `rasmuslos/AmpFin`'s `OfflineAlbumV2`:
/// - `@Model final class` with user-declared `id: String`
/// - `@Attribute(.unique)` on `id` for DB-level dedup
/// - Non-Optional `id` (contrasts with Fluent's `UUID?`)
///
/// This is the "non-Fluent Identifiable via SwiftData" case the
/// `swiftIdempotency` v0.1.0 pre-release API decision pivots on:
/// does `IdempotencyKey(fromEntity:)` reach this type cleanly, or
/// does SwiftData's `PersistentModel: Identifiable` synthesis put
/// the `id` constraint out of reach the way Fluent's Optional-UUID
/// `@ID` did?
///
/// Note: properties are declared `var` rather than `let`. The AmpFin
/// attempt showed that Swift 6.3's `@Model` macro + `let`-declared
/// stored properties produce the diagnostic "immutable value may
/// only be initialized once" on every `self.x = x` inside the
/// user-supplied `init`. Using `var` sidesteps the regression. This
/// constraint comes from SwiftData / the compiler, not from
/// `SwiftIdempotency`; it's recorded here because any real adopter
/// migrating a pre-Swift-6.3 `@Model` to current toolchain will
/// encounter it.
@Model
public final class OfflineAlbum {
    @Attribute(.unique)
    public var id: String
    public var name: String
    public var favorite: Bool

    public init(id: String, name: String, favorite: Bool) {
        self.id = id
        self.name = name
        self.favorite = favorite
    }
}
