import Foundation
import Testing
import FluentKit
import SwiftIdempotency
import SwiftIdempotencyFluent
@testable import FluentSample

/// Consumer-side exercise of `SwiftIdempotencyFluent` — verifies
/// the integration story documented in the sample's `AcronymService`
/// compiles and runs.
@Suite("AcronymService with SwiftIdempotencyFluent")
struct AcronymServiceTests {

    @Test("Post-save acronym → notify routes through deterministic key")
    func postSaveAcronym_producesDeterministicKey() throws {
        let savedID = UUID()
        let acronym = Acronym(id: savedID, short: "TEST", long: "Test acronym")

        var observed: (key: IdempotencyKey, short: String)?
        try AcronymService.notifyCacheFromFluentModel(acronym) { key, short in
            observed = (key, short)
        }

        let call = try #require(observed)
        #expect(call.key.rawValue == savedID.uuidString)
        #expect(call.short == "TEST")
    }

    @Test("Two calls on the same saved acronym produce the same key")
    func repeatedNotify_producesStableKey() throws {
        let savedID = UUID()
        let acronym = Acronym(id: savedID, short: "TEST", long: "Test")

        var keys: [IdempotencyKey] = []
        let recorder: (IdempotencyKey, String) -> Void = { key, _ in keys.append(key) }

        try AcronymService.notifyCacheFromFluentModel(acronym, recorder: recorder)
        try AcronymService.notifyCacheFromFluentModel(acronym, recorder: recorder)

        #expect(keys.count == 2)
        #expect(keys[0] == keys[1])
    }

    @Test("Pre-save acronym throws — sample documents the create-handler caveat")
    func preSaveAcronym_throws() {
        let unsaved = Acronym(short: "NEW", long: "New acronym")  // id nil
        #expect(throws: FluentError.self) {
            try AcronymService.notifyCacheFromFluentModel(unsaved) { _, _ in }
        }
    }

    @Test("Direct IdempotencyKey construction still works for adopter flexibility")
    func directKeyConstruction() throws {
        let acronym = Acronym(id: UUID(), short: "TEST", long: "Test")

        // Adopters can skip the wrapper and construct the key
        // directly if their handler signature needs the explicit
        // flow. Matches the hellovapor migration pattern.
        let key = try IdempotencyKey(fromFluentModel: acronym)

        var observed: (IdempotencyKey, String)?
        AcronymService.notifyCache(
            acronym: acronym,
            idempotencyKey: key,
            recorder: { k, s in observed = (k, s) }
        )
        #expect(observed?.0 == key)
    }
}
