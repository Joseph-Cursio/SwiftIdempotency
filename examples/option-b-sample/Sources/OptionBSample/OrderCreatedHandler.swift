import SwiftIdempotency

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A handler with a **trivial return type** (`Bool`) that makes
/// return-equality checks (`#assertIdempotent` / Option C) silent on
/// the non-idempotent path. Both invocations return `true`; the only
/// way to see the bug is to observe the side effects.
///
/// Option B (`IdempotentEffectRecorder` + `assertIdempotentEffects`)
/// is the right tool for this shape.
public struct OrderCreatedHandler: Sendable {
    private let repo: any OrderRepository
    private let dedup: any OrderDedupStore

    public init(repo: any OrderRepository, dedup: any OrderDedupStore) {
        self.repo = repo
        self.dedup = dedup
    }

    /// Persists an order and marks it as handled. Returns `true` when a
    /// persist actually happened, `false` when the dedup gate skipped
    /// it. The **dedup gate is what makes this idempotent** — remove it
    /// and you get duplicate rows on retry.
    public func handle(_ order: Order) async throws -> Bool {
        if await dedup.hasHandled(orderID: order.id) {
            return false
        }
        try await repo.insert(order)
        await dedup.markHandled(orderID: order.id)
        return true
    }
}

/// A deliberately broken variant — no dedup gate. Every invocation
/// writes. Ships with the sample purely so the test suite can
/// demonstrate what `assertIdempotentEffects` catches that
/// `#assertIdempotent` misses.
public struct BuggyOrderHandler: Sendable {
    private let repo: any OrderRepository

    public init(repo: any OrderRepository) {
        self.repo = repo
    }

    public func handle(_ order: Order) async throws -> Bool {
        try await repo.insert(order)
        return true
    }
}

// MARK: - Domain

public struct Order: Sendable, Equatable {
    public let id: String
    public let totalCents: Int

    public init(id: String, totalCents: Int) {
        self.id = id
        self.totalCents = totalCents
    }
}

// MARK: - Protocols

/// Abstract the persistence boundary so tests can inject a mock that
/// also conforms to `IdempotentEffectRecorder`.
public protocol OrderRepository: Sendable {
    func insert(_ order: Order) async throws
}

/// Abstract the dedup boundary. Production might back this with Redis,
/// a DynamoDB conditional put, or a `UNIQUE` constraint; tests use an
/// in-memory set.
public protocol OrderDedupStore: Sendable {
    func hasHandled(orderID: String) async -> Bool
    func markHandled(orderID: String) async
}
