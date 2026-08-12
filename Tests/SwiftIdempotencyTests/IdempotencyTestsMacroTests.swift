@testable import SwiftIdempotencyMacros
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

/// Expansion-verification tests for `@IdempotencyTests` — the
/// extension-role macro that landed in the round-8 spike.
///
/// Covers two axes:
///
/// 1. **Member selection** — which members get a generated `@Test`, which
///    don't (unmarked, parameterised).
/// 2. **Effect-aware expansion** — the emitted `try` / `await` tokens
///    match the target function's effect specifiers so the expansion
///    doesn't produce spurious "no calls to throwing functions occur
///    within 'try' expression" warnings on adoption.
///
/// See `docs/phase5-round-8/trial-findings.md` for the empirical reason
/// the extension role was chosen over member and peer. That round document
/// was pruned in `92d1363`; recover with
/// `git show 92d1363^:docs/phase5-round-8/trial-findings.md`.
struct IdempotencyTestsMacroTests {
    private let macros: [String: Macro.Type] = [
        "IdempotencyTests": IdempotencyTestsMacro.self,
        "Idempotent": IdempotentMacro.self
    ]

    // MARK: - Member selection

    @Test
    func singleIdempotentMember_emitsExtensionWithOneTest() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func status() -> Int { 200 }
            }
            """,
            expandedSource: """
            struct Checks {
                func status() -> Int { 200 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfStatus() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        status()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func multipleIdempotentMembers_emitsExtensionWithMultipleTests() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func status() -> Int { 200 }
                @Idempotent
                func pureMultiplier() -> Int { 6 }
            }
            """,
            expandedSource: """
            struct Checks {
                func status() -> Int { 200 }
                func pureMultiplier() -> Int { 6 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfStatus() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        status()
                    }
                    #expect(__first == __second)
                }

                @Test
                func testIdempotencyOfPureMultiplier() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        pureMultiplier()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func unmarkedMembers_notIncluded() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func tested() -> Int { 1 }
                func notTested() -> Int { 2 }
            }
            """,
            expandedSource: """
            struct Checks {
                func tested() -> Int { 1 }
                func notTested() -> Int { 2 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfTested() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        tested()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func idempotentWithArguments_skipped() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func withArg(_ x: Int) -> Int { x }
            }
            """,
            expandedSource: """
            struct Checks {
                func withArg(_ x: Int) -> Int { x }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: IdempotencyTestsDiagnostic.functionNeedsArguments(name: "withArg").message,
                    line: 4,
                    column: 10,
                    severity: .warning
                )
            ],
            macros: macros
        )
    }

    @Test
    func noIdempotentMembers_generatesNothing() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                func notMarked() -> Int { 1 }
            }
            """,
            expandedSource: """
            struct Checks {
                func notMarked() -> Int { 1 }
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
            macros: macros
        )
    }

    // MARK: - Effect-aware expansion (four combinations)

    /// The matrix exists because the expansion once carried `try await`
    /// unconditionally, which Swift flags on a non-throwing target with "no calls
    /// to throwing functions occur within 'try' expression". The sync/non-throwing
    /// row is the case that motivated the fix; the other three pin the tokens that
    /// were already right, so a future simplification cannot quietly take them out.
    ///
    /// The test method stays `async throws` in every row regardless — Swift does
    /// not warn on a declared-but-unused `throws`, only on `try` over a
    /// non-throwing expression.
    @Test("effect specifiers survive expansion", arguments: EffectMatrixCase.all)
    func effectSpecifiersSurviveExpansion(_ effect: EffectMatrixCase) {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                \(effect.target)
            }
            """,
            expandedSource: """
            struct Checks {
                \(effect.target)
            }

            extension Checks {
                @Test
                func \(effect.testName)() async throws {
                    let (__first, __second) = \(effect.outerPrefix)SwiftIdempotency.__idempotencyInvokeTwice {
                        \(effect.innerPrefix)\(effect.functionName)()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }
}

/// One row of the effect matrix: a target's effect specifiers, and the exact
/// `try` / `await` tokens the expansion must carry outside and inside.
///
/// **Both prefixes are written out, not derived.** `generateTestMember` computes
/// them from `(isAsync, isThrowing)`; a table that computed them the same way
/// would assert only that the macro agrees with itself, and would have passed
/// just as happily before the fix this matrix exists to pin. Spelling them as
/// literals is what makes the row an independent claim about the output.
struct EffectMatrixCase: Sendable, CustomTestStringConvertible {
    /// The annotated declaration, verbatim — it appears in both the input and,
    /// unchanged, in the expanded source, since `@Idempotent` is marker-only.
    let target: String
    let functionName: String
    let testName: String
    /// Before `__idempotencyInvokeTwice`. The helper is `async`, so `await` is
    /// always present; `try` is present iff the closure body can throw.
    let outerPrefix: String
    /// Before the call to the target.
    let innerPrefix: String

    var testDescription: String { "\(functionName): \(outerPrefix)/ \(innerPrefix)" }

    static let all: [EffectMatrixCase] = [
        EffectMatrixCase(
            target: "func plain() -> Int { 1 }",
            functionName: "plain",
            testName: "testIdempotencyOfPlain",
            outerPrefix: "await ",
            innerPrefix: ""
        ),
        EffectMatrixCase(
            target: "func throwing() throws -> Int { 1 }",
            functionName: "throwing",
            testName: "testIdempotencyOfThrowing",
            outerPrefix: "try await ",
            innerPrefix: "try "
        ),
        EffectMatrixCase(
            target: "func asynchronous() async -> Int { 1 }",
            functionName: "asynchronous",
            testName: "testIdempotencyOfAsynchronous",
            outerPrefix: "await ",
            innerPrefix: "await "
        ),
        EffectMatrixCase(
            target: "func asyncThrowing() async throws -> Int { 1 }",
            functionName: "asyncThrowing",
            testName: "testIdempotencyOfAsyncThrowing",
            outerPrefix: "try await ",
            innerPrefix: "try await "
        ),
    ]
}
