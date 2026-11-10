@testable import IdempotencyTestsSample
import Testing

// MARK: - Hand-written sanity tests
//
// Non-macro tests against the same library code. Keep these so a failure
// in the library itself produces a diagnostic that doesn't route through
// the generated `@IdempotencyTests` expansion — easier to debug a
// pricing regression when the failing test isn't macro-generated.

@Suite("PricingCalculator direct checks")
struct PricingCalculatorDirectTests {

    @Test("priceInCents is deterministic for fixed inputs")
    func priceInCentsDeterministic() {
        let first = PricingCalculator.priceInCents(kilograms: 5, ratePerKgCents: 250)
        let second = PricingCalculator.priceInCents(kilograms: 5, ratePerKgCents: 250)
        #expect(first == second)
        #expect(first == 1_250)
    }

    @Test("systemStatus returns the documented fixed value")
    func systemStatusFixedValue() {
        #expect(PricingCalculator.systemStatus() == "healthy")
    }
}
