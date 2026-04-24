import Testing
import SwiftIdempotency
import SwiftIdempotencyTestSupport

/// Unit tests for `assertIdempotentEffects` in
/// `SwiftIdempotencyTestSupport` + the `IdempotentEffectRecorder`
/// protocol in `SwiftIdempotency` (moved to the main target in v0.3.0).
///
/// Failure-path tests use `failureMode: .issueRecord` + `withKnownIssue`
/// to exercise detected non-idempotency without aborting the process.
/// The `.preconditionFailure` path isn't directly tested because it
/// terminates the test process by design; its correctness is verified
/// by the shared message-rendering code path exercised by `.issueRecord`.
@Suite("assertIdempotentEffects — Option B")
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
    func idempotentNoOpBody() async {
        let recorder = CountingRecorder()

        await assertIdempotentEffects(recorders: [recorder]) {
            // body doesn't touch the recorder → always idempotent
        }

        #expect(recorder.effectCount == 0)
    }

    @Test("Dedup-guarded body: records once on first call, zero on retry")
    func dedupGuardedBody() async {
        let recorder = CountingRecorder()

        // Mimics an adopter's dedup-gate shape: "if already done, skip."
        // Here, a boolean gate in the test closure represents whatever
        // the adopter's gate would be (DB unique constraint, dedup
        // cache lookup, whatever).
        let gate = Gate()

        await assertIdempotentEffects(recorders: [recorder]) {
            guard gate.tryTake() else { return }
            recorder.record()
        }

        // First call: recorder.effectCount went 0 → 1. Second call:
        // gate was already taken, early-return, recorder unchanged.
        #expect(recorder.effectCount == 1)
    }

    @Test("Multiple recorders: all must show zero delta on retry")
    func multipleRecorders() async {
        let databaseWrites = CountingRecorder()
        let email = CountingRecorder()

        // Both recorders increment on first call, neither on retry.
        let databaseGate = Gate()
        let emailGate = Gate()

        await assertIdempotentEffects(recorders: [databaseWrites, email]) {
            if databaseGate.tryTake() {
                databaseWrites.record()
            }
            if emailGate.tryTake() {
                email.record()
            }
        }

        #expect(databaseWrites.effectCount == 1)
        #expect(email.effectCount == 1)
    }

    @Test("Empty recorders array: runs body twice, no assertion")
    func emptyRecorders() async {
        var invocations = 0

        await assertIdempotentEffects(recorders: []) {
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

    // MARK: - R1: failureMode

    @Test("failureMode: .issueRecord reports via Testing without aborting")
    func issueRecordFailureMode_nonIdempotentBody_recordsIssueAndContinues() async {
        let recorder = CountingRecorder()

        await withKnownIssue {
            await assertIdempotentEffects(
                recorders: [recorder],
                failureMode: .issueRecord
            ) {
                // Unconditionally records: non-idempotent by construction.
                recorder.record()
            }
        }

        // Both invocations ran because .issueRecord doesn't abort.
        // First call: 0 → 1. Second call: 1 → 2. Snapshot comparison
        // (1 vs 2) fires the recorded issue captured by withKnownIssue.
        #expect(recorder.effectCount == 2)
    }

    @Test("failureMode: .issueRecord reports one issue per non-idempotent recorder")
    func issueRecordFailureMode_multipleRecordersAllFire_recordsIssuePerRecorder() async {
        let alpha = CountingRecorder()
        let beta = CountingRecorder()

        await withKnownIssue {
            await assertIdempotentEffects(
                recorders: [alpha, beta],
                failureMode: .issueRecord
            ) {
                alpha.record()
                beta.record()
            }
        } matching: { issue in
            // Both alpha and beta are non-idempotent; two issues are
            // recorded inside the single withKnownIssue scope.
            issue.comments.contains { $0.rawValue.contains("CountingRecorder") }
        }

        #expect(alpha.effectCount == 2)
        #expect(beta.effectCount == 2)
    }

    // MARK: - R2: Snapshot associatedtype

    @Test("Custom Snapshot ([String] call log): idempotent body passes")
    func customSnapshotType_dedupGuardedBody_passes() async {
        let recorder = CallLogRecorder()
        let gate = Gate()

        await assertIdempotentEffects(recorders: [recorder]) {
            guard gate.tryTake() else { return }
            recorder.record("putItem(id=42)")
        }

        #expect(recorder.callLog == ["putItem(id=42)"])
    }

    @Test("Custom Snapshot: non-idempotent body fires via .issueRecord")
    func customSnapshotType_nonIdempotentBody_firesOnSnapshotMismatch() async {
        let recorder = CallLogRecorder()
        var invocation = 0

        await withKnownIssue {
            await assertIdempotentEffects(
                recorders: [recorder],
                failureMode: .issueRecord
            ) {
                invocation += 1
                // Different string each invocation → snapshot diverges
                // even though effectCount increments uniformly (so a
                // count-only check would also catch it; the point is
                // the richer Snapshot type is wired through).
                recorder.record("call#\(invocation)")
            }
        }

        #expect(recorder.callLog == ["call#1", "call#2"])
    }

    // MARK: - Default Snapshot (Int) behavior

    @Test("Default Snapshot == Int: recorder without custom snapshot() gets effectCount-backed default")
    func defaultIntSnapshot_matchesEffectCount() async {
        let recorder = CountingRecorder()
        recorder.record()
        recorder.record()

        // Where-clause extension on IdempotentEffectRecorder where Snapshot == Int
        // provides snapshot() -> Int returning effectCount. CountingRecorder
        // declares no typealias → Snapshot defaults to Int → this works.
        #expect(recorder.snapshot() == 2)
        #expect(recorder.snapshot() == recorder.effectCount)
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

/// Recorder that opts into a richer `Snapshot` — an ordered call log
/// rather than an integer count. Lets `assertIdempotentEffects` detect
/// non-idempotency invisible to `effectCount` alone (e.g. retries that
/// undo-then-redo, leaving count unchanged but snapshot diverged).
///
/// File-scope rather than nested in `AssertIdempotentEffectsTests` to
/// avoid a SwiftLint `nesting` violation on the `Snapshot` typealias —
/// a typealias inside a class inside a struct is depth-2, which the
/// default nesting rule forbids.
final class CallLogRecorder: IdempotentEffectRecorder, @unchecked Sendable {
    typealias Snapshot = [String]

    private(set) var callLog: [String] = []
    var effectCount: Int { callLog.count }

    func record(_ operation: String) {
        callLog.append(operation)
    }

    func snapshot() -> [String] { callLog }
}
