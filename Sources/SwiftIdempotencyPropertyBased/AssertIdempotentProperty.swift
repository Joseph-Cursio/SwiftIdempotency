import PropertyBased
import Testing

/// Property-based **retry-idempotence** assertion (v0.4.0).
///
/// For each input drawn from `generator`, runs `operation` **twice** and
/// asserts the two results are equal — i.e. the operation is idempotent *on
/// retry* (calling it again with the same input yields the same observable
/// result). This is SwiftIdempotency's notion of idempotence (effects don't
/// accumulate across retries), not the algebraic `f(f(x)) == f(x)`.
///
/// ## Why not just `#assertIdempotent` in a `propertyCheck` loop?
///
/// `#assertIdempotent { … }` fails via `precondition`, which terminates the
/// test process — so on a failing property the process dies *before*
/// `swift-property-based`'s shrinker can find a minimal counterexample. This
/// function instead records a Testing issue (`#expect`), which composes with
/// the shrinker: a failing run is shrunk to the **minimal failing input**,
/// reported by `swift-property-based`.
///
/// The cost is worse than an unshrunk counterexample — it is *no* counterexample.
/// A shrinker minimises by running the property **again** on smaller inputs, and a
/// trapping assertion denies it the "again"; the process dies holding the value.
/// Measured on the same bug (non-idempotent only above 100), `#assertIdempotent`
/// reports `Precondition failed: …` and signal 5 with no mention of the input,
/// while this function reports `Failure occured with input 101.` — the boundary
/// itself. Verified 2026-07-16; see `docs/property-based/trial-findings.md`, whose
/// earlier reasoned-but-unverified prediction of a "raw randomised input" was
/// optimistic.
///
/// ## Usage
///
/// ```swift
/// @Test func upsertIsRetryIdempotent() async {
///     let service = UserService()
///     await assertIdempotentProperty(over: Gen<Int>.int(in: 0...1_000)) { id in
///         await service.upsert(id)   // run twice per id; results must match
///     }
/// }
/// ```
///
/// - Parameters:
///   - generator: Produces the inputs the operation is exercised over.
///   - count: Trial count (default 100). Ignored under a fixed seed.
///   - operation: The operation under test. Run twice per generated input;
///     its two `Equatable` results must be equal. An error it throws on either
///     call fails the property and is reported with that input. The shrinker
///     replays inputs, so an operation that keeps state across calls (like the
///     shared `service` above) can have a retry failure reported as a failure of
///     the first call.
public func assertIdempotentProperty<Input, Result: Equatable, Shrinker: Sequence>(
    over generator: Generator<Input, Shrinker>,
    count: Int = 100,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: (Input) async throws -> Result
) async {
    await propertyCheck(
        count: count,
        input: generator,
        perform: { input in
            // Catch here: swift-property-based drops what a `propertyCheck` body throws (#29).
            let first: Result
            do {
                first = try await operation(input)
            } catch {
                recordThrown(error, during: "the first call", sourceLocation: sourceLocation)
                return
            }
            let second: Result
            do {
                second = try await operation(input)
            } catch {
                recordThrown(error, during: "the second call with the same input", sourceLocation: sourceLocation)
                return
            }
            #expect(
                first == second,
                "operation is not retry-idempotent: a second call with the same input returned \(second), not \(first)",
                sourceLocation: sourceLocation
            )
        },
        sourceLocation: sourceLocation
    )
}

/// Records an error the operation under test threw as a failure of the property.
///
/// swift-property-based 1.0.0 through 2.0.1, on Swift 6.2 and later, runs a `propertyCheck` body
/// under `try?`, so an error that escapes the body is dropped and the property passes
/// (x-sheep/swift-property-based#29). Both wrappers therefore catch inside the body and record the
/// error here, which keeps the failure visible to the shrinker on every release and toolchain.
///
/// Two kinds of error are not recorded:
/// - `ExpectationFailedError`: `#require` records its own issue before it throws one, so recording
///   it again would report one failure twice.
/// - anything thrown once the task is cancelled (a `CancellationError`, `Test.cancel()`, a
///   `.timeLimit` expiry): recording it would turn a cancelled test into a failure pinned on
///   whatever input was running. This is broader than Swift Testing, which skips only a
///   `CancellationError` (or `Test.cancel()`'s internal error) and still records anything else
///   thrown after a cancel. `Test.cancel()`'s error cannot be matched by type outside the
///   framework, and the test is reported cancelled either way, so this drops it all.
func recordThrown(_ error: any Error, during step: String, sourceLocation: SourceLocation) {
    guard !(error is ExpectationFailedError), !Task.isCancelled else { return }
    Issue.record(error, "the operation threw during \(step)", sourceLocation: sourceLocation)
}
