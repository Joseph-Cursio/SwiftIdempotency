// Option B prototype — Penny package trial (2026-04-23).
//
// This file is prototype-shape: the API is minimal, unstable, and
// explicitly labeled v0.2.x experimental. It's shipped in
// `SwiftIdempotencyTestSupport` (previously a placeholder target) so
// the penny-bot package-integration trial can exercise it end-to-end.
// If the trial's findings are positive, this becomes the public
// Option B surface in a future release with potential API refinements.
// If negative, the module goes back to placeholder status.
//
// The Option C complement — return-equality checks via `#assertIdempotent`
// — remains the primary `SwiftIdempotency` API surface. Option B does
// not replace it; it addresses pathologies Option C is blind to
// (trivial returns like `HTTPStatus.ok`; invisible effects that don't
// change the return value).

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
    /// Count of observable side-effecting calls this recorder has
    /// witnessed since construction. Only mutations / writes / network
    /// sends; never reads.
    var effectCount: Int { get }
}

/// Runs `body` twice, asserting that the second invocation produces no
/// new side effects on any of the provided recorders — i.e. the handler
/// is idempotent under the observable-effect semantics Option B tests
/// for.
///
/// This complements `#assertIdempotent`'s Option C shape (return-value
/// equality). Use Option B when any of:
///
/// - The handler returns `HTTPStatus.ok` / `Void` / `Bool` / other
///   trivial types where two equal returns don't prove idempotency.
/// - The handler has side effects invisible to its return value
///   (sends an email, logs to metrics, publishes to a message queue).
/// - The handler returns a non-Equatable reference type and the struct-
///   projection workaround isn't practical.
///
/// ### Semantics
///
/// The helper:
///
/// 1. Snapshots each recorder's `effectCount` as a baseline.
/// 2. Runs `body` once. Captures post-first `effectCount`. (First-call
///    effect-deltas are diagnostic metadata; they aren't checked —
///    the first call may legitimately perform side effects.)
/// 3. Runs `body` a second time. Captures post-second `effectCount`.
/// 4. For each recorder, asserts `post-second - post-first == 0` —
///    the second invocation must be a no-op relative to the first.
///
/// If any recorder shows non-zero delta on the second invocation, the
/// helper fires a `precondition` with diagnostic text identifying
/// which recorder and the delta counts. This mirrors Option C's failure
/// mode (non-`Testing`-module `precondition`) so Option B is usable
/// outside a Swift Testing context.
///
/// ### Example
///
/// ```swift
/// @Test("handleAddUserRequest is idempotent when keyed on the request ID")
/// func addUserIsIdempotent() async throws {
///     let coinRepo = MockDynamoDBCoinRepo()
///     let userRepo = MockDynamoDBUserRepo()
///     let handler = UsersHandler(
///         context: .mock,
///         sharedContext: .mock(coinRepo: coinRepo, userRepo: userRepo)
///     )
///
///     let request = UserRequest.CoinEntryRequest(
///         fromDiscordID: "A", toDiscordID: "B", amount: 10,
///         source: .discord, reason: .userProvided
///     )
///
///     try await assertIdempotentEffects(
///         recorders: [coinRepo, userRepo]
///     ) {
///         _ = try await handler.handleAddUserRequest(entry: request)
///     }
/// }
/// ```
///
/// - Parameters:
///   - recorders: Array of mocks conforming to `IdempotentEffectRecorder`.
///     Empty array is allowed (useful for adopter code with no
///     instrumentable effects), in which case the helper just runs
///     `body` twice without asserting on any state — arguably more of
///     a smoke test than an idempotency check.
///   - file: Source file for failure diagnostics. Defaults to the
///     caller's source location via `#fileID`.
///   - line: Source line for failure diagnostics.
///   - body: The handler invocation under test. Should accept no
///     arguments; capture the inputs from the enclosing scope.
///
/// - Throws: Rethrows any error `body` throws. If the second
///   invocation throws but the first did not, that itself is a form
///   of non-idempotency; the helper does not intercept such throws
///   because the adopter's test framework should report them
///   directly.
public func assertIdempotentEffects(
    recorders: [any IdempotentEffectRecorder],
    file: StaticString = #fileID,
    line: UInt = #line,
    body: () async throws -> Void
) async rethrows {
    let baseline = recorders.map(\.effectCount)
    try await body()
    let afterFirst = recorders.map(\.effectCount)
    try await body()
    let afterSecond = recorders.map(\.effectCount)

    for i in recorders.indices {
        let firstDelta = afterFirst[i] - baseline[i]
        let secondDelta = afterSecond[i] - afterFirst[i]
        if secondDelta != 0 {
            preconditionFailure(
                """
                assertIdempotentEffects: handler is not idempotent.

                Recorder \(type(of: recorders[i])) \
                recorded \(secondDelta) new call\(secondDelta == 1 ? "" : "s") \
                on the second invocation \
                (first invocation recorded \(firstDelta); \
                expected 0 additional on retry).

                This is the Option B shape — side-effect observation.
                A handler that passes the Option C return-equality check
                (#assertIdempotent) can still fail this check when the
                non-idempotent effect is invisible to the return value
                (e.g., `HTTPStatus.ok` returned from a handler that sent
                two emails).
                """,
                file: file,
                line: line
            )
        }
    }
}
