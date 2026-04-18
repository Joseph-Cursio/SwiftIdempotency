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
/// ## Test generation
///
/// Marker-only since the round-8 peer-macro redesign. Test generation is
/// handled by `@IdempotencyTests` at the enclosing `@Suite` type — it
/// scans members and emits `@Test` methods in an extension for every
/// `@Idempotent`-marked zero-argument function. See Finding 4 in
/// `docs/phase5-round-7/trial-findings.md` for the empirical reason the
/// original peer-macro design couldn't ship, and
/// `docs/phase5-round-8/trial-findings.md` for the extension-role
/// redesign that did ship.
@attached(peer)
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

/// Candidate A — member-macro redesign attached to a `@Suite` type.
/// Scans the attached type's members for `@Idempotent`-marked
/// zero-argument functions and emits one `@Test` method per match.
///
///     @Suite
///     @IdempotencyTests
///     struct IdempotencyChecks {
///         @Idempotent
///         func currentSystemStatus() -> Int { 200 }
///     }
///
/// See `IdempotencyTestsMacro` for the empirical constraints this shape
/// was redesigned around (round-8 spike).
@attached(extension, names: arbitrary)
public macro IdempotencyTests() = #externalMacro(
    module: "SwiftIdempotencyMacros",
    type: "IdempotencyTestsMacro"
)
