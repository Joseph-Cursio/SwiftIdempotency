import SwiftSyntax
import SwiftParser
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosTestSupport
import SwiftDiagnostics
import Testing
@testable import SwiftIdempotencyMacros

/// Direct-invocation tests for the marker peer macros.
///
/// `IdempotentPeerMacroTests` and `ExternallyIdempotentMacroTests` use
/// `assertMacroExpansion` from `SwiftSyntaxMacrosTestSupport`, which
/// drives the macro through the framework's expansion machinery — but
/// LLVM coverage doesn't always attribute the expansion-method body
/// hits back to the impl module. The marker macros' bodies (`return []`)
/// were sitting at 0% line coverage in the package's coverage profile
/// despite being exercised by every expansion test.
///
/// Calling `Macro.expansion(of:providingPeersOf:in:)` directly produces
/// reliable coverage attribution. These tests also exercise the
/// fallback `return nil` path inside `extractByArgumentExpression`
/// (an attribute with arguments but no `by:` label — unreachable
/// through normal Swift syntax because `by:` is the only declared
/// argument label, but defensible-by-construction).
@Suite
struct MarkerMacroDirectInvocationTests {

    /// Synthesises a `func compute() {}` decl + a parsed attribute,
    /// returning both ready to feed to a `PeerMacro.expansion(...)`
    /// call.
    private func makeAttributedFunction(
        attribute attributeSource: String
    ) -> (AttributeSyntax, FunctionDeclSyntax) {
        let attributeFile = Parser.parse(source: "\(attributeSource)\nfunc compute() {}")
        // Locate the FunctionDeclSyntax — it's the first FunctionDecl in the file.
        // The attribute is also attached to it via Swift syntax's normal
        // parsing of `@Foo \n func compute()`.
        guard let funcDecl = attributeFile.statements.first?.item.as(FunctionDeclSyntax.self) else {
            preconditionFailure("test fixture failed to parse")
        }
        guard let attribute = funcDecl.attributes.first?.as(AttributeSyntax.self) else {
            preconditionFailure("test fixture has no attribute")
        }
        return (attribute, funcDecl)
    }

    @Test
    func idempotent_expansion_returnsEmpty() throws {
        let (attribute, funcDecl) = makeAttributedFunction(attribute: "@Idempotent")
        let context = BasicMacroExpansionContext()
        let result = try IdempotentMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func nonIdempotent_expansion_returnsEmpty() throws {
        let (attribute, funcDecl) = makeAttributedFunction(attribute: "@NonIdempotent")
        let context = BasicMacroExpansionContext()
        let result = try NonIdempotentMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func observational_expansion_returnsEmpty() throws {
        let (attribute, funcDecl) = makeAttributedFunction(attribute: "@Observational")
        let context = BasicMacroExpansionContext()
        let result = try ObservationalMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func externallyIdempotent_argumentListWithoutByLabel_isQuiet() throws {
        // Synthesises an attribute whose `arguments` is `.argumentList`
        // but where the argument has no `by:` label. The Swift compiler
        // would normally reject this — `by:` is the only valid label on
        // `@ExternallyIdempotent` — but the macro impl has a defensive
        // fallback `return nil` for the case. The fallback was sitting
        // at 0 hits in the coverage profile.
        let (attribute, funcDecl) = makeAttributedFunction(
            attribute: #"@ExternallyIdempotent(other: "x")"#
        )
        let context = BasicMacroExpansionContext()
        let result = try ExternallyIdempotentMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        // Quiet path — no `by:` argument means no validation runs.
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func externallyIdempotentDiagnostic_diagnosticIDIsAccessible() {
        // Reading `.diagnosticID` on a constructed `ExternallyIdempotentDiagnostic`
        // covers the `MessageID` getter — the path was 0-hit because
        // diagnostics are constructed and attached to nodes via
        // `context.diagnose(...)` but the `diagnosticID` getter is
        // exercised only when the test framework or compiler displays
        // the diagnostic. `MessageID`'s `domain` / `id` fields are
        // private, so the assertion compares against an expected value
        // constructed identically — the getter still runs.
        let diagnostic = ExternallyIdempotentDiagnostic.argumentMustBeStringLiteral
        let expected = MessageID(
            domain: "SwiftIdempotencyMacros",
            id: "externallyIdempotent.argumentMustBeStringLiteral"
        )
        #expect(diagnostic.diagnosticID == expected)
        #expect(diagnostic.severity == .error)
    }
}
