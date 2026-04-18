import Testing
@testable import SwiftIdempotency

/// Phase-1 attribute-recognition tests. The macros currently generate no
/// peer declarations, so "does the attribute compile" is the entirety of
/// the test surface at this phase. Phase 3 will add expansion-verification
/// tests using `SwiftSyntaxMacrosTestSupport`.
@Suite
struct AttributeRecognitionTests {

    // MARK: - @Idempotent

    @Test
    func idempotent_onSyncFunction_compiles() {
        @Idempotent
        func upsertUser(id: Int) {}
        upsertUser(id: 1)  // Just ensure the decl site compiled.
    }

    @Test
    func idempotent_onAsyncThrowsFunction_compiles() async throws {
        @Idempotent
        func persist(_ value: String) async throws -> Int { value.count }
        let result = try await persist("hello")
        #expect(result == 5)
    }

    // MARK: - @NonIdempotent

    @Test
    func nonIdempotent_onVoidFunction_compiles() {
        @NonIdempotent
        func sendNotification(_ msg: String) {}
        sendNotification("hi")
    }

    // MARK: - @Observational

    @Test
    func observational_onLoggerLikeFunction_compiles() {
        @Observational
        func logEvent(_ message: String) {}
        logEvent("event")
    }

    // MARK: - @ExternallyIdempotent

    @Test
    func externallyIdempotent_withoutKeyName_compiles() {
        @ExternallyIdempotent
        func sendEmail(to recipient: String, subject: String) {}
        sendEmail(to: "a@b.com", subject: "hi")
    }

    @Test
    func externallyIdempotent_withKeyName_compiles() {
        @ExternallyIdempotent(by: "idempotencyKey")
        func chargeCard(amount: Int, idempotencyKey: String) {}
        chargeCard(amount: 100, idempotencyKey: "stable-id-42")
    }

    // MARK: - Expansion behaviour notes

    /// The `@Idempotent` macro DOES generate a `@Test` peer for zero-
    /// argument functions (Phase 3 scope). The peer generation details —
    /// exact expansion, test-name casing, async/throws propagation — are
    /// verified in `IdempotentPeerMacroTests` via `assertMacroExpansion`.
    ///
    /// The three non-`@Idempotent` attributes (`@NonIdempotent`,
    /// `@Observational`, `@ExternallyIdempotent`) remain marker-only —
    /// they exist as recognisable attribute names for the linter but
    /// generate no peers. Phase 3 explicitly ships peer generation only
    /// for `@Idempotent`.
    @Test
    func nonIdempotent_producesNoPeerMembers() {
        struct Host {
            @NonIdempotent
            func sendMessage() {}
        }
        let host = Host()
        host.sendMessage()  // Just verify the host compiles.
    }

    @Test
    func observational_producesNoPeerMembers() {
        struct Host {
            @Observational
            func logTrace() {}
        }
        let host = Host()
        host.logTrace()
    }

    @Test
    func externallyIdempotent_producesNoPeerMembers() {
        struct Host {
            @ExternallyIdempotent(by: "key")
            func chargeCard(amount: Int, key: String) {}
        }
        let host = Host()
        host.chargeCard(amount: 100, key: "k")
    }
}
