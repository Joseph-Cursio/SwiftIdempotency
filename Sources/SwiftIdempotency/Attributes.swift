/// Marks a function as intentionally idempotent — re-invocation with the
/// same arguments produces the same observable result and the same external
/// effects (or no additional effects). Equivalent to the doc-comment form
/// `/// @lint.effect idempotent` for linter purposes.
///
/// ## Linter integration
///
/// `SwiftProjectLint`'s idempotency rules recognise both annotation forms.
/// A function carrying either `@Idempotent` or `/// @lint.effect idempotent`
/// (or both, if consistent) is treated identically by `idempotencyViolation`
/// and `nonIdempotentInRetryContext`.
///
/// ## Current behaviour
///
/// The macro currently expands to no generated code — it exists as a
/// recognisable attribute name the linter can scan. A future expansion
/// (Phase 3 of the macros plan) will generate a companion test function
/// that calls the annotated function twice with identical arguments and
/// asserts observable equivalence.
@attached(peer, names: arbitrary)
public macro Idempotent() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "IdempotentMacro"
)

/// Marks a function as unconditionally non-idempotent — re-invocation
/// produces additional observable effects (sending email, inserting rows,
/// publishing events). Equivalent to `/// @lint.effect non_idempotent`.
@attached(peer)
public macro NonIdempotent() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "NonIdempotentMacro"
)

/// Marks a function as observational — its only side effects are observation
/// primitives (logger calls, metrics emission, span creation) that are
/// retry-safe by convention. Equivalent to `/// @lint.effect observational`.
///
/// Observational functions may be called freely from `@lint.context replayable`
/// / `retry_safe` bodies without producing idempotency diagnostics.
@attached(peer)
public macro Observational() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "ObservationalMacro"
)

/// Marks a function as idempotent *only when routed through a caller-supplied
/// deduplication key* — the shape of Stripe charges, Mailgun deliveries, SNS
/// publishes, and similar APIs that accept a client-provided idempotency
/// token. Equivalent to `/// @lint.effect externally_idempotent(by: <name>)`.
///
/// - Parameter keyParameterName: The external label of the parameter that
///   carries the idempotency key. When provided, the `missingIdempotencyKey`
///   linter rule verifies that call sites pass a stable value at that
///   parameter (rejecting obvious per-invocation generators like `UUID()`).
///   When omitted, the annotation still grants lattice trust but no
///   key-routing verification is performed.
@attached(peer)
public macro ExternallyIdempotent(by keyParameterName: String = "") =
    #externalMacro(
        module: "SwiftIdempotencyMacros",
        type: "ExternallyIdempotentMacro"
    )
