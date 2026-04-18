import Testing
import Foundation
@testable import SwiftIdempotency

/// Phase-2 strong-type tests. Exercises `IdempotencyKey` construction paths,
/// conformances, and round-trip serialisation. Compile-time-enforcement
/// guarantees (e.g. "UUID() cannot be assigned to IdempotencyKey") are
/// inherent to the type's lack of a UUID constructor and are asserted via
/// the absence of such initialisers in the public API — if someone adds
/// one, the "Deliberately NOT provided" comment flags the review.
@Suite
struct IdempotencyKeyTypeTests {

    // MARK: - Construction from Identifiable entity

    @Test
    func fromIdentifiableEntity_uuidID_producesStableRawValue() {
        struct Event: Identifiable {
            let id: UUID
        }
        let fixedUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let event = Event(id: fixedUUID)
        let key = IdempotencyKey(from: event)
        #expect(key.rawValue == "11111111-2222-3333-4444-555555555555")
    }

    @Test
    func fromIdentifiableEntity_intID_producesStableRawValue() {
        struct Row: Identifiable {
            let id: Int
        }
        let key = IdempotencyKey(from: Row(id: 42))
        #expect(key.rawValue == "42")
    }

    @Test
    func fromIdentifiableEntity_stringID_producesStableRawValue() {
        struct Message: Identifiable {
            let id: String
        }
        let key = IdempotencyKey(from: Message(id: "evt_abc123"))
        #expect(key.rawValue == "evt_abc123")
    }

    // MARK: - Construction from audited string

    @Test
    func fromAuditedString_preservesValueExactly() {
        let key = IdempotencyKey(fromAuditedString: "stripe-charge-2026-04-18-run-7")
        #expect(key.rawValue == "stripe-charge-2026-04-18-run-7")
    }

    @Test
    func fromAuditedString_emptyString_allowedButDiscouraged() {
        // The type doesn't gate empty strings — that's a semantic check for
        // the caller. Documented here so the behaviour is intentional, not
        // an oversight.
        let key = IdempotencyKey(fromAuditedString: "")
        #expect(key.rawValue == "")
    }

    // MARK: - Hashable / equatable

    @Test
    func sameRawValue_hashesAndEquatesEqually() {
        let first = IdempotencyKey(fromAuditedString: "k1")
        let second = IdempotencyKey(fromAuditedString: "k1")
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
    }

    @Test
    func differentRawValue_notEqual() {
        let first = IdempotencyKey(fromAuditedString: "k1")
        let second = IdempotencyKey(fromAuditedString: "k2")
        #expect(first != second)
    }

    @Test
    func usableInSet() {
        let keys: Set<IdempotencyKey> = [
            IdempotencyKey(fromAuditedString: "k1"),
            IdempotencyKey(fromAuditedString: "k1"),
            IdempotencyKey(fromAuditedString: "k2")
        ]
        #expect(keys.count == 2)
    }

    // MARK: - Codable round-trip

    @Test
    func codable_jsonRoundTrip_preservesRawValue() throws {
        let original = IdempotencyKey(fromAuditedString: "webhook-evt-2026-04-18")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IdempotencyKey.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func codable_encodesAsBareString_noWrapper() throws {
        // The wire format should be a bare string so webhook payloads and
        // third-party APIs (Stripe, Mailgun) that expect a plain string
        // idempotency key don't need a wrapper.
        let key = IdempotencyKey(fromAuditedString: "evt_abc")
        let data = try JSONEncoder().encode(key)
        let jsonString = try #require(String(data: data, encoding: .utf8))
        #expect(jsonString == "\"evt_abc\"")
    }

    @Test
    func codable_decodesFromBareString() throws {
        let json = Data(#"  "evt_xyz"  "#.utf8)
        let key = try JSONDecoder().decode(IdempotencyKey.self, from: json)
        #expect(key.rawValue == "evt_xyz")
    }

    // MARK: - CustomStringConvertible

    @Test
    func description_returnsRawValue() {
        let key = IdempotencyKey(fromAuditedString: "k-9")
        #expect(key.description == "k-9")
        #expect("\(key)" == "k-9")
    }

    // MARK: - Typed-ID wrapper case (common adopter pattern)

    @Test
    func fromIdentifiableWithTypedIDWrapper_works() {
        struct CustomerID: Hashable, CustomStringConvertible {
            let value: String
            var description: String { value }
        }
        struct Customer: Identifiable {
            let id: CustomerID
        }
        let customer = Customer(id: CustomerID(value: "cust_42"))
        let key = IdempotencyKey(from: customer)
        #expect(key.rawValue == "cust_42")
    }
}
