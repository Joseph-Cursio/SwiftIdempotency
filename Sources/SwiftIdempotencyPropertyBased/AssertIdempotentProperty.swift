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
///     its two `Equatable` results must be equal.
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
            let first = try await operation(input)
            let second = try await operation(input)
            #expect(
                first == second,
                "operation is not retry-idempotent: a second call with the same input returned \(second), not \(first)",
                sourceLocation: sourceLocation
            )
        },
        sourceLocation: sourceLocation
    )
}
