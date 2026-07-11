import PropertyBased
import SwiftIdempotency
import SwiftIdempotencyPropertyBased
import Testing

/// v0.4.0 (W6.C) — `assertIdempotentEffectsProperty` tests: generated
/// action-sequence effect-idempotence with shrinking.
@Suite("assertIdempotentEffectsProperty — v0.4.0 W6.C")
struct AssertIdempotentEffectsPropertyTests {
    /// Effect-idempotent: an upsert that counts an effect only when it actually
    /// changes state, so retrying a sequence adds nothing.
    private final class SetRepo: IdempotentEffectRecorder, @unchecked Sendable {
        private(set) var effectCount = 0
        private var stored: Set<Int> = []

        func upsert(_ value: Int) {
            if stored.insert(value).inserted {
                effectCount += 1
            }
        }

        deinit { /* no-op */ }
    }

    /// Non-effect-idempotent: an append that always records an effect, so
    /// retrying a non-empty sequence doubles the effects.
    private final class AppendRepo: IdempotentEffectRecorder, @unchecked Sendable {
        private(set) var effectCount = 0
        private var log: [Int] = []

        func append(_ value: Int) {
            log.append(value)
            effectCount += 1
        }

        deinit { /* no-op */ }
    }

    @Test("effect-idempotent upsert holds across generated action sequences")
    func effectIdempotentHolds() async {
        await assertIdempotentEffectsProperty(
            over: Gen<Int>.int(in: 0 ... 5).array(of: 0 ... 8)
        ) {
            let repo = SetRepo()
            return (recorders: [repo], apply: { value in repo.upsert(value) })
        }
    }

    @Test("non-effect-idempotent append records an issue (shrinks to a minimal sequence)")
    func nonEffectIdempotentFails() async {
        // `array(of: 1...8)` keeps sequences non-empty so the retry always
        // doubles the appended effects; the assertion records a Testing issue
        // (non-fatal) so the shrinker can minimize and `withKnownIssue` observes.
        await withKnownIssue("negative control — the assertion is EXPECTED to record non-idempotency here; a pass without this issue would mean the detector went blind") {
            await assertIdempotentEffectsProperty(
                over: Gen<Int>.int(in: 0 ... 5).array(of: 1 ... 8)
            ) {
                let repo = AppendRepo()
                return (recorders: [repo], apply: { value in repo.append(value) })
            }
        }
    }
}
