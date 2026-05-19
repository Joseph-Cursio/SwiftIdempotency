#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// swiftlint:disable type_name

/// Type-erased snapshot + comparer pair. Captured inside a generic
/// extension so the concrete `Snapshot` type is known statically, then
/// returned via `Any` so heterogeneous recorders (each with their own
/// `Snapshot` associatedtype) can coexist in a single
/// `[any IdempotentEffectRecorder]` array.
///
/// Not part of the public API. Exposed to `SwiftIdempotencyTestSupport`
/// via `@_spi(Internals)`. The leading underscore is the Swift SPI
/// convention; SwiftLint's `identifier_name` / `type_name` rules are
/// suppressed at file scope because the marker is load-bearing.
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
    public let equals: (Self) -> Bool

    private let _value: Any

    init<T: Equatable>(_ value: T) {
        self._value = value
        self.description = String(describing: value)
        self.equals = { other in
            guard let otherValue = other._value as? T else {
                return false
            }
            return value == otherValue
        }
    }
}

// swiftlint:enable type_name

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
    case issueRecord
    case preconditionFailure
}

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
/// ### `Sendable` under Swift 6 strict concurrency
///
/// This protocol does **not** require `Sendable`. The package itself
/// imposes only `AnyObject`. Adopters working in a Swift 6 strict-
/// concurrency target whose surrounding code requires the conformer
/// to be `Sendable` (e.g. the conformer also implements an injected
/// repository protocol that is `Sendable`, or is captured across an
/// actor boundary) will hit:
///
/// ```text
/// error: stored property 'X' of 'Sendable'-conforming class
///        'MockY' is mutable
/// ```
///
/// because mutable stored properties on a `Sendable` class are
/// rejected by strict concurrency, and `effectCount` (or the call
/// log backing a custom `Snapshot`) must be mutable for the recorder
/// to do its job. Two resolutions:
///
/// - **`@unchecked Sendable`** — declare the conformer
///   `final class MyMock: ..., @unchecked Sendable`. The adopter
///   takes responsibility for thread safety. Mocks used inside a
///   single test body (the common case) are single-threaded by
///   construction; this annotation matches the same posture Fluent
///   `Model` and similar reference-typed test fixtures already use.
/// - **Actor-based shape** — declare the conformer as an `actor`.
///   Heavier idiom, but appropriate when the recorder is shared
///   across concurrent calls and you need real isolation rather than
///   single-threaded discipline.
///
/// The `@unchecked Sendable` route is recommended for ordinary test
/// mocks. Reach for the actor shape only when the test exercises a
/// genuinely concurrent body.
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

public extension IdempotentEffectRecorder where Snapshot == Int {
    /// Default `snapshot()` implementation for the common case where
    /// `effectCount` is sufficient to detect non-idempotency. Adopters
    /// who don't declare a custom `Snapshot` typealias get this
    /// automatically.
    func snapshot() -> Int { effectCount }
}

// swiftlint:disable identifier_name

@_spi(Internals)
public extension IdempotentEffectRecorder {
    /// Captures the current snapshot into a type-erased box.
    /// Implementation is specialized per conforming type (so `Snapshot`
    /// is known), but the return type is erased for cross-recorder
    /// storage. Consumed by `assertIdempotentEffects`.
    func _snapshotBox() -> _IdempotencySnapshotBox {
        _IdempotencySnapshotBox(snapshot())
    }
}

// swiftlint:enable identifier_name
