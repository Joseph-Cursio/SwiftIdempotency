@testable import SwiftIdempotencyMacros
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

/// `@ExternallyIdempotent(by:)` must name a key the *caller* supplies.
///
/// The macro used to check only that the label existed. But a parameter the caller may leave out
/// is a key the caller does not control, and "the caller repeats the key on a retry" is the
/// entire claim the annotation makes.
///
/// A default cannot rescue it, in either direction, and this is provable rather than a matter of
/// taste: **Swift forbids a default value from referring to another parameter**, so a defaulted
/// key can never be derived from the operation's own inputs. It can only be
///
/// - a constant — in which case every distinct operation shares one key, and the second is
///   deduplicated by the server as a replay of the first; or
/// - nondeterministic, like `UUID().uuidString` — in which case every retry mints a fresh key
///   and the operation runs twice.
///
/// Both destroy the guarantee. `= UUID().uuidString` is also the *natural* way to write an
/// idempotency-key parameter, which is what made this worth an error rather than a warning.
struct OmittableKeyParameterTests {
    private let testMacros: [String: Macro.Type] = [
        "ExternallyIdempotent": ExternallyIdempotentMacro.self
    ]

    // MARK: - The hole

    @Test
    func keyParameterWithNondeterministicDefault_isDiagnosed() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "idempotencyKey")
            func charge(amount: Int, idempotencyKey: String = UUID().uuidString) {}
            """,
            expandedSource: """
            func charge(amount: Int, idempotencyKey: String = UUID().uuidString) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: Self.omittableMessage(value: "idempotencyKey", cause: "has a default value"),
                    line: 2,
                    column: 25
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func keyParameterWithConstantDefault_isAlsoDiagnosed() {
        // A constant default is not the safe case. Every caller that omits the argument shares
        // one key, so two unrelated charges collide and the second is dropped as a replay.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "key")
            func charge(amount: Int, key: String = "fixed") {}
            """,
            expandedSource: """
            func charge(amount: Int, key: String = "fixed") {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: Self.omittableMessage(value: "key", cause: "has a default value"),
                    line: 2,
                    column: 25
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func variadicKeyParameter_isDiagnosed() {
        // A variadic may be passed nothing, so it is omittable by the same argument.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "keys")
            func charge(amount: Int, keys: String...) {}
            """,
            expandedSource: """
            func charge(amount: Int, keys: String...) {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: Self.omittableMessage(
                        value: "keys",
                        cause: "is variadic, and so may be passed nothing"
                    ),
                    line: 2,
                    column: 25
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Still quiet

    @Test
    func requiredKeyParameter_producesNoDiagnostic() {
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "idempotencyKey")
            func charge(amount: Int, idempotencyKey: String) {}
            """,
            expandedSource: """
            func charge(amount: Int, idempotencyKey: String) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func defaultOnANonKeyParameter_producesNoDiagnostic() {
        // Only the *key* has to be required. Everything else may default freely.
        assertMacroExpansion(
            """
            @ExternallyIdempotent(by: "idempotencyKey")
            func charge(amount: Int, currency: String = "USD", idempotencyKey: String) {}
            """,
            expandedSource: """
            func charge(amount: Int, currency: String = "USD", idempotencyKey: String) {}
            """,
            macros: testMacros
        )
    }

    /// The expected diagnostic text, kept in one place so the tests state the *rule* and not a
    /// transcription of the message.
    private static func omittableMessage(value: String, cause: String) -> String {
        ExternallyIdempotentDiagnostic.keyParameterIsOmittable(
            value: value,
            reason: cause.hasPrefix("is variadic") ? .isVariadic : .hasDefaultValue
        ).message
    }
}
