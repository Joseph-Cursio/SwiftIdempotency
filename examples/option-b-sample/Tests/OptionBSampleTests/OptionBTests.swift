import Testing
import SwiftIdempotency
import SwiftIdempotencyTestSupport
@testable import OptionBSample

/// End-to-end consumer validation of the Option B surface
/// (`IdempotentEffectRecorder` + `assertIdempotentEffects`) shipped in
/// v0.3.0. Mirrors the in-package unit tests, but from the perspective
/// of a downstream SPM package pulling SwiftIdempotency via a path
/// dependency.
@Suite("Option B — consumer sample")
struct OptionBSampleTests {

    // MARK: - Mocks

    /// Count-only recorder. Conforms to `IdempotentEffectRecorder`
    /// without declaring a `Snapshot` typealias, so `Snapshot` defaults
    /// to `Int` and `snapshot()` is provided by the where-clause
    /// extension.
    final class MockOrderRepository: OrderRepository, IdempotentEffectRecorder, @unchecked Sendable {
        private(set) var effectCount = 0
        private(set) var inserted: [Order] = []

        func insert(_ order: Order) async throws {
            inserted.append(order)
            effectCount += 1
        }
    }

    /// In-memory dedup store. Not instrumented for effect recording —
    /// marking an ID as handled is itself a side effect, but the point
    /// of Option B is observing effects the **production system**
    /// cares about (DB writes, emails, queue publishes), and a dedup
    /// store's writes are a self-accounting part of the idempotency
    /// mechanism, not a business effect.
    actor InMemoryOrderDedupStore: OrderDedupStore {
        private var handled: Set<String> = []

        func hasHandled(orderID: String) -> Bool {
            handled.contains(orderID)
        }

        func markHandled(orderID: String) {
            handled.insert(orderID)
        }
    }

    // MARK: - Happy path: dedup-guarded handler is idempotent

    @Test("Dedup-guarded handler: second invocation is a no-op")
    func dedupGuardedHandler_secondInvocationIsNoOp() async throws {
        let repo = MockOrderRepository()
        let dedup = InMemoryOrderDedupStore()
        let handler = OrderCreatedHandler(repo: repo, dedup: dedup)
        let order = Order(id: "ord_1", totalCents: 2_500)

        try await assertIdempotentEffects(recorders: [repo]) {
            _ = try await handler.handle(order)
        }

        // First invocation inserted; second was gated out. effectCount
        // stays at 1 — the assertion passed because post-first and
        // post-second snapshots both equal 1.
        #expect(repo.effectCount == 1)
        #expect(repo.inserted == [order])
    }

    // MARK: - Negative path: undgated handler is caught via .issueRecord

    @Test("Ungated handler: .issueRecord reports without aborting")
    func buggyHandler_issueRecordModeReportsAndContinues() async throws {
        let repo = MockOrderRepository()
        let handler = BuggyOrderHandler(repo: repo)
        let order = Order(id: "ord_2", totalCents: 4_200)

        await withKnownIssue {
            try await assertIdempotentEffects(
                recorders: [repo],
                failureMode: .issueRecord
            ) {
                _ = try await handler.handle(order)
            }
        }

        // Both invocations ran (Issue.record doesn't abort) so repo
        // has two inserts of the same order — the bug Option B is for.
        // #assertIdempotent on this handler would silently pass (both
        // calls returned `true`), which is why Option B exists.
        #expect(repo.effectCount == 2)
        #expect(repo.inserted == [order, order])
    }

    // MARK: - Custom Snapshot: ordered call log

    /// Opts into a richer `Snapshot` type — an ordered list of insert
    /// descriptions. Detects non-idempotency invisible to `effectCount`
    /// alone (e.g. retries that re-order operations with the same
    /// total count).
    final class CallLogOrderRepository: OrderRepository, IdempotentEffectRecorder, @unchecked Sendable {
        typealias Snapshot = [String]

        private(set) var insertedOrders: [String] = []
        var effectCount: Int { insertedOrders.count }

        func insert(_ order: Order) async throws {
            insertedOrders.append("\(order.id)@\(order.totalCents)")
        }

        func snapshot() -> [String] { insertedOrders }
    }

    @Test("Custom Snapshot ([String]): dedup-guarded handler still passes")
    func customSnapshotRecorder_dedupGuardedHandler_passes() async throws {
        let repo = CallLogOrderRepository()
        let dedup = InMemoryOrderDedupStore()
        let handler = OrderCreatedHandler(repo: repo, dedup: dedup)
        let order = Order(id: "ord_3", totalCents: 1_000)

        try await assertIdempotentEffects(recorders: [repo]) {
            _ = try await handler.handle(order)
        }

        #expect(repo.insertedOrders == ["ord_3@1000"])
    }
}
