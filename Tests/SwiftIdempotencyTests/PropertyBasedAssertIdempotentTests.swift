import Testing
import PropertyBased
import SwiftIdempotency

/// Demonstrates wrapping `#assertIdempotent` in a property-based test via
/// `swift-property-based`'s `propertyCheck`.
///
/// The pattern: `propertyCheck` supplies generated inputs; each iteration
/// applies `#assertIdempotent` to the operation under test. The macro runs
/// the operation twice per iteration and asserts observable equivalence,
/// so a 100-iteration `propertyCheck` exercises the operation 200 times
/// with paired checks.
///
/// Both sync and async variants are covered. The async variant exercises
/// an actor-isolated operation, demonstrating that state-threading across
/// the two invocations the macro performs converges correctly when the
/// operation is genuinely idempotent.
///
/// Note on failure modes: `#assertIdempotent` uses `precondition`, which
/// terminates the test process on failure. That's strictly harder than
/// PropertyBased's own `#expect` layer, which records issues without
/// crashing. On a failing property, the process dies before the library's
/// shrinker can find a minimal counter-example. A future non-fatal failure
/// mode (e.g. `Issue.record`) would compose with PropertyBased's shrinker
/// for free.
@Suite("#assertIdempotent — property-based wrap pattern")
struct PropertyBasedAssertIdempotentTests {

    /// Idempotent pure operation: inserting `value` into a sorted unique
    /// list produces the same list whether called once or twice.
    static func insertSortedUnique(_ value: Int, into base: [Int]) -> [Int] {
        if base.contains(value) { return base }
        return (base + [value]).sorted()
    }

    /// Actor-isolated idempotent operation: repeated inserts of the same
    /// value converge on the same observable `Set`.
    actor UniqueBag {
        private var contents: Set<Int> = []

        func insert(_ value: Int) -> Set<Int> {
            contents.insert(value)
            return contents
        }
    }

    @Test("sync — insertSortedUnique is idempotent across generated ints")
    func insertSortedUnique_propertyBased() async {
        await propertyCheck(input: Gen.int(in: -100...100)) { value in
            _ = #assertIdempotent {
                Self.insertSortedUnique(value, into: [1, 5, 10, 15])
            }
        }
    }

    @Test("async — actor-isolated UniqueBag.insert is idempotent across generated ints")
    func uniqueBagInsert_propertyBased() async {
        await propertyCheck(input: Gen.int(in: -100...100)) { value in
            let bag = Self.UniqueBag()
            _ = await #assertIdempotent {
                await bag.insert(value)
            }
        }
    }
}
