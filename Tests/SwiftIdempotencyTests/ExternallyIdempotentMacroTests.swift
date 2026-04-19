import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros

/// Expansion-verification tests for the argument validation on
/// `@ExternallyIdempotent(by:)`.
///
/// The macro itself emits no peer declarations (like the other marker
/// attributes), but it *does* diagnose unreachable `by:` arguments at
/// compile time — dotted key paths, non-literal expressions, and labels
/// that don't name a parameter of the annotated function. These tests
/// lock in the diagnostic surface so regressions are caught before they
/// reach adopters.
///
/// Paired positive cases in `AttributeRecognitionTests` verify that
/// correct usages still compile cleanly.
@Suite
struct ExternallyIdempotentMacroTests {

    private let testMacros: [String: Macro.Type] = [
        "ExternallyIdempotent": ExternallyIdempotentMacro.self
    ]

    // MARK: - Quiet paths (no diagnostic)

    @Test
    func withoutByArgument_producesNoDiagnostic() {
        // No `by:` at all — documented quiet path. Linter still grants
        // lattice trust; call-site verification is simply not performed.
        assertMacroExpansion(
            """
            @ExternallyIdempotent
            func sendEmail(to recipient: String) {}
            """,
            expandedSource: """
            func sendEmail(to recipient: String) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func explicitEmptyBy_producesNoDiagnostic() {
        // `by: ""` is equivalent to omitting the argument — the default
        // value is the empty string and the macro treats it identically.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "")
            func sendEmail(to recipient: String) {}
            """,
            expandedSource: """
            func sendEmail(to recipient: String) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func matchingLabel_producesNoDiagnostic() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "key")
            func chargeCard(amount: Int, key: String) {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, key: String) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func matchingExternalLabelOnRelabelledParameter_producesNoDiagnostic() {
        // External label differs from the internal parameter name —
        // `by:` must name the external label, which is what call sites
        // actually write. This lock confirms the check reads the right
        // side of the parameter.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "key")
            func chargeCard(amount: Int, key idempotencyToken: String) {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, key idempotencyToken: String) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func attachedToNonFunction_skipsLabelCheck() {
        // Peer-macro placement on a non-function is unusual but shouldn't
        // crash — the label check is skipped and the dotted-path / literal
        // checks still apply. Here the `by:` value is well-formed, so no
        // diagnostic is expected.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "key")
            struct Dummy {}
            """,
            expandedSource: """
            struct Dummy {}
            """,
            macros: testMacros
        )
    }

    // MARK: - Diagnostic cases

    @Test
    func dottedPath_producesDiagnostic() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "payload.eventId")
            func handleWebhook(payload: WebhookPayload) {}
            """,
            expandedSource: """
            func handleWebhook(payload: WebhookPayload) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by: \"payload.eventId\") contains a dotted "
                        + "key path, which is not supported. The `by:` argument must "
                        + "name a top-level parameter label of the annotated function. "
                        + "To route a key from a nested field, split the handler: "
                        + "decode the payload in one function, then forward to a "
                        + "downstream function whose parameter carries the key, and "
                        + "attach @ExternallyIdempotent there.",
                    line: 1,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func unknownLabel_producesDiagnostic() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "wrongLabel")
            func chargeCard(amount: Int, key: String) {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, key: String) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by: \"wrongLabel\"): no parameter "
                        + "labelled \"wrongLabel\" on this function — "
                        + "available parameter labels: \"amount\", \"key\".",
                    line: 1,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func wildcardParameterCannotBeReferencedByLabel() {
        // `_ k: String` has no external label, so `by: "k"` can't reach
        // it — even though "k" is the internal name. Adopters hitting
        // this need to add an explicit label.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "k")
            func chargeCard(amount: Int, _ k: String) {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, _ k: String) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by: \"k\"): no parameter "
                        + "labelled \"k\" on this function — "
                        + "available parameter labels: \"amount\".",
                    line: 1,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func functionWithOnlyWildcardParameters_reportsEmptyLabelList() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "k")
            func opaque(_ a: Int, _ b: String) {}
            """,
            expandedSource: """
            func opaque(_ a: Int, _ b: String) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by: \"k\"): no parameter "
                        + "labelled \"k\" on this function — "
                        + "the annotated function has no externally-labelled parameters.",
                    line: 1,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func nonLiteralExpression_producesDiagnostic() {
        // A runtime expression for `by:` can't be cross-referenced
        // statically. Reject with a pointer to the underlying reason.
        assertMacroExpansion(
            """
            let label = "key"
            @ExternallyIdempotent(by: label)
            func chargeCard(amount: Int, key: String) {}
            """,
            expandedSource: """
            let label = "key"
            func chargeCard(amount: Int, key: String) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by:) requires a string literal — "
                        + "runtime expressions can't be cross-referenced against the "
                        + "annotated function's parameter labels.",
                    line: 2,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func interpolatedStringLiteral_producesDiagnostic() {
        assertMacroExpansion(
            #"""
            let prefix = "k"
            @ExternallyIdempotent(by: "\(prefix)ey")
            func chargeCard(amount: Int, key: String) {}
            """#,
            expandedSource: #"""
            let prefix = "k"
            func chargeCard(amount: Int, key: String) {}
            """#,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ExternallyIdempotent(by:) requires a string literal — "
                        + "runtime expressions can't be cross-referenced against the "
                        + "annotated function's parameter labels.",
                    line: 2,
                    column: 27
                )
            ],
            macros: testMacros
        )
    }
}
