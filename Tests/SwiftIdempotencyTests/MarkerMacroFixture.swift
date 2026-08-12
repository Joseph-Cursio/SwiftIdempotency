import SwiftParser
import SwiftSyntax
import Testing

/// Parses `attribute` applied to `declaration` and hands back both halves, ready
/// to feed a `PeerMacro.expansion(of:providingPeersOf:in:)` call.
///
/// Shared because three test types need it and two of them had grown their own
/// copy — `PureAttributeTests` and `ClockDeterministicAttributeTests` each
/// carried a twenty-line body byte-identical to the other apart from the macro
/// name and the sample function. Both said *"mirrors
/// MarkerMacroDirectInvocationTests"* in a comment, which was true and was the
/// problem: the mirroring was by hand.
///
/// The duplication was deliberate rather than careless, and the reason survives
/// here — see ``MarkerMacroDirectInvocationTests`` for why these markers are
/// invoked directly at all. LLVM does not reliably attribute a macro body's
/// coverage back to the impl module when the expansion runs through
/// `assertMacroExpansion`, so each marker's `return []` needs a direct call, in
/// a file the coverage report names. Consolidating the *tests* would have
/// undone that; only the fixture is shared.
///
/// `declaration` is a parameter rather than a fixed `func compute() {}` because
/// the sample carries meaning at a glance: `@Pure` sits on a synchronous
/// function because purity implies synchrony by contract, and
/// `@ClockDeterministic` sits on an `async` one because that is the shape it
/// exists for. A single shared body would flatten that into noise.
///
/// Threads `SourceLocation` so a fixture-parsing regression points at the
/// calling test rather than at this helper.
func makeAttributedFunction(
    attribute attributeSource: String,
    declaration: String = "func compute() {}",
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> (AttributeSyntax, FunctionDeclSyntax) {
    let file = Parser.parse(source: "\(attributeSource)\n\(declaration)")
    // The attribute is attached to the declaration by Swift's normal parsing of
    // `@Foo \n func bar()`, so locating the function locates both.
    let funcDecl = try #require(
        file.statements.first?.item.as(FunctionDeclSyntax.self),
        "test fixture failed to parse",
        sourceLocation: sourceLocation
    )
    let attribute = try #require(
        funcDecl.attributes.first?.as(AttributeSyntax.self),
        "test fixture has no attribute",
        sourceLocation: sourceLocation
    )
    return (attribute, funcDecl)
}
