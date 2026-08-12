import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// The shape both `#assertIdempotent` expansions share: recognise the closure,
/// hand it to a runtime helper, and let the helper's `rethrows` signature carry
/// the call site's effects.
///
/// Two macro types exist because the *declarations* must be two — Swift picks
/// between `() throws -> Result` and `() async throws -> Result` by overload
/// resolution on the closure's effects, and an overload set needs two entries.
/// Only the helper's name differs between them, so only the name lives in the
/// conforming types. This mirrors ``EmptyPeerMacro`` in `IdempotentMacro.swift`,
/// which collapses the six marker macros the same way and for the same reason.
protocol RunTwiceExpressionMacro: ExpressionMacro {
    /// The `SwiftIdempotency` helper this expansion routes to.
    static var runtimeHelper: String { get }
}

extension RunTwiceExpressionMacro {
    public static func expansion(
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

/// Async overload of `AssertIdempotentMacro`. Shape and diagnostics are
/// identical; the only difference is the runtime helper — this one routes
/// to `__idempotencyAssertRunTwiceAsync`, which is `async rethrows` and
/// therefore requires `await` at the macro call site.
public struct AssertIdempotentAsyncMacro: RunTwiceExpressionMacro {
    static let runtimeHelper = "__idempotencyAssertRunTwiceAsync"
}

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
///
/// The expansion defers the double-invocation + compare + return-first
/// pattern to a runtime helper (`__idempotencyAssertRunTwice`) in
/// `SwiftIdempotency`. Keeps the macro expansion a single expression
/// that preserves the user's call-site effect specifiers (`try`,
/// `await`) without the macro needing to infer or emit a return-type
/// annotation — the helper's `rethrows` signature does the work.
public struct AssertIdempotentMacro: RunTwiceExpressionMacro {
    static let runtimeHelper = "__idempotencyAssertRunTwice"
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
