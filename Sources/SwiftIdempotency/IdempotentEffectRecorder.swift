#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A test-only recorder that observes side-effecting operations made by
/// a handler during a test run. The handler's test double (mock
/// `DynamoDB`, mock `HTTPClient`, mock mail sender, etc.) should conform
/// to this protocol and increment `effectCount` whenever it records a
/// mutation / write / network-send operation.
///
/// Reads should NOT be counted — the point of idempotency checking is
/// to detect *observable-state-changing* retries. A handler that reads
/// a row twice is idempotent; a handler that writes twice is not.
///
/// Class conformance is required (`AnyObject`) because effect-count
/// state must survive closure captures by reference; a struct conformance
/// would lose updates across closure boundaries.
///
/// The `Snapshot` associated type defaults to `Int` (backed by
/// `effectCount` via the default `snapshot()` implementation).
/// Adopters with richer mock state — a call log, an ordered list of
/// written rows, a multi-counter dictionary — can opt into a richer
/// snapshot type for more precise idempotency detection:
///
/// ```swift
/// final class DetailedMock: IdempotentEffectRecorder {
///     typealias Snapshot = [String]  // ordered call log
///     var effectCount: Int { callLog.count }
///     private(set) var callLog: [String] = []
///     func snapshot() -> [String] { callLog }
/// }
/// ```
///
/// Declared in `SwiftIdempotency` (not `SwiftIdempotencyTestSupport`)
/// so production mocks — observability shims, retry instrumentation —
/// can conform without forcing a `SwiftIdempotencyTestSupport`
/// dependency into production code. The `assertIdempotentEffects`
/// helper that consumes conformers lives in `SwiftIdempotencyTestSupport`.
///
/// ### Example
///
/// ```swift
/// final class MockDynamoDBCoinRepo: IdempotentEffectRecorder {
///     private(set) var effectCount = 0
///     var puts: [CoinEntry] = []
///
///     func putItem(_ entry: CoinEntry) async throws {
///         puts.append(entry)
///         effectCount += 1
///     }
/// }
/// ```
public protocol IdempotentEffectRecorder: AnyObject {
    /// The snapshot type compared across invocations to detect
    /// non-idempotent side effects. Defaults to `Int` (backed by
    /// `effectCount`). Adopters can override with any `Equatable` type
    /// for richer comparison (e.g. an ordered call log).
    associatedtype Snapshot: Equatable = Int

    /// Count of observable side-effecting calls this recorder has
    /// witnessed since construction. Only mutations / writes / network
    /// sends; never reads. Used in diagnostic messages and as the
    /// default `Snapshot` when `Snapshot == Int`.
    var effectCount: Int { get }

    /// Returns an `Equatable` snapshot of the recorder's current state.
    /// Called three times per `assertIdempotentEffects` invocation:
    /// pre-body baseline, post-first-invocation, post-second-invocation.
    /// The helper asserts the first and second snapshots are equal.
    ///
    /// When `Snapshot == Int` (the default), the default implementation
    /// returns `effectCount`. Adopters overriding `Snapshot` must provide
    /// their own `snapshot()` implementation.
    func snapshot() -> Snapshot
}

extension IdempotentEffectRecorder where Snapshot == Int {
    /// Default `snapshot()` implementation for the common case where
    /// `effectCount` is sufficient to detect non-idempotency. Adopters
    /// who don't declare a custom `Snapshot` typealias get this
    /// automatically.
    public func snapshot() -> Int { effectCount }
}

/// How `assertIdempotentEffects` reports a detected non-idempotency.
///
/// - `preconditionFailure`: the historical default. Calls
///   `Swift.preconditionFailure(_:file:line:)`, which aborts the
///   process. Matches `#assertIdempotent`'s Option C failure mode;
///   usable outside a Swift Testing context.
/// - `issueRecord`: reports via `Testing.Issue.record(_:sourceLocation:)`.
///   Fails the enclosing `@Test` without aborting the process, so
///   failure-path tests (intentionally non-idempotent bodies) can be
///   exercised via `withKnownIssue { }` or similar. Only meaningful
///   inside a Swift Testing run.
public enum IdempotencyFailureMode: Sendable {
    case preconditionFailure
    case issueRecord
}

// MARK: - Internal SPI (consumed by SwiftIdempotencyTestSupport)
//
// Leading underscores on the following declarations are the Swift
// convention for SPI-internal API. SwiftLint's `identifier_name` /
// `type_name` rules flag them, but the underscore is load-bearing —
// it signals "don't reach past @_spi(Internals)" to adopters who
// might otherwise import the SPI unaware. Suppressed inline.

// swiftlint:disable identifier_name type_name

/// Type-erased snapshot + comparer pair. Captured inside a generic
/// extension so the concrete `Snapshot` type is known statically, then
/// returned via `Any` so heterogeneous recorders (each with their own
/// `Snapshot` associatedtype) can coexist in a single
/// `[any IdempotentEffectRecorder]` array.
///
/// Not part of the public API. Exposed to `SwiftIdempotencyTestSupport`
/// via `@_spi(Internals)`.
@_spi(Internals)
public struct _IdempotencySnapshotBox {
    /// Describes the snapshot for diagnostic messages. Derived from
    /// `String(describing:)` at capture time so we don't need to keep
    /// the recorder alive for rendering.
    public let description: String

    /// Compares this snapshot against another box's erased value.
    /// Returns `false` if the type of the other box's value doesn't
    /// match the type captured at construction (defensive; shouldn't
    /// happen in practice because both boxes come from the same
    /// recorder).
    public let equals: (_IdempotencySnapshotBox) -> Bool

    fileprivate let _value: Any

    fileprivate init<T: Equatable>(_ value: T) {
        self._value = value
        self.description = String(describing: value)
        self.equals = { other in
            guard let otherValue = other._value as? T else { return false }
            return value == otherValue
        }
    }
}

@_spi(Internals)
extension IdempotentEffectRecorder {
    /// Captures the current snapshot into a type-erased box.
    /// Implementation is specialized per conforming type (so `Snapshot`
    /// is known), but the return type is erased for cross-recorder
    /// storage. Consumed by `assertIdempotentEffects`.
    public func _snapshotBox() -> _IdempotencySnapshotBox {
        _IdempotencySnapshotBox(snapshot())
    }
}

// swiftlint:enable identifier_name type_name
