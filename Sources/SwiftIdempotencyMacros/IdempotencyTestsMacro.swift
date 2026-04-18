import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// `@IdempotencyTests` — attached to a `@Suite` type; emits a `@Test`
/// method per `@Idempotent`-marked zero-argument member in an extension
/// of the type.
///
///     @Suite
///     @IdempotencyTests
///     struct IdempotencyChecks {
///         @Idempotent
///         func currentSystemStatus() -> Int { 200 }
///     }
///
/// Expands (as an extension decl) to:
///
///     extension IdempotencyChecks {
///         @Test
///         func testIdempotencyOfCurrentSystemStatus() async throws {
///             let (__first, __second) = try await SwiftIdempotency
///                 .__idempotencyInvokeTwice { currentSystemStatus() }
///             #expect(__first == __second)
///         }
///     }
///
/// ## Why an extension role, not peer or member
///
/// Round-7 validation (see `docs/phase5-round-7/trial-findings.md`
/// Finding 4) found Swift Testing's `@Test` macro expansion produces
/// `@used`/`@section` properties referencing `self` during property
/// initialisation when emitted by another macro at peer or member scope
/// inside a struct. The compiler rejects the nested expansion. Hand-
/// written `@Test`s work because they expand at a different point in
/// the type's layout.
///
/// Round 8 measured three candidates (`docs/phase5-round-8/trial-
/// findings.md`): Candidate A (`@attached(member)`) fails identically
/// to the original peer shape; Candidate B (`@attached(extension)`)
/// succeeds because the emitted `@Test`s live in a fresh extension
/// decl, outside the original struct's member layout and past the
/// point where the struct's own properties are initialised. Candidate
/// C (two-macro split) was rendered unnecessary by B's success.
public struct IdempotencyTestsMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let functionNames = declaration.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter(hasIdempotentAttribute)
            .filter { $0.signature.parameterClause.parameters.isEmpty }
            .map { $0.name.text }

        guard !functionNames.isEmpty else { return [] }

        let members = functionNames
            .map(generateTestMember)
            .map { "\($0)" }
            .joined(separator: "\n\n")

        let extensionSource: DeclSyntax = """
            extension \(type.trimmed) {
            \(raw: members)
            }
            """
        guard let ext = extensionSource.as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [ext]
    }

    /// Returns `true` if the function declaration has `@Idempotent` in
    /// its attribute list. Matches by trailing identifier segment.
    private static func hasIdempotentAttribute(_ function: FunctionDeclSyntax) -> Bool {
        function.attributes.contains { attribute in
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self)
            else {
                return false
            }
            return identifier.name.text == "Idempotent"
        }
    }

    private static func generateTestMember(for functionName: String) -> DeclSyntax {
        let testName = "testIdempotencyOf"
            + functionName.prefix(1).uppercased()
            + functionName.dropFirst()

        return """
            @Test
            func \(raw: testName)() async throws {
                let (__first, __second) = try await SwiftIdempotency.__idempotencyInvokeTwice {
                    \(raw: functionName)()
                }
                #expect(__first == __second)
            }
            """
    }
}
