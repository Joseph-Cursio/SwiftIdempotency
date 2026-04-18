import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftIdempotencyMacros

/// Expansion-verification tests for the `@Idempotent` peer macro. Uses
/// `assertMacroExpansion` to check the exact textual output rather than
/// observing compile-and-run behaviour — this way the tests stay
/// deterministic regardless of whether the host module has `import Testing`
/// wired up.
@Suite
struct IdempotentPeerMacroTests {

    private let testMacros: [String: Macro.Type] = [
        "Idempotent": IdempotentMacro.self
    ]

    // MARK: - Zero-argument function shapes — peer generated

    @Test
    func zeroArgVoid_generatesPeerTest_noTryNoAwait() {
        assertMacroExpansion(
            """
            @Idempotent
            func flush() {}
            """,
            expandedSource: """
            func flush() {}

            @Test
            func testIdempotencyOfFlush() {
                flush()
                flush()
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func zeroArgAsync_generatesAsyncPeer_awaitOnly() {
        assertMacroExpansion(
            """
            @Idempotent
            func sync() async {}
            """,
            expandedSource: """
            func sync() async {}

            @Test
            func testIdempotencyOfSync() async {
                await sync()
                await sync()
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func zeroArgThrows_generatesThrowingPeer_tryOnly() {
        assertMacroExpansion(
            """
            @Idempotent
            func validate() throws {}
            """,
            expandedSource: """
            func validate() throws {}

            @Test
            func testIdempotencyOfValidate() throws {
                try validate()
                try validate()
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func zeroArgAsyncThrows_generatesAsyncThrowingPeer_tryAwait() {
        assertMacroExpansion(
            """
            @Idempotent
            func upload() async throws {}
            """,
            expandedSource: """
            func upload() async throws {}

            @Test
            func testIdempotencyOfUpload() async throws {
                try await upload()
                try await upload()
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func zeroArgWithReturn_generatesEqualityAssertion() {
        assertMacroExpansion(
            """
            @Idempotent
            func compute() -> Int { 42 }
            """,
            expandedSource: """
            func compute() -> Int { 42 }

            @Test
            func testIdempotencyOfCompute() {
                let firstResult = compute()
                let secondResult = compute()
                #expect(firstResult == secondResult)
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func zeroArgAsyncThrowsReturn_generatesFullCeremony() {
        assertMacroExpansion(
            """
            @Idempotent
            func fetchValue() async throws -> String { "" }
            """,
            expandedSource: """
            func fetchValue() async throws -> String { "" }

            @Test
            func testIdempotencyOfFetchValue() async throws {
                let firstResult = try await fetchValue()
                let secondResult = try await fetchValue()
                #expect(firstResult == secondResult)
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Test-name casing

    @Test
    func lowercaseFunctionName_getsCapitalisedInTestName() {
        assertMacroExpansion(
            """
            @Idempotent
            func x() {}
            """,
            expandedSource: """
            func x() {}

            @Test
            func testIdempotencyOfX() {
                x()
                x()
            }
            """,
            macros: testMacros
        )
    }

    @Test
    func camelCaseFunctionName_preservesInternalCasing() {
        assertMacroExpansion(
            """
            @Idempotent
            func upsertRow() {}
            """,
            expandedSource: """
            func upsertRow() {}

            @Test
            func testIdempotencyOfUpsertRow() {
                upsertRow()
                upsertRow()
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Parameterised functions — no peer generated

    @Test
    func oneArgFunction_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            func upsert(id: Int) {}
            """,
            expandedSource: """
            func upsert(id: Int) {}
            """,
            macros: testMacros
        )
    }

    @Test
    func multiArgFunction_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            func chargeCard(amount: Int, idempotencyKey: String) async throws {}
            """,
            expandedSource: """
            func chargeCard(amount: Int, idempotencyKey: String) async throws {}
            """,
            macros: testMacros
        )
    }

    // MARK: - Non-function declarations — no peer generated

    @Test
    func varDeclWithIdempotent_producesNoPeer() {
        assertMacroExpansion(
            """
            @Idempotent
            let constant = 42
            """,
            expandedSource: """
            let constant = 42
            """,
            macros: testMacros
        )
    }
}
