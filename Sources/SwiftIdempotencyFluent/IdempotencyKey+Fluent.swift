import FluentKit
import SwiftIdempotency

public extension IdempotencyKey {

    /// Construct a key from a Fluent `Model`'s primary key. Post-save
    /// Models — whose `id` is non-nil by the time the initializer runs —
    /// are the intended use. Pre-save (create-handler) Models have a
    /// nil `id`; the initializer throws in that case, matching Fluent's
    /// own `requireID()` idiom.
    ///
    /// ## Why this exists
    ///
    /// The generic `IdempotencyKey.init<E: Identifiable>(fromEntity:)`
    /// is unreachable for Fluent `Model` types: Fluent's Model protocol
    /// does not inherit `Identifiable`, and `Model`'s `id: IDValue?`
    /// Optional rejects the `E.ID: CustomStringConvertible` constraint
    /// even on the Model types that do get retroactively conformed.
    /// Rather than paper over both gaps with a per-Model adapter struct
    /// (the pattern documented in README §"Using with Fluent ORM" before
    /// v0.2.0), this initializer takes the Fluent Model directly and
    /// routes through the FluentKit-side primitives.
    ///
    /// ## Call-site shape
    ///
    /// ```swift
    /// import FluentKit
    /// import SwiftIdempotency
    /// import SwiftIdempotencyFluent
    ///
    /// final class Acronym: Model {
    ///     static let schema = "acronyms"
    ///     @ID(key: .id) var id: UUID?
    ///     @Field(key: "short") var short: String
    ///     init() {}
    /// }
    ///
    /// func updateAcronym(_ acronym: Acronym) async throws {
    ///     // post-save: acronym.id is non-nil
    ///     let key = try IdempotencyKey(fromFluentModel: acronym)
    ///     try await externalService.request(idempotencyKey: key)
    /// }
    /// ```
    ///
    /// ## Create-handler caveat
    ///
    /// This initializer does **not** solve the create-handler bootstrap
    /// problem — before the first save, `model.id` is nil and the
    /// initializer throws `FluentError.idRequired`. For create handlers
    /// the idiomatic path stays `init(fromAuditedString:)` over a
    /// client-supplied header (`Idempotency-Key` per Stripe convention)
    /// or a stable business key:
    ///
    /// ```swift
    /// let keyString = req.headers.first(name: "Idempotency-Key")
    ///     ?? acronym.short  // fallback on a stable business key
    /// let key = IdempotencyKey(fromAuditedString: keyString)
    /// // ... proceed to acronym.save(on: db)
    /// ```
    ///
    /// ## Composite IDs
    ///
    /// Models using `@CompositeID` have an `IDValue` that is a custom
    /// struct and typically does not conform to
    /// `CustomStringConvertible`. The initializer's generic constraint
    /// rejects those at compile time. For composite-keyed Models, route
    /// through `init(fromAuditedString:)` on a manually-composed string
    /// (e.g. `"\(key1)-\(key2)"`) — the composition is itself the audit
    /// moment.
    ///
    /// - Throws: `FluentError.idRequired` when `model.id` is `nil`
    ///   (pre-save state). This is the same error `model.requireID()`
    ///   throws, which this initializer delegates to directly.
    init<M: Model>(fromFluentModel model: M) throws
    where M.IDValue: CustomStringConvertible {
        let id = try model.requireID()
        self.init(fromAuditedString: String(describing: id))
    }
}
