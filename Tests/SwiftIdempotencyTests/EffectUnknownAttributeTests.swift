import SwiftIdempotency
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
@testable import SwiftIdempotencyMacros

/// `@EffectUnknown` — the `unknown` tier, given a spelling. Marker-only, so the
/// test surface is the same as `@ClockDeterministic`'s: it compiles on the
/// shapes it exists for, and its expansion is empty and quiet.
///
/// The tier it names has been in the reference lattice from the start and was
/// **inference-only** — a human had no way to write it. That left "I cannot
/// determine this" with no vocabulary, and the nearest writable marker,
/// `@NonIdempotent`, claims something strictly stronger: *unconditionally*
/// non-idempotent, re-invocation *does* add effects.
struct EffectUnknownAttributeTests {

    // MARK: - Compiles on the shapes it exists for

    @Test
    func effectUnknown_onFunctionCallingOpaqueDependency_compiles() {
        @EffectUnknown
        func settle(_ amount: Int) -> Int {
            // Stands in for the case the tier is named for: a call into code the
            // analysis cannot see and nobody annotated.
            OpaqueLedger.post(amount)
            return amount
        }
        #expect(settle(7) == 7)
    }

    @Test
    func effectUnknown_onThrowingFunction_compiles() throws {
        @EffectUnknown
        func settle(_ amount: Int) throws -> Int {
            guard amount >= 0 else { throw SettlementError.negative }
            return amount
        }
        #expect(try settle(3) == 3)
        #expect(throws: SettlementError.self) { try settle(-1) }
    }

    @Test
    func effectUnknown_onAsyncFunction_compiles() async {
        @EffectUnknown
        func settle(_ amount: Int) async -> Int { amount }
        let result = await settle(5)
        #expect(result == 5)
    }

    // MARK: - Marker-only: the expansion is empty and quiet

    @Test
    func effectUnknown_expansion_isEmptyAndQuiet() {
        let source = """
        @EffectUnknown
        func settle(_ amount: Int) -> Int { amount }
        """
        let file = Parser.parse(source: source)
        let context = BasicMacroExpansionContext(
            sourceFiles: [file: .init(moduleName: "Test", fullFilePath: "Test.swift")]
        )
        let expanded = file.expand(
            macros: ["EffectUnknown": EffectUnknownMacro.self],
            in: context
        )
        // Expansion strips the attribute and adds NOTHING — the declaration
        // comes through byte-identical apart from the marker itself. Asserting
        // equality with the original source would be wrong: attribute removal is
        // normal peer-macro behaviour, not a defect, and a test that expected it
        // to survive would be testing SwiftSyntax rather than this macro.
        #expect(expanded.description == "\nfunc settle(_ amount: Int) -> Int { amount }")
        // No peer declarations, and no diagnostic. The marker's whole job is to
        // be READ — by the linter and by a human — not to generate anything.
        #expect(context.diagnostics.isEmpty)
    }
}

// MARK: - Fixtures

private enum OpaqueLedger {
    static func post(_ amount: Int) { _ = amount }
}

private enum SettlementError: Error {
    case negative
}
