import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros

/// Expansion-verification tests for the `@Idempotent` peer macro.
///
/// Since the round-8 redesign, `@Idempotent` is marker-only — the peer
/// macro expands to zero declarations regardless of what it's attached
/// to. Test generation moved to `@IdempotencyTests` (extension macro on
/// the enclosing `@Suite` type). The assertion shape here is the same as
/// the other marker peer macros (`@NonIdempotent`, `@Observational`,
/// `@ExternallyIdempotent`).
///
/// The previously-shipped tests asserting peer-emitted `@Test func
/// testIdempotencyOf<Name>()` bodies were correct against the round-7
/// design but not the round-8 shape — they're gone. See
/// `IdempotencyTestsMacroTests` for the current test-generation
/// expansion surface.
@Suite
struct IdempotentPeerMacroTests {

    private let testMacros: [String: Macro.Type] = [
        "Idempotent": IdempotentMacro.self
    ]

    @Test
    func zeroArgFunction_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            func compute() -> Int { 42 }
            """,
            expandedSource: """
            func compute() -> Int { 42 }
            """,
            macros: testMacros
        )
    }

    @Test
    func asyncThrowsFunction_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            func fetchValue() async throws -> String { "" }
            """,
            expandedSource: """
            func fetchValue() async throws -> String { "" }
            """,
            macros: testMacros
        )
    }

    @Test
    func parameterisedFunction_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            func chargeCard(amount: Int, idempotencyKey: String) async throws {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, idempotencyKey: String) async throws {}
            """,
            macros: testMacros
        )
    }

    @Test
    func varDeclWithIdempotent_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            let constant = 42
            """,
            expandedSource: """
            let constant = 42
            """,
            macros: testMacros
        )
    }
}
