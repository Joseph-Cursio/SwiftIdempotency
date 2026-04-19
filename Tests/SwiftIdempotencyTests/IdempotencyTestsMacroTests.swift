import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros

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
/// the extension role was chosen over member and peer.
@Suite
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
            macros: macros
        )
    }

    // MARK: - Effect-aware expansion (four combinations)

    /// Non-throwing, non-async target — the case that motivated the fix.
    /// Pre-fix the expansion unconditionally carried `try await`, which
    /// Swift flagged with "no calls to throwing functions occur within
    /// 'try' expression". Post-fix the outer call emits only `await`,
    /// the helper being async, and the inner body is bare — the whole
    /// expansion is warning-clean on adoption.
    @Test
    func syncNonThrowingTarget_emitsAwaitOnly() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func plain() -> Int { 1 }
            }
            """,
            expandedSource: """
            struct Checks {
                func plain() -> Int { 1 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfPlain() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        plain()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func throwingTarget_emitsTryAwaitOutsideAndTryInside() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func throwing() throws -> Int { 1 }
            }
            """,
            expandedSource: """
            struct Checks {
                func throwing() throws -> Int { 1 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfThrowing() async throws {
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
                        try throwing()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func asyncNonThrowingTarget_emitsAwaitOutsideAndInside() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func asynchronous() async -> Int { 1 }
            }
            """,
            expandedSource: """
            struct Checks {
                func asynchronous() async -> Int { 1 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfAsynchronous() async throws {
                    let (__first, __second) = await SwiftIdempotency.__idempotencyInvokeTwice {
                        await asynchronous()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }

    @Test
    func asyncThrowingTarget_emitsTryAwaitOutsideAndInside() {
        assertMacroExpansion(
            """
            @IdempotencyTests
            struct Checks {
                @Idempotent
                func asyncThrowing() async throws -> Int { 1 }
            }
            """,
            expandedSource: """
            struct Checks {
                func asyncThrowing() async throws -> Int { 1 }
            }

            extension Checks {
                @Test
                func testIdempotencyOfAsyncThrowing() async throws {
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
                        try await asyncThrowing()
                    }
                    #expect(__first == __second)
                }
            }
            """,
            macros: macros
        )
    }
}
