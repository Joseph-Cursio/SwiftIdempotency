import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Idempotent` peer-macro implementation.
///
/// For **zero-argument** functions, generates a companion Swift Testing
/// test that calls the function twice with identical (empty) arguments and
/// asserts Option-C observable equivalence:
///
///   - functions returning `Equatable`: `#expect(first == second)`
///   - functions returning `Void`: call twice; the test passes if neither
///     invocation throws (catches the common "second-call-errors" bug)
///
/// For all other function shapes (parameterised, non-function declarations),
/// emits no peer. Parameterised-function support is deferred to a
/// subsequent phase that introduces an `IdempotencyTestArgs` protocol.
///
/// ## Swift Testing dependency
///
/// The generated test uses `@Test` and `#expect` from `Testing`. The user's
/// module must import `Testing` where `@Idempotent` is used on a zero-
/// argument function. For modules that don't (production code, XCTest-only
/// targets), the generated test won't compile; in those cases, either:
///
///   - use `@Idempotent` only in modules where `import Testing` is
///     appropriate, OR
///   - keep the annotation for linter purposes but live without the
///     generated test, OR
///   - use the `#assertIdempotent` expression macro in a hand-written
///     XCTest test method.
///
/// A future phase may add conditional-compilation wrapping to ease this.
public struct IdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            return []
        }
        // Phase 3 ships zero-argument support only. Parameterised functions
        // need a way to provide test arguments the macro can't synthesise
        // from syntax alone.
        guard function.signature.parameterClause.parameters.isEmpty else {
            return []
        }

        let functionName = function.name.text
        // CamelCased peer name — matches `names: arbitrary` in the macro
        // declaration. Requires `@Idempotent` to be used at type-member
        // scope (inside a struct/class/actor/extension), since
        // arbitrary-named peers aren't allowed at global scope.
        let testName = "testIdempotencyOf"
            + functionName.prefix(1).uppercased()
            + functionName.dropFirst()

        let isAsync = function.signature.effectSpecifiers?.asyncSpecifier != nil
        let canThrow = function.signature.effectSpecifiers?.throwsClause != nil
        let returnsVoid = function.signature.returnClause == nil

        let asyncKeyword = isAsync ? "async " : ""
        let throwsKeyword = canThrow ? "throws " : ""
        let tryKeyword = canThrow ? "try " : ""
        let awaitKeyword = isAsync ? "await " : ""

        let bodyLines: String
        if returnsVoid {
            bodyLines = """
            \(tryKeyword)\(awaitKeyword)\(functionName)()
            \(tryKeyword)\(awaitKeyword)\(functionName)()
            """
        } else {
            bodyLines = """
            let firstResult = \(tryKeyword)\(awaitKeyword)\(functionName)()
            let secondResult = \(tryKeyword)\(awaitKeyword)\(functionName)()
            #expect(firstResult == secondResult)
            """
        }

        // The expansion emits a Swift Testing `@Test` function directly.
        // Two Swift-macro constraints ruled out the alternatives surfaced
        // during the round-7 validation trial:
        //
        //   1. Macros cannot emit `import` statements — the compiler
        //      rejects macro-introduced imports (`macro expansion cannot
        //      introduce import` error).
        //   2. Wrapping the peer in `#if canImport(Testing)` breaks the
        //      name-coverage check — declarations inside an
        //      `IfConfigDeclSyntax` don't satisfy `prefixed(testIdempotencyOf)`
        //      so the compiler rejects the expansion.
        //
        // Consequence: `@Idempotent` requires the enclosing file to have
        // `import Testing` at file scope. This constrains the annotation
        // to test-target usage — annotating a production-module function
        // that doesn't depend on Testing produces a `no macro named
        // 'expect'` compile error, which is a useful signal (the
        // annotation belongs in a test target, not production code).
        let testDecl: DeclSyntax = """
            @Test
            func \(raw: testName)() \(raw: asyncKeyword)\(raw: throwsKeyword){
                \(raw: bodyLines)
            }
            """
        return [testDecl]
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

/// Marker implementation — see `IdempotentMacro`. Parameter validation
/// (verifying the named key parameter exists on the annotated function) is
/// deferred to a future phase; Phase 1 accepts any string value and relies
/// on the linter's existing `missingIdempotencyKey` rule for verification.
public struct ExternallyIdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct SwiftIdempotencyMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        IdempotentMacro.self,
        NonIdempotentMacro.self,
        ObservationalMacro.self,
        ExternallyIdempotentMacro.self,
        AssertIdempotentMacro.self
    ]
}
