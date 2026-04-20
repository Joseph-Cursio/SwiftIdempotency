import Foundation
import SwiftIdempotency

/// A Stripe-style payment-intent webhook event.
///
/// Identifiable by a stable event id that Stripe redelivers verbatim on
/// every retry. That stability is exactly what `IdempotencyKey` needs: a
/// caller deriving the key from `event.id` is guaranteed retry-safe by
/// construction.
public struct PaymentIntent: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let amountMinorUnits: Int
    public let currency: String

    public init(id: String, amountMinorUnits: Int, currency: String) {
        self.id = id
        self.amountMinorUnits = amountMinorUnits
        self.currency = currency
    }
}

/// The downstream action the webhook dispatches.
///
/// Carrying `IdempotencyKey` in the type signature — rather than a bare
/// `String` — makes the stability guarantee enforceable at the call site.
/// Callers cannot construct a `ChargeRequest` with a per-invocation value
/// without going through one of `IdempotencyKey`'s documented labelled
/// initialisers.
public struct ChargeRequest: Sendable, Equatable {
    public let amountMinorUnits: Int
    public let currency: String
    public let idempotencyKey: IdempotencyKey

    public init(
        amountMinorUnits: Int,
        currency: String,
        idempotencyKey: IdempotencyKey
    ) {
        self.amountMinorUnits = amountMinorUnits
        self.currency = currency
        self.idempotencyKey = idempotencyKey
    }
}

/// Translate a payment-intent webhook into a downstream charge request.
///
/// The handler is intentionally pure — it builds a value-typed
/// `ChargeRequest` and stops. Production code would hand that request to
/// a Stripe client; the sample omits the network leg so the tests can
/// assert shape without side effects.
public enum StripeWebhookHandler {
    public static func makeChargeRequest(for event: PaymentIntent) -> ChargeRequest {
        ChargeRequest(
            amountMinorUnits: event.amountMinorUnits,
            currency: event.currency,
            idempotencyKey: IdempotencyKey(fromEntity: event)
        )
    }
}
