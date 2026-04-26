import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Idempotent` — marker-only since the round-8 peer-macro redesign.
///
/// Primary value is existing as a recognisable attribute name that both
/// the linter (`SwiftProjectLint`'s `EffectAnnotationParser`) and
/// `@IdempotencyTests` (this package's member-scanning macro) can detect.
/// Emits no peer declarations of its own.
///
/// ## Why marker-only
///
/// The original Phase 3 design had `@Idempotent` peer-emit a
/// `@Test func testIdempotencyOf<Name>()`. Round-7 validation (see
/// `docs/phase5-round-7/trial-findings.md`, Finding 4) surfaced that
/// Swift Testing's `@Test` macro interacts poorly with any outer macro
/// that emits it at peer or member scope inside a struct — the nested
/// expansion produces `@used`/`@section` properties referencing `self`
/// during property initialisation, which the compiler rejects.
///
/// Round 8 (`docs/claude_phase_5_peer_macro_redesign_plan.md`) spiked
/// three candidate redesigns. Candidate B — an `@attached(extension)`
/// role on a separate `@IdempotencyTests` attribute attached to the
/// `@Suite` type — turned out to sidestep Finding 4 because the emitted
/// `@Test`s live in a fresh extension decl, outside the original
/// struct's member layout. That shape landed; `@Idempotent` reverted
/// to marker-only.
///
/// ## Usage
///
/// ```swift
/// @Suite
/// @IdempotencyTests
/// struct Checks {
///     @Idempotent
///     func currentSystemStatus() -> Int { 200 }
/// }
/// ```
///
/// `@IdempotencyTests` scans the struct's members, finds `@Idempotent`-
/// marked zero-argument functions, and emits a `@Test` per match inside
/// an extension of the struct.
public struct IdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker implementation — see `IdempotentMacro`.
public struct NonIdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker implementation — see `IdempotentMacro`.
public struct ObservationalMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker + argument validator. Emits no peer declarations (like the
/// three sibling marker macros), but *does* validate the `by:` argument
/// at expansion time — rejecting dotted paths, non-literal expressions,
/// and labels that don't name a parameter of the annotated function.
///
/// The validation closes finding #2 in the Hummingbird road-test:
/// previously the macro silently accepted any string value, so an
/// adopter writing `@ExternallyIdempotent(by: "payload.eventId")` got
/// zero enforcement at compile time *and* zero enforcement at lint time
/// (the linter's `MissingIdempotencyKey` visitor only understands
/// top-level parameter labels, not dotted paths). That combination
/// shipped false safety to adopters.
public struct ExternallyIdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let byExpression = extractByArgumentExpression(from: node) else {
            // No `by:` argument supplied. Documented quiet path — the
            // annotation still grants lattice trust at the linter, but
            // key-routing verification is skipped.
            return []
        }

        guard let byValue = stringLiteralValue(of: byExpression) else {
            context.diagnose(Diagnostic(
                node: Syntax(byExpression),
                message: ExternallyIdempotentDiagnostic.argumentMustBeStringLiteral
            ))
            return []
        }

        if byValue.isEmpty {
            // Explicit empty string — equivalent to omitting `by:`.
            return []
        }

        if byValue.contains(".") {
            context.diagnose(Diagnostic(
                node: Syntax(byExpression),
                message: ExternallyIdempotentDiagnostic.dottedPathNotSupported(value: byValue)
            ))
            return []
        }

        // Parameter-label check only applies when the macro is attached
        // to a function. If it's attached to something else, skip —
        // peer-macro placement on non-functions is a separate concern.
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            return []
        }

        let availableLabels = externalParameterLabels(of: funcDecl)
        if !availableLabels.contains(byValue) {
            context.diagnose(Diagnostic(
                node: Syntax(byExpression),
                message: ExternallyIdempotentDiagnostic.unknownParameterLabel(
                    value: byValue,
                    available: availableLabels
                )
            ))
        }

        return []
    }
}

// MARK: - Argument extraction helpers

/// Pulls the expression bound to the `by:` argument label out of an
/// `@ExternallyIdempotent(by: ...)` attribute. Returns `nil` when no
/// `by:` argument is present — the macro's documented default.
private func extractByArgumentExpression(
    from node: AttributeSyntax
) -> ExprSyntax? {
    guard case let .argumentList(arguments) = node.arguments else {
        return nil
    }
    for argument in arguments where argument.label?.text == "by" {
        return argument.expression
    }
    return nil
}

/// Extracts the underlying string value from a string-literal expression,
/// or returns `nil` if the expression isn't a literal or contains
/// interpolation. The macro requires literals because the visitor-side
/// `MissingIdempotencyKey` rule reads the value statically — a runtime
/// expression can't be cross-referenced to a parameter label.
private func stringLiteralValue(of expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self) else {
        return nil
    }
    var collected = ""
    for segment in literal.segments {
        guard let stringSegment = segment.as(StringSegmentSyntax.self) else {
            // Interpolation segment — the literal isn't statically
            // readable, so treat it the same as a non-literal.
            return nil
        }
        collected += stringSegment.content.text
    }
    return collected
}

/// Returns the external parameter labels of a function declaration, in
/// declaration order. Wildcards (`_ name: T`) contribute no label — a
/// parameter with no external label cannot be named by `by:`.
private func externalParameterLabels(of funcDecl: FunctionDeclSyntax) -> [String] {
    var labels: [String] = []
    for parameter in funcDecl.signature.parameterClause.parameters {
        if parameter.firstName.tokenKind == .wildcard {
            continue
        }
        labels.append(parameter.firstName.text)
    }
    return labels
}

// MARK: - Diagnostics

struct ExternallyIdempotentDiagnostic: DiagnosticMessage {
    let message: String
    let identifier: String

    var severity: DiagnosticSeverity { .error }
    var diagnosticID: MessageID {
        MessageID(domain: "SwiftIdempotencyMacros", id: identifier)
    }

    static let argumentMustBeStringLiteral = Self(
        message: "@ExternallyIdempotent(by:) requires a string literal — "
            + "runtime expressions can't be cross-referenced against the "
            + "annotated function's parameter labels.",
        identifier: "externallyIdempotent.argumentMustBeStringLiteral"
    )

    static func dottedPathNotSupported(value: String) -> Self {
        Self(
            message: "@ExternallyIdempotent(by: \"\(value)\") contains a dotted "
                + "key path, which is not supported. The `by:` argument must "
                + "name a top-level parameter label of the annotated function. "
                + "To route a key from a nested field, split the handler: "
                + "decode the payload in one function, then forward to a "
                + "downstream function whose parameter carries the key, and "
                + "attach @ExternallyIdempotent there.",
            identifier: "externallyIdempotent.dottedPathNotSupported"
        )
    }

    static func unknownParameterLabel(value: String, available: [String]) -> Self {
        let listing: String
        if available.isEmpty {
            listing = "the annotated function has no externally-labelled parameters"
        } else {
            let formatted = available.map { "\"\($0)\"" }.joined(separator: ", ")
            listing = "available parameter labels: \(formatted)"
        }
        return Self(
            message: "@ExternallyIdempotent(by: \"\(value)\"): no parameter "
                + "labelled \"\(value)\" on this function — \(listing).",
            identifier: "externallyIdempotent.unknownParameterLabel"
        )
    }
}

@main
struct SwiftIdempotencyMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        IdempotentMacro.self,
        NonIdempotentMacro.self,
        ObservationalMacro.self,
        ExternallyIdempotentMacro.self,
        AssertIdempotentMacro.self,
        AssertIdempotentAsyncMacro.self,
        IdempotencyTestsMacro.self
    ]
}
