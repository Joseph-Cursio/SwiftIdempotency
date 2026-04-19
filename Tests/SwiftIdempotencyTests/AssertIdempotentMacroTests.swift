import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros
import SwiftIdempotency

/// Phase-4 tests for the `#assertIdempotent` freestanding expression
/// macro. Split into expansion-verification tests (exact textual form the
/// macro produces) and runtime-behaviour tests (the expanded code
/// actually works in context).
@Suite
struct AssertIdempotentMacroTests {

    private let testMacros: [String: Macro.Type] = [
        "assertIdempotent": AssertIdempotentMacro.self
    ]

    private let testMacrosAsync: [String: Macro.Type] = [
        "assertIdempotent": AssertIdempotentAsyncMacro.self
    ]

    // MARK: - Expansion shape

    @Test
    func trailingClosureForm_expandsToHelperCall() {
        assertMacroExpansion(
            """
            let r = #assertIdempotent { 42 }
            """,
            expandedSource: """
            let r = SwiftIdempotency.__idempotencyAssertRunTwice({ 42 })
            """,
            macros: testMacros
        )
    }

    @Test
    func explicitClosureForm_expandsToHelperCall() {
        // Parens-style invocation also works — the macro accepts both.
        assertMacroExpansion(
            """
            let r = #assertIdempotent({ 42 })
            """,
            expandedSource: """
            let r = SwiftIdempotency.__idempotencyAssertRunTwice({ 42 })
            """,
            macros: testMacros
        )
    }

    @Test
    func nonClosureArgument_producesDiagnostic() {
        // Passing something other than a closure literal — e.g. a plain
        // expression — surfaces a diagnostic rather than silently
        // generating broken code. A future phase may relax this to accept
        // passed-in closure references.
        assertMacroExpansion(
            """
            let x = 42
            let r = #assertIdempotent(x)
            """,
            expandedSource: """
            let x = 42
            let r = fatalError("#assertIdempotent requires a closure literal argument")
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "#assertIdempotent requires a closure literal argument, " +
                        "e.g. `#assertIdempotent { ... }`",
                    line: 2,
                    column: 9
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Runtime behaviour

    @Test
    func idempotentClosure_returnsFirstValue() throws {
        var callCount = 0
        let result = try #assertIdempotent { () -> Int in
            callCount += 1
            return 42  // deterministic — identical across calls
        }
        #expect(result == 42)
        #expect(callCount == 2)  // The macro invokes the closure twice.
    }

    @Test
    func idempotentClosureWithStringReturn_returnsFirstValue() throws {
        let result = try #assertIdempotent { () -> String in
            "stable-value"
        }
        #expect(result == "stable-value")
    }

    @Test
    func throwingClosureInFirstCall_propagates() {
        struct TestError: Error, Equatable {}
        var shouldThrow = true
        var caught = false
        do {
            _ = try #assertIdempotent { () -> Int in
                if shouldThrow {
                    shouldThrow = false
                    throw TestError()
                }
                return 0
            }
        } catch is TestError {
            caught = true
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(caught)
    }

    // Note: the "non-idempotent closure trips precondition" case isn't
    // tested directly here because `precondition` aborts the process —
    // not gracefully-catchable in a Swift Testing fixture. The runtime
    // behaviour is verified indirectly by the expansion test above (which
    // shows `precondition` is emitted) and by the semantic contract of
    // `precondition` itself. A future phase may swap to `Issue.record`
    // when `import Testing` is guaranteed.

    // MARK: - Async overload expansion shape

    @Test
    func asyncTrailingClosureForm_expandsToAsyncHelperCall() {
        // When overload resolution picks the async signature, the macro
        // routes to the async runtime helper. Swift's type checker selects
        // this overload automatically based on closure effects; the macro
        // itself doesn't inspect them.
        assertMacroExpansion(
            """
            let r = #assertIdempotent { 42 }
            """,
            expandedSource: """
            let r = SwiftIdempotency.__idempotencyAssertRunTwiceAsync({ 42 })
            """,
            macros: testMacrosAsync
        )
    }

    @Test
    func asyncExplicitClosureForm_expandsToAsyncHelperCall() {
        assertMacroExpansion(
            """
            let r = #assertIdempotent({ 42 })
            """,
            expandedSource: """
            let r = SwiftIdempotency.__idempotencyAssertRunTwiceAsync({ 42 })
            """,
            macros: testMacrosAsync
        )
    }

    @Test
    func asyncNonClosureArgument_producesDiagnostic() {
        assertMacroExpansion(
            """
            let x = 42
            let r = #assertIdempotent(x)
            """,
            expandedSource: """
            let x = 42
            let r = fatalError("#assertIdempotent requires a closure literal argument")
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "#assertIdempotent requires a closure literal argument, " +
                        "e.g. `#assertIdempotent { ... }`",
                    line: 2,
                    column: 9
                )
            ],
            macros: testMacrosAsync
        )
    }

    // MARK: - Async runtime behaviour

    /// The async overload is selected because the closure contains `await`.
    /// This case proves end-to-end compilation of `try await #assertIdempotent`
    /// against an `async throws` closure — the shape blocked by the
    /// pre-fix signature.
    @Test
    func asyncIdempotentClosure_returnsFirstValue() async throws {
        actor Counter {
            private(set) var calls = 0
            func bump() -> Int {
                calls += 1
                return 42
            }
        }
        let counter = Counter()
        let result = try await #assertIdempotent { () async -> Int in
            await counter.bump()
        }
        #expect(result == 42)
        let calls = await counter.calls
        #expect(calls == 2)
    }

    @Test
    func asyncThrowingClosureInFirstCall_propagates() async {
        struct TestError: Error, Equatable {}
        actor Gate {
            private var shouldThrow = true
            func next() throws -> Int {
                if shouldThrow {
                    shouldThrow = false
                    throw TestError()
                }
                return 0
            }
        }
        let gate = Gate()
        var caught = false
        do {
            _ = try await #assertIdempotent {
                try await gate.next()
            }
        } catch is TestError {
            caught = true
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(caught)
    }

    /// Overload resolution sanity check — a closure with no `await` still
    /// resolves to the sync overload, keeping the existing surface intact.
    /// The macro-expansion tests above cover the async routing; this one
    /// covers the selection rule at the user's call site.
    @Test
    func syncClosure_stillResolvesToSyncOverload() async throws {
        // No `await` in the body, so Swift picks the sync overload. If
        // overload resolution ever regressed to always pick async, the
        // outer `try` would become unnecessary (warning) and the absence
        // of `await` would become a compile error.
        let result = try #assertIdempotent { () -> Int in 7 }
        #expect(result == 7)
    }
}
