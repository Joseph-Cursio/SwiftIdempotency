import PropertyBased
import SwiftIdempotencyPropertyBased
import Testing

/// v0.4.0 — `assertIdempotentProperty` tests: generated-input, non-fatal,
/// shrinking retry-idempotence assertions.
@Suite("assertIdempotentProperty — v0.4.0")
struct AssertIdempotentPropertyTests {
    /// Pure idempotent operation: inserting into a sorted-unique list yields
    /// the same list on a second call with the same input.
    private static func insertSortedUnique(_ value: Int, into base: [Int]) -> [Int] {
        base.contains(value) ? base : (base + [value]).sorted()
    }

    @Test("a pure idempotent operation holds across generated inputs")
    func pureIdempotentHolds() async {
        await assertIdempotentProperty(over: Gen<Int>.int(in: -100 ... 100)) { value in
            Self.insertSortedUnique(value, into: [1, 5, 10, 15])
        }
    }

    /// Actor-isolated idempotent operation: repeated inserts of the same value
    /// converge on the same observable `Set` (retry-safe).
    private actor UniqueBag {
        private var contents: Set<Int> = []

        func insert(_ value: Int) -> Set<Int> {
            contents.insert(value)
            return contents
        }
    }

    @Test("an effectful but retry-idempotent operation holds across generated inputs")
    func effectfulIdempotentHolds() async {
        let bag = UniqueBag()

        await assertIdempotentProperty(over: Gen<Int>.int(in: -100 ... 100)) { value in
            await bag.insert(value)
        }
    }

    /// Non-idempotent operation: a counter returns a different value on each
    /// call, so the second call never matches the first.
    private actor Counter {
        private var current = 0

        func next() -> Int {
            current += 1
            return current
        }
    }

    @Test("a non-retry-idempotent operation records a failure (composes with the shrinker, no crash)")
    func nonIdempotentFails() async {
        let counter = Counter()

        // The assertion records a Testing issue rather than `precondition`-
        // crashing, so `withKnownIssue` can observe the failure — the property
        // that makes it compose with swift-property-based's shrinker.
        await withKnownIssue("negative control — the assertion is EXPECTED to record non-idempotency here; a pass without this issue would mean the detector went blind") {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 10)) { _ in
                await counter.next()
            }
        }
    }
}
