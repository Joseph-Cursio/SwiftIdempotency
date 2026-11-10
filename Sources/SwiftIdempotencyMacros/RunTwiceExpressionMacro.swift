import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Diagnostic messages surfaced by `AssertIdempotentMacro`.
private enum AssertIdempotentDiagnostic: String, DiagnosticMessage {
    case requiresClosureArgument

    var message: String {
        switch self {
        case .requiresClosureArgument:
            return "#assertIdempotent requires a closure literal argument, " +
                "e.g. `#assertIdempotent { ... }`"
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiftIdempotencyMacros", id: rawValue)
    }
}

/// The shape both `#assertIdempotent` expansions share: recognise the closure,
/// hand it to a runtime helper, and let the helper's `rethrows` signature carry
/// the call site's effects.
///
/// Two macro types exist because the *declarations* must be two — Swift picks
/// between `() throws -> Result` and `() async throws -> Result` by overload
/// resolution on the closure's effects, and an overload set needs two entries.
/// Only the helper's name differs between them, so only the name lives in the
/// conforming types. This mirrors ``EmptyPeerMacro`` in `EmptyPeerMacro.swift`,
/// which collapses the six marker macros the same way and for the same reason.
public protocol RunTwiceExpressionMacro: ExpressionMacro {
    /// The `SwiftIdempotency` helper this expansion routes to.
    static var runtimeHelper: String { get }
}

public extension RunTwiceExpressionMacro {
    /// Expands to a call that hands the closure to ``runtimeHelper``, or to a
    /// `fatalError` placeholder after diagnosing a missing closure.
    static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closureSource = try extractClosureSource(from: node, in: context) else {
            // `extractClosureSource` has already diagnosed. Emitting a `fatalError`
            // rather than an empty expression keeps the expansion type-checkable, so
            // the author sees the diagnostic they can act on instead of a cascade of
            // inference errors reported against the macro's expansion.
            return "fatalError(\"#assertIdempotent requires a closure literal argument\")"
        }
        return """
            SwiftIdempotency.\(raw: runtimeHelper)(\(raw: closureSource))
            """
    }
}

/// Extracts the closure argument that `#assertIdempotent` was invoked
/// with. A freestanding expression macro's closure argument can arrive
/// either as a trailing closure (`#assertIdempotent { body }`) or as an
/// explicit argument (`#assertIdempotent({ body })`); both forms route
/// to the same runtime helper so both need to be recognised here.
///
/// Returns `nil` after emitting a diagnostic when no closure is present.
private func extractClosureSource(
    from node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
) throws -> String? {
    if let trailing = node.trailingClosure {
        return trailing.description
    }
    if let explicit = node.arguments.first?.expression.as(ClosureExprSyntax.self) {
        return explicit.description
    }
    context.diagnose(Diagnostic(
        node: Syntax(node),
        message: AssertIdempotentDiagnostic.requiresClosureArgument
    ))
    return nil
}
