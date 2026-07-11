import SwiftIdempotency
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import Testing
@testable import SwiftIdempotencyMacros

/// `@ClockDeterministic` — the clock-determinism marker (the attribute
/// spelling of `/// @lint.determinism clock_deterministic`). Marker-only,
/// so the test surface is: the attribute compiles on the shapes it exists
/// for (async functions), and the expansion is empty and quiet.
struct ClockDeterministicAttributeTests {

    // MARK: - Attribute recognition (compiles on the canonical shapes)

    @Test
    func clockDeterministic_onAsyncClockInjectedFunction_compiles() async {
        let clock: any Clock<Duration> = ContinuousClock()

        @ClockDeterministic
        func coalesce(_ value: Int) async -> Int {
            try? await clock.sleep(for: .zero, tolerance: nil)
            return value * 2
        }
        let result = await coalesce(21)
        #expect(result == 42)
    }

    @Test
    func clockDeterministic_onAsyncThrowsFunction_compiles() async throws {
        @ClockDeterministic
        func fetchLabel(_ n: Int) async throws -> String {
            await Task.yield()
            return "#\(n)"
        }
        let label = try await fetchLabel(7)
        #expect(label == "#7")
    }

    // MARK: - Direct invocation (coverage attribution, mirrors
    // MarkerMacroDirectInvocationTests)

    @Test
    func clockDeterministic_expansion_returnsEmpty() throws {
        let file = Parser.parse(source: "@ClockDeterministic\nfunc refresh() async {}")
        let funcDecl = try #require(
            file.statements.first?.item.as(FunctionDeclSyntax.self),
            "test fixture failed to parse"
        )
        let attribute = try #require(
            funcDecl.attributes.first?.as(AttributeSyntax.self),
            "test fixture has no attribute"
        )
        let context = BasicMacroExpansionContext()
        let result = try ClockDeterministicMacro.expansion(
            of: attribute,
            providingPeersOf: funcDecl,
            in: context
        )
        #expect(result.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }
}
