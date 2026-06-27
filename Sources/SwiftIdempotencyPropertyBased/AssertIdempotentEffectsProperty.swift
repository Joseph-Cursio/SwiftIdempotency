import PropertyBased
@_spi(Internals)
import SwiftIdempotency
import Testing

/// Property-based **effect** idempotence over generated action *sequences*
/// (v0.4.0, W6.C) — the seed of model-based testing.
///
/// For each generated sequence of actions, builds a fresh system, applies the
/// whole sequence **twice** (the retry), and asserts that the second pass adds
/// **no new effects** — i.e. retrying the sequence is effect-idempotent. On
/// failure, `swift-property-based`'s shrinker reduces the action array to the
/// **minimal sequence** that breaks retry-safety.
///
/// This is the effect-counting analogue of `assertIdempotentProperty`: where
/// that compares *return values* across a retry, this compares
/// `IdempotentEffectRecorder` snapshots (observable writes) across a retry of a
/// whole sequence. Like `assertIdempotentProperty`, failures are recorded as
/// Testing issues (non-fatal) so they compose with the shrinker.
///
/// ## Usage
///
/// ```swift
/// @Test func handlerIsEffectIdempotentAcrossSequences() async {
///     await assertIdempotentEffectsProperty(
///         over: Gen<Int>.int(in: 0...5).array(of: 0...8)
///     ) {
///         let repo = MockRepo()                       // fresh per trial
///         let handler = Handler(repo: repo)
///         return (recorders: [repo], apply: { id in await handler.upsert(id) })
///     }
/// }
/// ```
///
/// - Parameters:
///   - actions: Generates the action sequence per trial (e.g. an element
///     generator `.array(of:)`). Its array shrinker drives minimization.
///   - count: Trial count (default 100). Ignored under a fixed seed.
///   - makeRun: Builds a **fresh** system per trial, returning the effect
///     recorders to observe and an `apply` closure that runs one action against
///     that system. Freshness per trial keeps trials independent.
public func assertIdempotentEffectsProperty<Action, Shrinker: Sequence>(
    over actions: Generator<[Action], Shrinker>,
    count: Int = 100,
    sourceLocation: SourceLocation = #_sourceLocation,
    makeRun: () -> (recorders: [any IdempotentEffectRecorder], apply: (Action) async throws -> Void)
) async {
    await propertyCheck(
        count: count,
        input: actions,
        perform: { sequence in
            let run = makeRun()
            for action in sequence { try await run.apply(action) }
            let afterFirst = run.recorders.map { $0._snapshotBox() }
            for action in sequence { try await run.apply(action) }
            let afterSecond = run.recorders.map { $0._snapshotBox() }
            for index in afterFirst.indices {
                #expect(
                    afterFirst[index].equals(afterSecond[index]),
                    """
                    effect non-idempotence: retrying the action sequence added effects \
                    (recorder \(index): \(afterFirst[index].description) \
                    vs \(afterSecond[index].description))
                    """,
                    sourceLocation: sourceLocation
                )
            }
        },
        sourceLocation: sourceLocation
    )
}
