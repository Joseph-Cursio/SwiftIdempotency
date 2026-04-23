import Foundation
import FluentKit
import SwiftIdempotency
import SwiftIdempotencyFluent

/// Handler-style service that routes an externally-side-effecting
/// operation (here: a stub "notify downstream cache") through an
/// idempotency key derived from a Fluent Model's primary key.
///
/// This is the public-API shape that `SwiftIdempotencyFluent` is
/// designed to support: an adopter has a Fluent `Model`, already
/// saved (post-save, id populated), and needs to thread a stable
/// idempotency key into a downstream call that the linter has
/// flagged as requiring one via `@ExternallyIdempotent(by:)`.
///
/// Before `SwiftIdempotencyFluent`, this flow required a per-Model
/// adapter struct bridging `Acronym` to `Identifiable` with a
/// force-unwrapped UUID:
///
/// ```swift
/// struct IdentifiableAcronym: Identifiable {
///     let acronym: Acronym
///     var id: UUID { acronym.id! }
/// }
/// let key = IdempotencyKey(fromEntity: IdentifiableAcronym(acronym))
/// ```
///
/// With `SwiftIdempotencyFluent` in the dep graph, that's one line:
///
/// ```swift
/// let key = try IdempotencyKey(fromFluentModel: acronym)
/// ```
///
/// The boilerplate adapter struct is gone — the bare Fluent Model
/// reaches `IdempotencyKey` directly, and the throwing initializer
/// uses Fluent's own `requireID()` for the pre-save failure case.
public enum AcronymService {

    /// Notify a downstream cache of the acronym's update. Idempotent
    /// when routed through the `idempotencyKey` parameter — multiple
    /// calls with the same key produce the same observable effect at
    /// the cache layer.
    ///
    /// The handler doesn't actually hit a cache in this sample; the
    /// `recorder` closure stands in for the external side effect so
    /// tests can observe what was sent.
    @ExternallyIdempotent(by: "idempotencyKey")
    public static func notifyCache(
        acronym: Acronym,
        idempotencyKey: IdempotencyKey,
        recorder: (IdempotencyKey, String) -> Void
    ) {
        recorder(idempotencyKey, acronym.short)
    }

    /// Convenience wrapper that sources the idempotency key from the
    /// Fluent Model directly and forwards to `notifyCache`. Shows the
    /// typical call-site flow — adopters can use this pattern wherever
    /// they already have a post-save Model to hand.
    ///
    /// - Throws: `FluentError.idRequired` if `acronym.id` is nil (i.e.
    ///   pre-save). For pre-save create handlers, source the key from
    ///   a client-supplied header via
    ///   `IdempotencyKey(fromAuditedString:)` instead.
    public static func notifyCacheFromFluentModel(
        _ acronym: Acronym,
        recorder: (IdempotencyKey, String) -> Void
    ) throws {
        let key = try IdempotencyKey(fromFluentModel: acronym)
        notifyCache(
            acronym: acronym,
            idempotencyKey: key,
            recorder: recorder
        )
    }
}
