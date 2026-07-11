/// Marks an `async` function as **deterministic given an injected `Clock`**
/// — its observable behavior is a pure function of its inputs once time is
/// a parameter rather than an ambient effect. Equivalent to the doc-comment
/// form `/// @lint.determinism clock_deterministic`.
///
/// ## Not an effect tier
///
/// This marker is deliberately orthogonal to the idempotency/effect family
/// (`@Pure` implies *synchronous* referential transparency; the retry-safety
/// tiers say nothing about time). It lives in its own `@lint.determinism`
/// doc-comment namespace for the same reason. Attaching it grants no
/// lattice trust — it makes a *determinism* claim.
///
/// ## Tooling integration
///
/// `SwiftEffectInference`'s `EffectAnnotationParser.isClockDeterministic(declaration:)`
/// recognises both spellings, and `SwiftInferProperties` consumes the claim
/// as a conjunction gate on its async vetoes: an annotated async function
/// earns the generic determinism law (`(await f(x)) == (await f(x))` over
/// generated inputs), and an annotated async view-model method joins the
/// synthetic action surface with an awaited dispatcher — un-annotated
/// async stays excluded, because it would make seeded sequence replays
/// nondeterministic.
///
/// ## The claim is checkable
///
/// The annotation asserts exactly the property SwiftPropertyLaws'
/// `TimedAsyncSequence.debounceIsDeterministicUnderTestClock` law states:
/// under a virtual clock, two runs produce identical output. Annotate a
/// function that secretly reads `Date()` or sleeps on a clock it didn't
/// inject, and the emitted determinism law is the test that falsifies the
/// claim. (The pbt-book's Chapter 22 §22.6 is the worked walkthrough.)
///
/// ## Usage
///
/// ```swift
/// private let clock: any Clock<Duration>
///
/// @ClockDeterministic
/// func refresh() async {
///     try? await clock.sleep(for: .milliseconds(40), tolerance: nil)
///     syncCount += 1
/// }
/// ```
@attached(peer)
public macro ClockDeterministic() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "ClockDeterministicMacro"
)
