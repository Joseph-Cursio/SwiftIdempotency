import Foundation

/// A deduplication key for externally-idempotent operations (Stripe charges,
/// Mailgun deliveries, SNS publishes, and similar APIs that accept a
/// client-provided idempotency token).
///
/// ## Why a strong type
///
/// The central failure mode this type prevents is **using a per-invocation
/// generator** — `UUID()`, `Date()`, `arc4random()` — as an idempotency key.
/// A fresh UUID per call means each retry sees a new "identity," which
/// defeats the key's entire purpose: the external service treats each retry
/// as a distinct request, and the non-idempotent operation fires on every
/// replay.
///
/// By making `IdempotencyKey` a distinct type with deliberately limited
/// constructors, code like this becomes a *compile error*:
///
/// ```swift
/// let key: IdempotencyKey = UUID()            // ❌ type mismatch
/// stripe.charge(amount: 100, idempotencyKey: key)
/// ```
///
/// Instead, callers must go through one of the documented stable-source
/// constructors, making the derivation visible in code review:
///
/// ```swift
/// let key = IdempotencyKey(from: webhookEvent) // ✓ uses stable event id
/// stripe.charge(amount: 100, idempotencyKey: key)
/// ```
///
/// ## Fallback: the linter catches the remaining gap
///
/// A caller can still smuggle an unstable value in through
/// `IdempotencyKey(fromAuditedString: UUID().uuidString)`. The label
/// `fromAuditedString` is intentionally explicit so the bypass shows up
/// in code review, and `SwiftProjectLint`'s `missingIdempotencyKey` rule
/// catches the specific `UUID()` / `Date()` / `arc4random()` patterns at
/// call sites. The type handles the common case; the linter handles the
/// escape hatch.
///
/// ## Conformances
///
/// - `Hashable`: deduplicate keys in sets and dictionaries.
/// - `Sendable`: safe to pass across actor / isolation boundaries.
/// - `Codable`: round-trips through JSON, webhook payloads, persistence.
///   The serialised representation is the raw string; no wrapper.
public struct IdempotencyKey: Hashable, Sendable {

    /// The underlying string representation. Stable across retries by
    /// construction — callers choose from stability-preserving initialisers.
    public let rawValue: String

    /// Construct a key from an `Identifiable` entity whose `id` is stable
    /// across retries. Database primary keys, webhook event IDs, upstream
    /// request IDs, and similar durable identifiers all qualify.
    ///
    /// The entity's `id` must be `CustomStringConvertible` so this
    /// initialiser can produce a canonical string without the caller
    /// reaching for `String(describing:)` manually. Most real-world stable
    /// IDs (`UUID`, `Int`, `String`, typed wrappers around those) satisfy
    /// this out of the box.
    public init<E: Identifiable>(from entity: E) where E.ID: CustomStringConvertible {
        self.rawValue = String(describing: entity.id)
    }

    /// Construct a key from a string the caller has **audited** as stable
    /// across retries. The explicit label signals "I checked this; it's not
    /// a per-invocation value" — reviewers can flag cases where the audit
    /// is implausible (`UUID().uuidString`, `"\(Date())"`, etc.).
    ///
    /// Use only when no `Identifiable` entity is available. If you find
    /// yourself reaching for this constructor frequently, consider
    /// introducing a typed ID wrapper for the domain concept instead.
    public init(fromAuditedString source: String) {
        self.rawValue = source
    }

    // Deliberately NOT provided:
    //
    // - `init()` — cannot conjure a key from nothing.
    // - `init(_ uuid: UUID)` — UUID is per-invocation by default.
    // - `init(_ date: Date)` — same issue.
    // - `ExpressibleByStringLiteral` — would allow bare `"key-123"` which
    //   circumvents the audit signal.
    //
    // Adding any of these would undo the type's whole purpose. If a future
    // adopter has a genuine need for one of these paths, the answer is
    // almost always `fromAuditedString` with a justification comment at
    // the call site.
}

extension IdempotencyKey: CustomStringConvertible {
    public var description: String { rawValue }
}

extension IdempotencyKey: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
