import Foundation

/// The production-shape API the `#assertIdempotent` call-site tests
/// exercise. All methods are pure — the adopter's value from using the
/// macro comes from the **call site** (asserting a specific call is
/// idempotent under a specific binding) rather than from the function
/// signature.
public enum OrderTotaliser {

    public struct LineItem: Sendable, Equatable {
        public let quantity: Int
        public let unitPriceCents: Int

        public init(quantity: Int, unitPriceCents: Int) {
            self.quantity = quantity
            self.unitPriceCents = unitPriceCents
        }
    }

    /// Deterministic total. Same inputs → same output, synchronously.
    public static func totalCents(for items: [LineItem]) -> Int {
        items.reduce(0) { sum, item in
            sum + item.quantity * item.unitPriceCents
        }
    }

    /// Deterministic total computed through an async boundary — the
    /// sample's stand-in for "the real implementation awaits a cached
    /// pricing service." The point the sample makes is that
    /// `#assertIdempotent`'s async overload passes `try await` through
    /// the closure transparently.
    public static func totalCentsAsync(for items: [LineItem]) async -> Int {
        totalCents(for: items)
    }

    /// Throwing variant — used to demonstrate that the macro's
    /// expansion preserves the closure's throwing effect. A throwing
    /// closure produces an expression the caller must `try`.
    public static func totalCentsValidated(for items: [LineItem]) throws -> Int {
        guard items.allSatisfy({ $0.quantity >= 0 && $0.unitPriceCents >= 0 })
        else {
            throw ValidationError.negativeInput
        }
        return totalCents(for: items)
    }

    public enum ValidationError: Error, Equatable {
        case negativeInput
    }
}
