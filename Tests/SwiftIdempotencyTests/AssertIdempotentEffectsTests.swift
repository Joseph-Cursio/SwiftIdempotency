import Testing
import SwiftIdempotency
import SwiftIdempotencyTestSupport

/// Unit tests for the Option B prototype (`assertIdempotentEffects`)
/// in `SwiftIdempotencyTestSupport`. The API is labeled experimental
/// pending the penny-bot package-integration-trial's feedback.
///
/// Failure-path tests (a non-idempotent body firing a precondition)
/// aren't exercised here because `preconditionFailure` terminates the
/// test process. The precondition's correctness is relied upon by
/// construction — the body is ~5 lines and deltas compare directly.
@Suite("assertIdempotentEffects — Option B prototype")
struct AssertIdempotentEffectsTests {

    /// Counting-only recorder — conforms to the minimal `IdempotentEffectRecorder`
    /// protocol. Used throughout the test suite as a generic mock.
    final class CountingRecorder: IdempotentEffectRecorder, @unchecked Sendable {
        private(set) var effectCount: Int = 0

        func record() {
            effectCount += 1
        }
    }

    @Test("Idempotent body (no effects inside) passes with zero-effect recorders")
    func idempotentNoOpBody() async throws {
        let recorder = CountingRecorder()

        try await assertIdempotentEffects(recorders: [recorder]) {
            // body doesn't touch the recorder → always idempotent
        }

        #expect(recorder.effectCount == 0)
    }

    @Test("Dedup-guarded body: records once on first call, zero on retry")
    func dedupGuardedBody() async throws {
        let recorder = CountingRecorder()

        // Mimics an adopter's dedup-gate shape: "if already done, skip."
        // Here, a boolean gate in the test closure represents whatever
        // the adopter's gate would be (DB unique constraint, dedup
        // cache lookup, whatever).
        let gate = Gate()

        try await assertIdempotentEffects(recorders: [recorder]) {
            guard gate.tryTake() else { return }
            recorder.record()
        }

        // First call: recorder.effectCount went 0 → 1. Second call:
        // gate was already taken, early-return, recorder unchanged.
        #expect(recorder.effectCount == 1)
    }

    @Test("Multiple recorders: all must show zero delta on retry")
    func multipleRecorders() async throws {
        let db = CountingRecorder()
        let email = CountingRecorder()

        // Both recorders increment on first call, neither on retry.
        let dbGate = Gate()
        let emailGate = Gate()

        try await assertIdempotentEffects(recorders: [db, email]) {
            if dbGate.tryTake() {
                db.record()
            }
            if emailGate.tryTake() {
                email.record()
            }
        }

        #expect(db.effectCount == 1)
        #expect(email.effectCount == 1)
    }

    @Test("Empty recorders array: runs body twice, no assertion")
    func emptyRecorders() async throws {
        var invocations = 0

        try await assertIdempotentEffects(recorders: []) {
            invocations += 1
        }

        // Helper always runs the body twice regardless of recorder
        // presence. Useful for adopter code with no instrumentable
        // effects; arguably more smoke-test than idempotency check,
        // but the API accepts it.
        #expect(invocations == 2)
    }

    @Test("Throwing body rethrows through assertIdempotentEffects")
    func throwingBodyRethrows() async {
        let recorder = CountingRecorder()

        do {
            try await assertIdempotentEffects(recorders: [recorder]) {
                throw TestError.synthetic
            }
            Issue.record("Expected throw, got success")
        } catch TestError.synthetic {
            // Expected path — body's throw flows through the rethrows boundary.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Body threw on first invocation, so effectCount stays at 0.
        // The second invocation never ran.
        #expect(recorder.effectCount == 0)
    }

    // MARK: - Helpers

    /// Toy gate simulating an adopter's dedup mechanism. `tryTake()`
    /// returns `true` exactly once; subsequent calls return `false`.
    final class Gate: @unchecked Sendable {
        private var taken = false

        func tryTake() -> Bool {
            guard !taken else { return false }
            taken = true
            return true
        }
    }

    enum TestError: Error {
        case synthetic
    }
}
