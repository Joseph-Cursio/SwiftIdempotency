import Foundation
import Testing
import SwiftIdempotency
@testable import WebhookHandlerSample

@Suite("IdempotencyKey type safety on a webhook handler")
struct WebhookHandlerTests {

    @Test("Key derived from event.id is stable across retries of the same event")
    func derivesKeyFromEventId() {
        let event = PaymentIntent(
            id: "evt_abc123",
            amountMinorUnits: 2_000,
            currency: "USD"
        )

        let first = StripeWebhookHandler.makeChargeRequest(for: event)
        let second = StripeWebhookHandler.makeChargeRequest(for: event)

        // Same event → same derived key. This is the invariant the type
        // exists to protect. If the handler had used `UUID()` instead,
        // these two keys would differ and Stripe would charge twice.
        #expect(first.idempotencyKey == second.idempotencyKey)
        #expect(first.idempotencyKey.rawValue == "evt_abc123")
    }

    @Test("Audited-string escape hatch preserves the rawValue verbatim")
    func auditedStringEscapeHatch() {
        let key = IdempotencyKey(fromAuditedString: "upstream-request-id-7f3c")
        #expect(key.rawValue == "upstream-request-id-7f3c")
    }

    @Test("Codable round-trips as a bare string — no wrapper in the payload")
    func codableRoundTrip() throws {
        let original = IdempotencyKey(fromAuditedString: "stable-audit-id")

        let encoded = try JSONEncoder().encode(original)
        #expect(String(data: encoded, encoding: .utf8) == "\"stable-audit-id\"")

        let decoded = try JSONDecoder().decode(IdempotencyKey.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - Compile-time rejection examples (documented, not executed)
//
// The three patterns below are the entire reason `IdempotencyKey` exists
// as a strong type instead of `typealias IdempotencyKey = String`. Each
// one is kept as a comment so a reader can verify by removing the `//`
// prefix and seeing the compiler reject the pattern.
//
// 1. Raw UUID — no unlabeled `init(UUID)` path exists:
//
//    let key = IdempotencyKey(UUID())
//    // error: missing argument label 'fromEntity:' / 'fromAuditedString:'
//
// 2. String literal — `IdempotencyKey` deliberately does not conform to
//    `ExpressibleByStringLiteral`:
//
//    let key: IdempotencyKey = "evt_abc123"
//    // error: cannot convert value of type 'String' to 'IdempotencyKey'
//
// 3. Default construction — no `init()` path exists:
//
//    let key = IdempotencyKey()
//    // error: missing argument for parameter
//
// Each rejection forces the caller through `fromEntity` (preferred) or
// `fromAuditedString` (audit-labelled escape hatch). The labels are the
// reviewer's signal that retry-stability has been thought about at the
// call site.
