import SwiftIdempotency
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
@testable import SwiftIdempotencyMacros

/// `@Pure` — the lattice-bottom marker (attribute spelling of
/// `/// @lint.effect pure`). Marker-only, so the test surface is: the
/// attribute compiles on the shapes it exists for (synchronous functions —
/// pure implies synchronous by contract), and the expansion is empty and
/// quiet.
struct PureAttributeTests {

    // MARK: - Attribute recognition (compiles on the canonical shapes)

    @Test
    func pure_onSyncFunction_compiles() {
        @Pure
        func normalize(_ path: String) -> String {
            path.lowercased()
        }
        #expect(normalize("A/B") == "a/b")
    }

    @Test
    func pure_onGenericFunction_compiles() {
        @Pure
        func firstSorted<Element: Comparable>(_ values: [Element]) -> Element? {
            values.sorted().first
        }
        #expect(firstSorted([3, 1, 2]) == 1)
    }

    // MARK: - Direct invocation (coverage attribution, mirrors
    // MarkerMacroDirectInvocationTests)

    @Test
    func pure_expansion_returnsEmpty() throws {
        let file = Parser.parse(source: "@Pure\nfunc normalize(_ s: String) -> String { s }")
        let funcDecl = try #require(
            file.statements.first?.item.as(FunctionDeclSyntax.self),
            "test fixture failed to parse"
        )
        let attribute = try #require(
            funcDecl.attributes.first?.as(AttributeSyntax.self),
            "test fixture has no attribute"
        )
        let context = BasicMacroExpansionContext()
        let result = try PureMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }
}
