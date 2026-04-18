/// Placeholder so the target has at least one source file in Phase 1.
/// Phase 4 (`#assertIdempotent` expression macro) replaces this with the
/// `IdempotencyAssertion` runtime helper that runs a closure twice and
/// compares results.
internal enum SwiftIdempotencyTestSupportPlaceholder {}
