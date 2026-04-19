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
///             let (__first, __second) = await SwiftIdempotency
///                 .__idempotencyInvokeTwice { currentSystemStatus() }
///             #expect(__first == __second)
///         }
///     }
///
/// The expansion adapts to the target function's effect specifiers —
/// `try` / `await` are emitted only when the target's signature requires
/// them, so non-throwing and non-async targets don't produce spurious
/// warnings ("no calls to throwing functions occur within 'try'
/// expression"). See the effect matrix in `generateTestMember`.
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
        let functions = declaration.memberBlock.members
            .compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .filter(hasIdempotentAttribute)
            .filter { $0.signature.parameterClause.parameters.isEmpty }

        guard !functions.isEmpty else { return [] }

        let members = functions
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

    /// Emits one `@Test` member per target function, inspecting the
    /// target's effect specifiers so the expansion doesn't carry
    /// unnecessary `try` / `await` tokens. Four cases:
    ///
    ///     target effects       inner call          outer helper call
    ///     ()                   fn()                await __helper { ... }
    ///     () throws            try fn()            try await __helper { ... }
    ///     () async             await fn()          await __helper { ... }
    ///     () async throws      try await fn()      try await __helper { ... }
    ///
    /// The outer `await` is always present because
    /// `__idempotencyInvokeTwice` is declared `async`. The outer `try`
    /// is present iff the closure body can throw (helper is `rethrows`).
    /// The test method stays `async throws` regardless — Swift doesn't
    /// warn on declared-but-unused `throws`, only on `try` over
    /// non-throwing expressions.
    private static func generateTestMember(for function: FunctionDeclSyntax) -> DeclSyntax {
        let functionName = function.name.text
        let testName = "testIdempotencyOf"
            + functionName.prefix(1).uppercased()
            + functionName.dropFirst()

        let effects = function.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrowing = effects?.throwsClause != nil

        let innerEffectPrefix: String
        switch (isAsync, isThrowing) {
        case (false, false): innerEffectPrefix = ""
        case (false, true):  innerEffectPrefix = "try "
        case (true, false):  innerEffectPrefix = "await "
        case (true, true):   innerEffectPrefix = "try await "
        }

        let outerEffectPrefix = isThrowing ? "try await " : "await "

        return """
            @Test
            func \(raw: testName)() async throws {
                let (__first, __second) = \(raw: outerEffectPrefix)SwiftIdempotency.__idempotencyInvokeTwice {
                    \(raw: innerEffectPrefix)\(raw: functionName)()
                }
                #expect(__first == __second)
            }
            """
    }
}
