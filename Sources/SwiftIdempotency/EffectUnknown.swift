/// Marks a function whose idempotency effect **cannot be determined** — the
/// `unknown` tier, given a spelling. Equivalent to the doc-comment form
/// `/// @lint.effect unknown`.
///
/// ## Why this exists
///
/// `unknown` has been in the reference lattice since the start, described as
/// *"the linter could not determine an effect (e.g., calls into an un-annotated
/// third-party API)"* — but it was **inference-only**, with no way for a human
/// to write it down. That left an author with no vocabulary for the commonest
/// honest answer, and pushed them toward `@NonIdempotent`, which claims
/// something much stronger: that tier is *unconditionally* non-idempotent —
/// re-invocation *does* produce additional effects. "I cannot guarantee it" and
/// "it definitely is not" are different statements, and only one of them was
/// writable.
///
/// ## It is NOT the same as no annotation
///
/// An unannotated declaration and an `@EffectUnknown` one both resolve to "no
/// effect known", and that is exactly why the marker earns its keep: they mean
/// different things. Absence says *nobody looked*. This says *someone looked and
/// could not decide* — usually because the body reaches code the analysis cannot
/// see. The distinction is the same one `unknown` already draws from
/// `non_idempotent` by being **incomparable** to it rather than ordered against
/// it: it is not a point on the retry-safety scale, it is the absence of one.
///
/// ## Deliberately not a lattice element in `SwiftEffectInference`
///
/// SEI models the five ordered tiers as a linear chain and its `lub(_:)` is
/// rank-only. `unknown` is incomparable to `non_idempotent`, so admitting it as
/// an `Effect` case would force that chain into a genuine partial order and
/// replace the rank comparison with a Hasse-diagram join — a substantial change
/// to the core algebra, which SEI declined for exactly this tier. This marker
/// therefore ships the *spelling* without asking for that: a consumer reads it
/// the way `@ClockDeterministic` is read, as its own question rather than as a
/// point on the effect scale.
///
/// ## Usage
///
/// ```swift
/// @EffectUnknown
/// func settle(_ order: Order) -> Order {
///     ThirdPartyLedger.post(order)   // no annotations, no source
///     return order
/// }
/// ```
@attached(peer)
public macro EffectUnknown() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "EffectUnknownMacro"
)
