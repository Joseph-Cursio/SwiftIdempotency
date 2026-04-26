import Testing
import SwiftIdempotency

/// Runtime tests for `SwiftIdempotency.__idempotencyInvokeTwice` —
/// the helper the `@IdempotencyTests(for:)` macro expansion calls
/// from each generated `@Test` body.
///
/// `IdempotencyTestsMacroTests.swift` already verifies the expansion's
/// textual form. These tests cover the runtime contract:
/// invoke-twice, return both results, propagate throws, work for sync
/// + async + throwing + non-throwing closure shapes.
@Suite
struct IdempotencyInvokeTwiceRuntimeTests {

    @Test
    func sync_nonThrowing_invokesTwice_returnsBothResults() async throws {
        actor Counter {
            private(set) var calls = 0
            func bump() -> Int {
                calls += 1
                return 7
            }
        }
        let counter = Counter()
        let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
            await counter.bump()
        }
        #expect(first == 7)
        #expect(second == 7)
        let calls = await counter.calls
        #expect(calls == 2)
    }

    @Test
    func returnsTuple_evenWhenResultsDiffer() async throws {
        // The helper does not enforce equality — that's the macro
        // expansion's `#expect(__first == __second)` job. The helper
        // just returns both values; the caller decides.
        actor Sequence {
            private var next = 0
            func step() -> Int {
                let value = next
                next += 1
                return value
            }
        }
        let sequence = Sequence()
        let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
            await sequence.step()
        }
        #expect(first == 0)
        #expect(second == 1)
    }

    @Test
    func async_nonThrowing_invokesTwice() async throws {
        actor Counter {
            private(set) var calls = 0
            func bump() async -> String {
                calls += 1
                return "ok"
            }
        }
        let counter = Counter()
        let (first, second) = await SwiftIdempotency.__idempotencyInvokeTwice {
            await counter.bump()
        }
        #expect(first == "ok")
        #expect(second == "ok")
        let calls = await counter.calls
        #expect(calls == 2)
    }

    @Test
    func throwingOnFirstCall_propagates_secondNotInvoked() async {
        struct TestError: Error, Equatable {}
        actor Gate {
            private(set) var calls = 0
            func step() throws -> Int {
                calls += 1
                throw TestError()
            }
        }
        let gate = Gate()
        var caught = false
        do {
            _ = try await SwiftIdempotency.__idempotencyInvokeTwice {
                try await gate.step()
            }
        } catch is TestError {
            caught = true
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(caught)
        let calls = await gate.calls
        #expect(calls == 1, "second invocation must not run when first throws")
    }

    @Test
    func throwingOnSecondCall_propagates() async {
        struct TestError: Error, Equatable {}
        actor Gate {
            private var calls = 0
            func step() throws -> Int {
                calls += 1
                if calls == 2 { throw TestError() }
                return 0
            }
        }
        let gate = Gate()
        var caught = false
        do {
            _ = try await SwiftIdempotency.__idempotencyInvokeTwice {
                try await gate.step()
            }
        } catch is TestError {
            caught = true
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(caught)
    }
}
