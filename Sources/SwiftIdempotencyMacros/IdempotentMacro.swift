import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Idempotent` — marker-only since the round-8 peer-macro redesign.
///
/// Primary value is existing as a recognisable attribute name that both
/// the linter (`SwiftProjectLint`'s `EffectAnnotationParser`) and
/// `@IdempotencyTests` (this package's member-scanning macro) can detect.
/// Emits no peer declarations of its own.
///
/// ## Why marker-only
///
/// The original Phase 3 design had `@Idempotent` peer-emit a
/// `@Test func testIdempotencyOf<Name>()`. Round-7 validation (see
/// `docs/phase5-round-7/trial-findings.md`, Finding 4) surfaced that
/// Swift Testing's `@Test` macro interacts poorly with any outer macro
/// that emits it at peer or member scope inside a struct — the nested
/// expansion produces `@used`/`@section` properties referencing `self`
/// during property initialisation, which the compiler rejects.
///
/// Round 8 (`docs/claude_phase_5_peer_macro_redesign_plan.md`) spiked
/// three candidate redesigns. Candidate B — an `@attached(extension)`
/// role on a separate `@IdempotencyTests` attribute attached to the
/// `@Suite` type — turned out to sidestep Finding 4 because the emitted
/// `@Test`s live in a fresh extension decl, outside the original
/// struct's member layout. That shape landed; `@Idempotent` reverted
/// to marker-only.
///
/// ## Usage
///
/// ```swift
/// @Suite
/// @IdempotencyTests
/// struct Checks {
///     @Idempotent
///     func currentSystemStatus() -> Int { 200 }
/// }
/// ```
///
/// `@IdempotencyTests` scans the struct's members, finds `@Idempotent`-
/// marked zero-argument functions, and emits a `@Test` per match inside
/// an extension of the struct.
public struct IdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker implementation — see `IdempotentMacro`.
public struct NonIdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker implementation — see `IdempotentMacro`.
public struct ObservationalMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

/// Marker implementation — see `IdempotentMacro`. Parameter validation
/// (verifying the named key parameter exists on the annotated function) is
/// deferred to a future phase; Phase 1 accepts any string value and relies
/// on the linter's existing `missingIdempotencyKey` rule for verification.
public struct ExternallyIdempotentMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct SwiftIdempotencyMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        IdempotentMacro.self,
        NonIdempotentMacro.self,
        ObservationalMacro.self,
        ExternallyIdempotentMacro.self,
        AssertIdempotentMacro.self,
        AssertIdempotentAsyncMacro.self,
        IdempotencyTestsMacro.self
    ]
}
