import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expansion for `#assertIdempotent { body }`.
///
/// Expands to a double-invocation with an Option-C equivalence check,
/// returning the first result. The closure is preserved exactly as the
/// user wrote it — no arguments, no rewrites; the macro just arranges for
/// two calls and a comparison.
///
/// ## Expansion shape
///
/// ```swift
/// // User writes:
/// let result = try await #assertIdempotent { try await sendEmail(for: event) }
///
/// // Macro expands to (simplified):
/// let result: <ReturnType> = try await {
///     let _first = try await (body closure)()
///     let _second = try await (body closure)()
///     precondition(_first == _second, "..." )
///     return _first
/// }()
/// ```
///
/// The exact form preserves the `try` / `await` effect specifiers of the
/// closure by using a wrapped immediately-invoked closure; the compiler
/// sees the outer closure's effect spec at the call site and lifts it into
/// the surrounding expression.
public struct AssertIdempotentMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closureSource = try extractClosureSource(from: node, in: context) else {
            return "fatalError(\"#assertIdempotent requires a closure literal argument\")"
        }

        // The expansion defers the double-invocation + compare + return-first
        // pattern to a runtime helper (`__idempotencyAssertRunTwice`) in
        // `SwiftIdempotency`. Keeps the macro expansion a single expression
        // that preserves the user's call-site effect specifiers (`try`,
        // `await`) without the macro needing to infer or emit a return-type
        // annotation — the helper's `rethrows` signature does the work.
        let expansion: ExprSyntax = """
            SwiftIdempotency.__idempotencyAssertRunTwice(\(raw: closureSource))
            """
        return expansion
    }
}

/// Async overload of `AssertIdempotentMacro`. Shape and diagnostics are
/// identical; the only difference is the runtime helper — this one routes
/// to `__idempotencyAssertRunTwiceAsync`, which is `async rethrows` and
/// therefore requires `await` at the macro call site.
public struct AssertIdempotentAsyncMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        guard let closureSource = try extractClosureSource(from: node, in: context) else {
            return "fatalError(\"#assertIdempotent requires a closure literal argument\")"
        }

        let expansion: ExprSyntax = """
            SwiftIdempotency.__idempotencyAssertRunTwiceAsync(\(raw: closureSource))
            """
        return expansion
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

/// Diagnostic messages surfaced by `AssertIdempotentMacro`.
enum AssertIdempotentDiagnostic: String, DiagnosticMessage {
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
