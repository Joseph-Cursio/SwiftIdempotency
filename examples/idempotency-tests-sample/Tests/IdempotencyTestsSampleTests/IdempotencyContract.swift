import Foundation
@testable import IdempotencyTestsSample
import SwiftIdempotency
import Testing

/// Consumer-side exercise of `@IdempotencyTests`. The macro sits on a
/// `@Suite` type and scans the type's `@Idempotent`-marked zero-argument
/// members, emitting one `@Test` method per match in a generated
/// extension. Each emitted test calls the wrapped function twice and
/// `#expect`s the two return values are equal.
///
/// The root package's unit tests verify the **expansion source**; this
/// sample is the companion end-to-end check — the expanded code actually
/// compiles against Swift Testing and runs green in a downstream SPM
/// package.
///
/// Running `swift test` inside this directory exercises:
///
/// - `testIdempotencyOfSystemStatusIsHealthy()` (generated — sync target)
/// - `testIdempotencyOfPricingForFiveKilos()` (generated — sync target)
/// - `testIdempotencyOfAsyncStatusProbe()` (generated — async target, the
///   effect-matrix branch the root expansion tests verify in isolation)
///
/// None of these test methods are written by hand. They are produced by
/// the extension-role macro expansion on compilation, and Swift Testing
/// picks them up as ordinary `@Test` declarations.
@Suite("Idempotency contract checks")
@IdempotencyTests
struct IdempotencyContract {

    @Idempotent
    func systemStatusIsHealthy() -> String {
        PricingCalculator.systemStatus()
    }

    @Idempotent
    func pricingForFiveKilos() -> Int {
        PricingCalculator.priceInCents(kilograms: 5, ratePerKgCents: 250)
    }

    /// Async target — exercises the effect-matrix branch that emits
    /// `await` on both the outer helper call and the inner invocation.
    @Idempotent
    // swiftlint:disable:next async_without_await - exercises the async branch of @IdempotencyTests' expansion
    func asyncStatusProbe() async -> String {
        PricingCalculator.systemStatus()
    }
}

// MARK: - Members deliberately skipped by the macro (documented)
//
// `@IdempotencyTests` only picks up `@Idempotent`-marked **zero-argument**
// functions. The exclusions are part of the macro's contract and are
// worth seeing in consumer context. Uncomment the block below to confirm
// the macro ignores parameterised and un-marked members — the package
// still compiles and the generated extension contains no extra tests for
// these shapes.
//
//     extension IdempotencyContract {
//         @Idempotent
//         func parameterisedIsSkipped(_ kilograms: Int) -> Int {
//             PricingCalculator.priceInCents(kilograms: kilograms, ratePerKgCents: 250)
//         }
//
//         func unmarkedIsSkipped() -> String {
//             PricingCalculator.systemStatus()
//         }
//     }
//
// Uncommenting this extension doesn't add new generated tests. The macro
// sees the two members but filters them: the first has parameters
// (the macro can't synthesise arguments); the second lacks `@Idempotent`.
