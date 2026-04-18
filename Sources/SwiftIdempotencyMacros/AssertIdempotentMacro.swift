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
        // A freestanding expression macro's closure argument can arrive in
        // two positions:
        //   - `#assertIdempotent { body }` → trailing-closure form. The
        //     closure lives in `node.trailingClosure`.
        //   - `#assertIdempotent({ body })` → explicit-argument form. The
        //     closure lives in `node.arguments.first?.expression`.
        // Accept either.
        let closureArg: ClosureExprSyntax
        if let trailing = node.trailingClosure {
            closureArg = trailing
        } else if let explicit = node.arguments.first?.expression.as(ClosureExprSyntax.self) {
            closureArg = explicit
        } else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: AssertIdempotentDiagnostic.requiresClosureArgument
            ))
            return "fatalError(\"#assertIdempotent requires a closure literal argument\")"
        }

        let closureSource = closureArg.description

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
