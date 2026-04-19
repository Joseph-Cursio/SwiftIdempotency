/// `#assertIdempotent { body }` — runs the closure twice with the same
/// lexical bindings and asserts observable equivalence between the two
/// invocations (currently Option C: identical return values for
/// `Equatable` returns, no throw on the second invocation for `Void`).
///
/// ## Usage
///
/// ```swift
/// @Test func myTest() async throws {
///     let event = Event(id: "evt_1")
///     let result = try await #assertIdempotent {
///         try await sendEmail(for: event)
///     }
///     // `result` is the closure's first-invocation return value.
/// }
/// ```
///
/// Use this when:
///   - The function under test takes arguments the `@Idempotent` peer
///     macro can't synthesise on its own (most real-world cases).
///   - You want to verify idempotency at a specific call site rather
///     than the function-level `@Idempotent` annotation.
///   - The assertion should run inside an XCTest method or as part of a
///     larger Swift Testing scenario, rather than as a standalone test.
///
/// ## Sync and async overloads
///
/// Two `assertIdempotent` macro declarations coexist — one for
/// `() throws -> Result`, one for `() async throws -> Result`. Swift's
/// overload resolution picks the more specific sync signature when the
/// closure has no `await`, and the async signature when it does.
/// Adopters get the right behaviour without choosing explicitly; the
/// only visible difference is that async usage requires `try await`
/// at the macro call site.
///
/// ## Current scope
///
/// Option C semantics only — same as the `@Idempotent` peer-macro
/// expansion. Options A and B (dependency-injected observation sinks,
/// mock-based equivalence) remain deferred; callers wanting stronger
/// guarantees wrap the closure in their own harness.
@freestanding(expression)
public macro assertIdempotent<Result: Equatable>(
    _ body: () throws -> Result
) -> Result = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "AssertIdempotentMacro"
)

/// Async overload of `#assertIdempotent`. Picked by Swift overload
/// resolution when the closure contains an `await` effect. See the sync
/// declaration above for usage and scope details; semantics are identical.
@freestanding(expression)
public macro assertIdempotent<Result: Equatable>(
    _ body: () async throws -> Result
) -> Result = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "AssertIdempotentAsyncMacro"
)

// swiftlint:disable identifier_name

/// Runtime helper the `#assertIdempotent` macro expansion calls into.
/// Not intended for direct use — the underscore prefix marks it as a
/// macro-only implementation detail. Lives in the public library rather
/// than `SwiftIdempotencyTestSupport` so `#assertIdempotent` is usable
/// from any module that imports `SwiftIdempotency` without a second
/// library dependency.
///
/// The `rethrows` signature lets the helper pass through the closure's
/// throwing effect: non-throwing closures compile without `try`, throwing
/// closures require `try` at the macro-expansion call site. The Swift
/// compiler handles the effect inference at the macro's type boundary.
@inlinable
public func __idempotencyAssertRunTwice<Result: Equatable>(
    _ body: () throws -> Result,
    file: StaticString = #file,
    line: UInt = #line
) rethrows -> Result {
    let first = try body()
    let second = try body()
    precondition(
        first == second,
        "#assertIdempotent: closure returned different values on re-invocation — not idempotent",
        file: file,
        line: line
    )
    return first
}

/// Async runtime helper for the async overload of `#assertIdempotent`.
/// Identical semantics to `__idempotencyAssertRunTwice` but accepts an
/// `async throws` closure. The `async rethrows` signature lets the
/// closure's throwing effect pass through: a non-throwing async closure
/// compiles as `await #assertIdempotent { ... }` with no `try`; a
/// throwing async closure requires `try await`.
@inlinable
public func __idempotencyAssertRunTwiceAsync<Result: Equatable>(
    _ body: () async throws -> Result,
    file: StaticString = #file,
    line: UInt = #line
) async rethrows -> Result {
    let first = try await body()
    let second = try await body()
    precondition(
        first == second,
        "#assertIdempotent: closure returned different values on re-invocation — not idempotent",
        file: file,
        line: line
    )
    return first
}

/// Runtime helper the `@IdempotencyTests(for:)` member-macro expansion
/// (Candidate A) calls into. Takes a zero-argument closure, invokes it
/// twice, returns both results as a tuple. `async rethrows` lets sync,
/// async, throwing, and non-throwing closures all flow through — the
/// macro emits a `try await` call-site unconditionally and Swift's
/// implicit conversions absorb the effect polymorphism.
///
/// Not intended for direct use.
@inlinable
public func __idempotencyInvokeTwice<Result: Equatable>(
    _ body: () async throws -> Result
) async rethrows -> (Result, Result) {
    let first = try await body()
    let second = try await body()
    return (first, second)
}

// swiftlint:enable identifier_name
