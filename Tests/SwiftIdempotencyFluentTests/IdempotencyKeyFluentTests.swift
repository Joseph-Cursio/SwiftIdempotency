import Foundation
import Testing
import FluentKit
import SwiftIdempotency
@testable import SwiftIdempotencyFluent

@Suite("IdempotencyKey.init(fromFluentModel:) — Fluent integration")
struct IdempotencyKeyFluentTests {

    // MARK: - Post-save (id non-nil) — succeeds for each common IDValue

    @Test("UUID ID — produces key over String(describing:)")
    func uuidIDValue_postSave_producesStringifiedKey() throws {
        let acronym = Acronym()
        let assignedID = UUID()
        acronym.id = assignedID
        acronym.short = "TEST"
        acronym.long = "Test acronym"

        let key = try IdempotencyKey(fromFluentModel: acronym)

        // `String(describing: UUID())` produces the canonical
        // lowercased UUID string, which is what the init delegates to
        // via `fromAuditedString:`.
        #expect(key.rawValue == String(describing: assignedID))
        #expect(key.rawValue == assignedID.uuidString)
    }

    @Test("Int ID — produces key \"42\" for id=42")
    func intIDValue_postSave_producesDigits() throws {
        let entry = CounterEntry()
        entry.id = 42
        entry.label = "life"

        let key = try IdempotencyKey(fromFluentModel: entry)

        #expect(key.rawValue == "42")
    }

    @Test("String ID — produces key equal to the raw id string")
    func stringIDValue_postSave_producesRawString() throws {
        let session = SessionToken()
        session.id = "sess_abc123"
        session.user = "alice"

        let key = try IdempotencyKey(fromFluentModel: session)

        #expect(key.rawValue == "sess_abc123")
    }

    // MARK: - Pre-save (id nil) — throws FluentError.idRequired

    @Test("Pre-save Model with nil id throws FluentError.idRequired")
    func nilID_throwsFluentIDRequired() {
        let acronym = Acronym()
        // deliberately leave acronym.id unset (nil)
        acronym.short = "PRE"
        acronym.long = "pre-save"

        // `FluentError` doesn't conform to `Equatable`, so the
        // value-form `#expect(throws: FluentError.idRequired)` can't
        // compile. Match the type instead, then assert on the case
        // in the error-handler block.
        #expect(throws: FluentError.self) {
            try IdempotencyKey(fromFluentModel: acronym)
        }

        // Belt-and-suspenders: confirm it's specifically the
        // `.idRequired` case, not some other FluentError variant.
        do {
            _ = try IdempotencyKey(fromFluentModel: acronym)
            Issue.record("Expected throw; got success")
        } catch let error as FluentError {
            guard case .idRequired = error else {
                Issue.record("Expected FluentError.idRequired, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected FluentError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - Stability

    @Test("Two calls on the same Model produce equal keys (stability)")
    func stability_sameModelSameKey() throws {
        let acronym = Acronym()
        acronym.id = UUID()
        acronym.short = "TEST"
        acronym.long = "Test"

        let key1 = try IdempotencyKey(fromFluentModel: acronym)
        let key2 = try IdempotencyKey(fromFluentModel: acronym)

        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)
    }

    @Test("Two Models with equal IDs produce equal keys (cross-instance consistency)")
    func crossInstanceConsistency() throws {
        let sharedID = UUID()

        let a1 = Acronym()
        a1.id = sharedID
        a1.short = "TEST"
        a1.long = "one"

        let a2 = Acronym()
        a2.id = sharedID
        a2.short = "TEST-DIFFERENT-FIELD"  // intentional field drift
        a2.long = "two"

        let key1 = try IdempotencyKey(fromFluentModel: a1)
        let key2 = try IdempotencyKey(fromFluentModel: a2)

        // The init only hashes the id — the other fields don't
        // contribute. Two post-save Models with the same id produce
        // the same key regardless of field-level drift.
        #expect(key1 == key2)
    }
}

// MARK: - Fixture Fluent Models

/// Minimal UUID-id Fluent Model mirroring the shape of hellovapor's
/// `Acronym`. Used to verify the post-save / pre-save id paths.
final class Acronym: Model, @unchecked Sendable {
    static let schema = "acronyms"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "short")
    var short: String

    @Field(key: "long")
    var long: String

    init() {}
}

/// Int-id Model. Covers the `Int: CustomStringConvertible` case —
/// digits in, digits out.
final class CounterEntry: Model, @unchecked Sendable {
    static let schema = "counter_entries"

    @ID(custom: .id, generatedBy: .database)
    var id: Int?

    @Field(key: "label")
    var label: String

    init() {}
}

/// String-id Model. Covers the `String: CustomStringConvertible`
/// case — `String(describing: "x")` is `"x"` (no surrounding quotes).
final class SessionToken: Model, @unchecked Sendable {
    static let schema = "session_tokens"

    @ID(custom: .id, generatedBy: .user)
    var id: String?

    @Field(key: "user")
    var user: String

    init() {}
}

// MARK: - Compile-time and documentation notes (not executed)
//
// 1. Models whose `IDValue` does not conform to
//    `CustomStringConvertible` (e.g., custom struct composite IDs via
//    `@CompositeID`) are rejected at compile time with
//
//        error: initializer 'init(fromFluentModel:)' requires that
//               'CompositeIDModel.IDValue' conform to 'CustomStringConvertible'
//
//    This is deliberate: composite IDs should route through
//    `IdempotencyKey(fromAuditedString:)` on a manually-composed
//    string rather than a silent `String(describing:)` that would
//    produce something like `"CompositeID(key1: ..., key2: ...)"`.
//
// 2. Non-Fluent types can't be passed to this initializer; the
//    generic constraint `M: Model` forces a FluentKit `Model`
//    conformance. Callers with SwiftData `@Model` or plain
//    `Identifiable` types should use
//    `IdempotencyKey(fromEntity:)` from the main SwiftIdempotency
//    module instead.
//
// 3. `@unchecked Sendable` on the fixture Models is a test-time
//    convenience — Fluent Models are reference-type property-
//    wrapper aggregates that aren't Sendable by default. Swift 6
//    strict concurrency would warn without the opt-out, and
//    real adopters' Models typically are declared identically.
