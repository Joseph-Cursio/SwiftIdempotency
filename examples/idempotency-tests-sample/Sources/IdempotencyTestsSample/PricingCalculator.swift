import Foundation

/// A pure pricing calculator the test suite exercises through
/// `@IdempotencyTests`. Pure functions are the motivating case for the
/// extension macro: no side effects, no arguments the macro couldn't
/// synthesise, and a deterministic return value that a double-invocation
/// check can compare directly.
public enum PricingCalculator {

    /// Deterministic price-in-cents for a given weight and unit rate.
    ///
    /// No I/O, no time-dependent state — calling this twice with the same
    /// arguments is the definition of idempotent. That's the contract the
    /// test-suite wrapper asserts at the function level.
    public static func priceInCents(kg: Int, ratePerKgCents: Int) -> Int {
        kg * ratePerKgCents
    }

    /// Observable system status — a placeholder stand-in for something a
    /// real adopter might want to freeze as idempotent ("health endpoint
    /// response is stable under retry"). Returning a fixed string keeps
    /// the sample's scope to the macro shape, not the thing being tested.
    public static func systemStatus() -> String {
        "healthy"
    }
}
