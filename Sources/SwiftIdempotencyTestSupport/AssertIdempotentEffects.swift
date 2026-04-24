#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@_spi(Internals) import SwiftIdempotency
import Testing

/// Runs `body` twice, asserting that the second invocation produces a
/// snapshot identical to the first on every provided recorder — i.e.
/// the handler is idempotent under the observable-effect semantics
/// Option B tests for.
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
/// 1. Captures each recorder's baseline snapshot.
/// 2. Runs `body` once. Captures the post-first-invocation snapshot.
///    (First-call snapshots are diagnostic metadata; they aren't
///    compared — the first call may legitimately perform side effects.)
/// 3. Runs `body` a second time. Captures the post-second-invocation
///    snapshot.
/// 4. For each recorder, asserts the post-first and post-second
///    snapshots are equal — the second invocation must be a no-op
///    relative to the first.
///
/// When a recorder's snapshot changes across the second invocation,
/// the helper fires a failure through `failureMode`. With
/// `.preconditionFailure` (default), it calls
/// `Swift.preconditionFailure(_:file:line:)` — matching Option C's
/// failure mode; usable outside a Swift Testing context. With
/// `.issueRecord`, it reports via `Testing.Issue.record(_:sourceLocation:)`
/// — failing the enclosing `@Test` without aborting the process, so
/// failure-path tests can be exercised via `withKnownIssue { }`.
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
///   - failureMode: How detected non-idempotencies are reported.
///     Defaults to `.preconditionFailure`. Switch to `.issueRecord`
///     when exercising failure-path tests with Swift Testing's
///     `withKnownIssue { }`.
///   - file: Source file for failure diagnostics. Defaults to the
///     caller's source location via `#fileID`.
///   - filePath: Full file path, used for `Testing.SourceLocation`
///     when `failureMode == .issueRecord`. Defaults to `#filePath`.
///   - line: Source line for failure diagnostics.
///   - column: Source column, used for `Testing.SourceLocation`.
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
    failureMode: IdempotencyFailureMode = .preconditionFailure,
    file: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column,
    body: () async throws -> Void
) async rethrows {
    let baselines = recorders.map { $0._snapshotBox() }
    try await body()
    let afterFirsts = recorders.map { $0._snapshotBox() }
    try await body()
    let afterSeconds = recorders.map { $0._snapshotBox() }

    for index in recorders.indices
    where !afterFirsts[index].equals(afterSeconds[index]) {
        let message = diagnosticMessage(
            recorderType: type(of: recorders[index]),
            baseline: baselines[index].description,
            afterFirst: afterFirsts[index].description,
            afterSecond: afterSeconds[index].description
        )

        switch failureMode {
        case .preconditionFailure:
            preconditionFailure(message, file: file, line: line)
        case .issueRecord:
            Issue.record(
                Comment(rawValue: message),
                sourceLocation: SourceLocation(
                    fileID: String(describing: file),
                    filePath: String(describing: filePath),
                    line: Int(line),
                    column: Int(column)
                )
            )
        }
    }
}

/// Builds the failure diagnostic emitted by both `failureMode` branches
/// so the `for-where` loop body doesn't need a nested `if`.
private func diagnosticMessage(
    recorderType: Any.Type,
    baseline: String,
    afterFirst: String,
    afterSecond: String
) -> String {
    """
    assertIdempotentEffects: handler is not idempotent.

    Recorder \(recorderType) snapshot changed across the second \
    invocation.
        baseline (pre-body):        \(baseline)
        after first invocation:     \(afterFirst)
        after second invocation:    \(afterSecond)

    The second invocation must be a no-op relative to the first.
    This is the Option B shape — side-effect observation. A handler \
    that passes the Option C return-equality check (#assertIdempotent) \
    can still fail this check when the non-idempotent effect is \
    invisible to the return value (e.g., `HTTPStatus.ok` returned \
    from a handler that sent two emails).
    """
}
