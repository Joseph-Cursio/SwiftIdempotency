import Foundation
import FluentKit

/// Sample Fluent `Model` mirroring the shape of hellovapor's Acronym:
/// UUID primary key, two String fields. Intentionally minimal — the
/// point is to demonstrate the `SwiftIdempotencyFluent` integration,
/// not to show Fluent itself.
///
/// The `@unchecked Sendable` is the standard Fluent escape hatch: Fluent
/// Models are reference types assembled from property wrappers that
/// aren't individually `Sendable`. Real adopters declare Models the
/// same way.
public final class Acronym: Model, @unchecked Sendable {
    public static let schema = "acronyms"

    @ID(key: .id)
    public var id: UUID?

    @Field(key: "short")
    public var short: String

    @Field(key: "long")
    public var long: String

    public init() {}

    public init(id: UUID? = nil, short: String, long: String) {
        self.id = id
        self.short = short
        self.long = long
    }
}
