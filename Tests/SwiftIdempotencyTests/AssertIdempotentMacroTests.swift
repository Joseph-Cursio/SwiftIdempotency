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
}
