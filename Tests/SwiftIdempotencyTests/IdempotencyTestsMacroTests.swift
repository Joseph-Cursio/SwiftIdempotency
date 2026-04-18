import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros

/// Expansion-verification tests for `@IdempotencyTests` — the
/// extension-role macro that landed in the round-8 spike.
///
/// See `docs/phase5-round-8/trial-findings.md` for the empirical
/// reason the extension role was chosen over member and peer.
@Suite
struct IdempotencyTestsMacroTests {

    private let macros: [String: Macro.Type] = [
        "IdempotencyTests": IdempotencyTestsMacro.self,
        "Idempotent": IdempotentMacro.self
    ]

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
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
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
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
                        status()
                    }
                    #expect(__first == __second)
                }

                @Test
                func testIdempotencyOfPureMultiplier() async throws {
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
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
                    let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
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
}
