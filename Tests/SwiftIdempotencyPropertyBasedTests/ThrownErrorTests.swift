import Foundation
import PropertyBased
import SwiftIdempotency
import SwiftIdempotencyPropertyBased
import Testing

/// A thrown error from the operation under test is a FAILURE of the property, for both wrappers.
///
/// swift-property-based 1.0.0 through 2.0.1, on Swift 6.2 and later, runs a `propertyCheck` body
/// under `try?` and drops anything it throws, so the property passes
/// (x-sheep/swift-property-based#29). The wrappers therefore catch inside the body and record the
/// error themselves. Each negative control matches only the thrown error (with the step it names)
/// and the library's own "Failure occured with input" report, and then requires that the thrown
/// error was seen — so an unexpected issue, or the report alone, fails the test.
@Suite("Property wrappers record a thrown error as a failure")
struct ThrownErrorTests {
    private struct Refused: Error {}

    /// A store that throws on every second call with the same key — refusing a duplicate is not
    /// retry-idempotent, and is exactly the bug a retry check exists to catch. Counting per key
    /// (rather than refusing any key seen before) keeps the shrinker's replays on the retry too.
    private actor RefusingStore {
        private var calls: [Int: Int] = [:]

        func insert(_ key: Int) throws -> Int {
            calls[key, default: 0] += 1
            guard calls[key, default: 0] % 2 == 1 else { throw Refused() }
            return key
        }
    }

    /// Whether a matcher saw the issue a test requires. `withKnownIssue` passes on ANY matched
    /// issue, so without this the library's own failure report would satisfy it alone.
    private final class Sighting: @unchecked Sendable {
        private let lock = NSLock()
        private var seen = false

        var wasSeen: Bool {
            lock.lock()
            defer { lock.unlock() }
            return seen
        }

        func note(_ matched: Bool) -> Bool {
            guard matched else { return false }
            lock.lock()
            defer { lock.unlock() }
            seen = true
            return true
        }
    }

    private final class RefusingRepo: IdempotentEffectRecorder, @unchecked Sendable {
        private(set) var effectCount = 0
        private var stored: Set<Int> = []

        func insert(_ key: Int) throws {
            guard stored.insert(key).inserted else { throw Refused() }
            effectCount += 1
        }

        deinit { /* no-op */ }
    }

    private static func isRefused(_ issue: Issue) -> Bool {
        issue.error is Refused
    }

    private static func mentions(_ issue: Issue, _ text: String) -> Bool {
        issue.comments.contains { $0.rawValue.contains(text) }
    }

    /// swift-property-based's own report after shrinking ("Failure occured with input …"). It
    /// carries no error and follows any failure, so it is accepted but never sufficient.
    private static func isLibraryReport(_ issue: Issue) -> Bool {
        issue.error == nil && mentions(issue, "with input")
    }

    /// Matches the thrown `Refused` naming `step`, or the library's report; notes the former.
    private static func matchesRefused(_ issue: Issue, during step: String, _ sighting: Sighting) -> Bool {
        sighting.note(isRefused(issue) && mentions(issue, step)) || isLibraryReport(issue)
    }

    @Test("assertIdempotentProperty: an operation that throws on the retry fails")
    func retryThrowFails() async {
        let sighting = Sighting()
        let store = RefusingStore()
        await withKnownIssue("negative control — the second call throws `Refused`") {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { key in
                try await store.insert(key)
            }
        } matching: { issue in
            Self.matchesRefused(issue, during: "second call", sighting)
        }
        #expect(sighting.wasSeen, "the thrown error was never recorded — the property passed on a throw")
    }

    @Test("assertIdempotentProperty: an operation that always throws fails")
    func firstCallThrowFails() async {
        let sighting = Sighting()
        await withKnownIssue("negative control — the first call throws `Refused`") {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { (_: Int) -> Int in
                throw Refused()
            }
        } matching: { issue in
            Self.matchesRefused(issue, during: "first call", sighting)
        }
        #expect(sighting.wasSeen, "the thrown error was never recorded — the property passed on a throw")
    }

    /// `#require` records its own issue before it throws `ExpectationFailedError`. Recording that
    /// error again would report one failure twice — Swift Testing files that second record as
    /// "An API was misused", not as a caught error — so the only issues accepted here are expectation
    /// failures and the library's report.
    @Test("assertIdempotentProperty: try #require inside the operation is reported once")
    func requireIsNotRecordedTwice() async {
        await withKnownIssue("negative control — `#require` fails above 500") {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { key in
                try #require(key <= 500)
                return key
            }
        } matching: { issue in
            if case .expectationFailed = issue.kind { return true }
            return Self.isLibraryReport(issue)
        }
    }

    @Test("assertIdempotentEffectsProperty: apply that throws on the retry pass fails")
    func effectsRetryThrowFails() async {
        let sighting = Sighting()
        await withKnownIssue("negative control — the retry pass throws `Refused`") {
            await assertIdempotentEffectsProperty(
                over: Gen<Int>.int(in: 0 ... 5).array(of: 1 ... 8).map { Array(Set($0)) }
            ) {
                let repo = RefusingRepo()
                return (recorders: [repo], apply: { key in try repo.insert(key) })
            }
        } matching: { issue in
            Self.matchesRefused(issue, during: "retry pass", sighting)
        }
        #expect(sighting.wasSeen, "the thrown error was never recorded — the property passed on a throw")
    }

    @Test("assertIdempotentEffectsProperty: apply that throws on the first pass fails")
    func effectsFirstPassThrowFails() async {
        let sighting = Sighting()
        await withKnownIssue("negative control — a repeated key throws `Refused` in the first pass") {
            await assertIdempotentEffectsProperty(
                over: Gen<Int>.int(in: 0 ... 5).array(of: 1 ... 4).map { $0 + $0 }
            ) {
                let repo = RefusingRepo()
                return (recorders: [repo], apply: { key in try repo.insert(key) })
            }
        } matching: { issue in
            Self.matchesRefused(issue, during: "first pass", sighting)
        }
        #expect(sighting.wasSeen, "the thrown error was never recorded — the property passed on a throw")
    }

    /// The error must be recorded INSIDE the property, where the library counts it — that is what
    /// drives the shrinker and its "Failure occured with input" report. Throwing above 500 only, the
    /// report must name the boundary, 501, beside the thrown error.
    @Test("assertIdempotentProperty: a throw on some inputs is shrunk to the boundary input")
    func partialThrowIsShrunkToItsInput() async {
        let thrown = Sighting()
        let reported = Sighting()
        await withKnownIssue("negative control — the operation throws above 500") {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { key in
                if key > 500 { throw Refused() }
                return key
            }
        } matching: { issue in
            thrown.note(Self.isRefused(issue) && Self.mentions(issue, "first call"))
                || reported.note(Self.isLibraryReport(issue) && Self.mentions(issue, "with input 501."))
        }
        #expect(thrown.wasSeen, "the thrown error was never recorded — the property passed on a throw")
        #expect(reported.wasSeen, "the library never reported the shrunk input 501")
    }

    /// A cancelled task is control flow, not a failure: `recordThrown` skips what is thrown once the
    /// task is cancelled, as Swift Testing does. Shrinking is off so the trial's issues are not
    /// suppressed — with it on, the shrink loop's own cancellation check would hide a regression.
    @Test("a throw caused by cancellation is not recorded as a failure", .shrinking(false))
    func cancellationIsNotAFailure() async {
        let task = Task {
            await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { key in
                withUnsafeCurrentTask { $0?.cancel() }
                try Task.checkCancellation()
                return key
            }
        }
        await task.value
    }

    @Test("a non-throwing, retry-idempotent operation still records nothing")
    func passingOperationRecordsNothing() async {
        await assertIdempotentProperty(over: Gen<Int>.int(in: 0 ... 1_000)) { key in
            key * 2
        }
        await assertIdempotentEffectsProperty(over: Gen<Int>.int(in: 0 ... 5).array(of: 0 ... 8)) {
            let repo = RefusingRepo()
            return (recorders: [repo], apply: { _ in })
        }
    }
}
