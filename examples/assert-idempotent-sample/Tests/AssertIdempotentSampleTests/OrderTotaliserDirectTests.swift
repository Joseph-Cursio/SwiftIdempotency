@testable import AssertIdempotentSample
import Testing

// MARK: - Hand-written sanity tests
//
// Non-macro tests against the same library code. Keep these so a
// pricing regression produces a diagnostic that doesn't route through
// the macro's runtime precondition — easier to locate a library bug
// when the failing test isn't the one comparing two invocations.

@Suite("OrderTotaliser direct checks")
struct OrderTotaliserDirectTests {

    @Test("totalCents is deterministic for fixed inputs")
    func totalCentsDeterministic() {
        let items: [OrderTotaliser.LineItem] = [
            .init(quantity: 2, unitPriceCents: 500),
        ]
        let first = OrderTotaliser.totalCents(for: items)
        let second = OrderTotaliser.totalCents(for: items)
        #expect(first == second)
        #expect(first == 1_000)
    }

    @Test("totalCentsValidated rejects negative quantities")
    func rejectsNegative() {
        let items: [OrderTotaliser.LineItem] = [
            .init(quantity: -1, unitPriceCents: 500),
        ]
        #expect(throws: OrderTotaliser.ValidationError.negativeInput) {
            try OrderTotaliser.totalCentsValidated(for: items)
        }
    }
}

// MARK: - Compile-time and type-constraint notes (documented, not executed)
//
// 1. The macro is generic over `Result: Equatable`. A closure returning
//    a non-Equatable type won't type-check — Swift routes this through
//    ordinary overload resolution, not a macro diagnostic. For example
//    `#assertIdempotent { NonEquatableStruct() }` fails with a standard
//    "argument type does not conform to Equatable" error.
//
// 2. The macro requires a closure literal. `#assertIdempotent()` with
//    no closure produces the diagnostic
//    "#assertIdempotent requires a closure literal argument,
//     e.g. `#assertIdempotent { ... }`" at the macro call site.
//
// Both are deliberate — the macro's runtime helpers pin the closure's
// return type to Equatable so `==` comparison is well-defined, and the
// closure is the only argument the macro knows how to rewrite.
