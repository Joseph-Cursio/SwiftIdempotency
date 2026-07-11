/// Marks a function as **pure** — referentially transparent: no side
/// effects, deterministic, and total, and (by contract) *synchronous*.
/// Equivalent to the doc-comment form `/// @lint.effect pure`.
///
/// ## The strongest claim on the lattice
///
/// `pure` sits at the bottom of the effect lattice, below `@Observational`
/// and `@Idempotent`: a pure function is trivially retry-safe because a
/// replay changes nothing and observes nothing. Note the synchronous part
/// of the contract — an `async` function cannot be pure (awaiting is an
/// interaction with the scheduler and, usually, with time). For an async
/// function that is deterministic *given an injected `Clock`*, use
/// `@ClockDeterministic`, which makes the orthogonal
/// `@lint.determinism` claim instead.
///
/// ## Analysis can refute this claim, never verify it
///
/// `SwiftEffectInference`'s `PurityInferrer` is deliberately one-sided: it
/// scans for purity *refuters* (side-effect APIs, nondeterminism sources,
/// partiality like `try!`/`fatalError`, and `async`/`throws` themselves)
/// and can prove a claim wrong, but no static analysis soundly proves a
/// function pure. That asymmetry is why the user-declared marker exists —
/// and why SwiftInferProperties surfaces "this looks pure — consider
/// annotating it" advisories for human review rather than annotating
/// automatically. Downstream, a `@Pure`-seeded function earns the generic
/// determinism law (`f(x) == f(x)` over generated inputs), which is the
/// runtime check that catches a wrong claim.
///
/// ## Usage
///
/// ```swift
/// @Pure
/// func normalize(_ path: String) -> String { ... }
/// ```
@attached(peer)
public macro Pure() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "PureMacro"
)
