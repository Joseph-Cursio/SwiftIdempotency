@testable import SwiftIdempotencyMacros
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

/// `@IdempotencyTests` emits a test for every `@Idempotent` member it can *call* with no
/// arguments — not for every member that *declares* no parameters.
///
/// Those are different predicates, and the gap between them is every defaulted and variadic
/// parameter. `func status(verbose: Bool = false)` declares one parameter, and `status()`
/// compiles. Filtering on `parameters.isEmpty` dropped it — and then, with nothing left to emit,
/// the macro returned no extension at all. The author was left with a green build, `@Idempotent`
/// on the function, `@IdempotencyTests` on the suite, and not one idempotency check anywhere.
///
/// A silently absent test is the worst outcome a testing macro has available to it.
struct IdempotencyTestsArgumentlessTests {
    private let testMacros: [String: Macro.Type] = [
        "IdempotencyTests": IdempotencyTestsMacro.self
    ]

    @Test
    func defaultedParameter_stillGeneratesATest() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func currentSystemStatus(verbose: Bool = false) -> Int { 200 }
            }
            """,
            expandedSource: """
            struct Checks {
                @Idempotent
                func currentSystemStatus(verbose: Bool = false) -> Int { 200 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfCurrentSystemStatus() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        currentSystemStatus()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func variadicParameter_stillGeneratesATest() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func tally(_ counts: Int...) -> Int { counts.reduce(0, +) }
            }
            """,
            expandedSource: """
            struct Checks {
                @Idempotent
                func tally(_ counts: Int...) -> Int { counts.reduce(0, +) }
            }

            extension Checks {
                @Test
                func testIdempotencyOfTally() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        tally()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func aFunctionNeedingArguments_warnsInsteadOfVanishing() {
        // This one genuinely cannot be tested by the generated shape. Previously it was dropped
        // in silence; now the author is told, and pointed at the tools that can test it.
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func charge(amount: Int) -> Int { amount }
            }
            """,
            expandedSource: """
            struct Checks {
                @Idempotent
                func charge(amount: Int) -> Int { amount }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: IdempotencyTestsDiagnostic.functionNeedsArguments(name: "charge").message,
                    line: 4,
                    column: 10,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func aSuiteWithNoIdempotentFunctions_warns() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                func helper() -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Checks {
                func helper() -> Int { 0 }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: IdempotencyTestsDiagnostic.noIdempotentFunctions.message,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }
}
