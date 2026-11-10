@testable import AssertIdempotentSample
import Foundation
import SwiftIdempotency
import Testing

/// Consumer-side exercise of the `#assertIdempotent` freestanding
/// expression macro. Each test picks a specific call site — a binding
/// of inputs — and asserts the invocation is idempotent under that
/// binding.
///
/// `#assertIdempotent` is the call-site complement to the function-level
/// `@IdempotencyTests` extension macro: where `@IdempotencyTests`
/// generates tests for zero-argument `@Idempotent` members, this macro
/// lets a test author freeze a specific argument binding and check the
/// call twice under that binding. Real-world signatures almost always
/// take arguments, so this is the form most tests end up using.
///
/// The macro has two overloads, chosen by Swift's overload resolution
/// based on whether the closure body contains `await`. Each runtime
/// helper is `rethrows`, so the closure's own throwing effect flows
/// through — `try` is present at the call site only when the closure
/// body can throw:
///
/// - Sync non-throwing:  `let r = #assertIdempotent { ... }`
/// - Sync throwing:      `let r = try #assertIdempotent { try ... }`
/// - Async non-throwing: `let r = await #assertIdempotent { await ... }`
/// - Async throwing:     `let r = try await #assertIdempotent { try await ... }`
///
/// The runtime helper re-invokes the closure twice and `precondition`s
/// that the two return values are equal under `==`. The return value
/// of the macro expression is the first invocation's result, so
/// assignment reads naturally at the call site.
@Suite("#assertIdempotent call-site tests against OrderTotaliser")
struct AssertIdempotentTests {

    private static let items: [OrderTotaliser.LineItem] = [
        .init(quantity: 2, unitPriceCents: 500),
        .init(quantity: 3, unitPriceCents: 750),
    ]

    // MARK: - Sync overload

    @Test("Sync non-throwing — overload resolution picks the sync form")
    func syncNonThrowing() {
        let total = #assertIdempotent {
            OrderTotaliser.totalCents(for: Self.items)
        }
        #expect(total == 2 * 500 + 3 * 750)
    }

    @Test("Sync throwing — try flows through the closure effect")
    func syncThrowing() throws {
        let total = try #assertIdempotent {
            try OrderTotaliser.totalCentsValidated(for: Self.items)
        }
        #expect(total == 2 * 500 + 3 * 750)
    }

    // MARK: - Async overload

    @Test("Async non-throwing — await alone (no try) flows through")
    func asyncNonThrowing() async {
        let total = await #assertIdempotent {
            await OrderTotaliser.totalCentsAsync(for: Self.items)
        }
        #expect(total == 2 * 500 + 3 * 750)
    }

    @Test("Async throwing — both effects flow through")
    func asyncThrowing() async throws {
        let total = try await #assertIdempotent {
            let sync = try OrderTotaliser.totalCentsValidated(for: Self.items)
            return await withUnsafeContinuation { continuation in continuation.resume(returning: sync) }
        }
        #expect(total == 2 * 500 + 3 * 750)
    }

    // MARK: - Bindings that differ across invocations would fail
    //
    // The test below is green because both invocations of the closure
    // see the same `items` value. If the closure captured a per-
    // invocation source of change — `Date()`, `UUID()`, a mutable
    // counter — the two return values would diverge and the macro's
    // runtime helper would trip its `precondition`.
    //
    // Uncomment the block to see the assertion fire:
    //
    //     @Test("Counter-changing closure trips the assertion at runtime")
    //     func counterChangingClosureFails() {
    //         var counter = 0
    //         _ = #assertIdempotent {
    //             counter += 1
    //             return counter
    //         }
    //         // Reaches precondition("#assertIdempotent: closure returned
    //         // different values on re-invocation — not idempotent").
    //     }
    //
    // This is a **runtime** check, not a compile-time one. Compile-time
    // enforcement of call-site argument stability is the linter's job
    // (SwiftProjectLint's `idempotencyViolation` / `missingIdempotencyKey`
    // rules). The macro handles the dynamic half — observing the actual
    // return values during a test run.
}
