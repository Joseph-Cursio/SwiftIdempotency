import SwiftSyntax
import SwiftSyntaxMacros

/// Peer macros that emit no declarations — pure annotation markers whose
/// only job is to exist as a recognisable attribute name for the linter
/// and `@IdempotencyTests`. Each marker stays a distinct type because the
/// compiler plugin registers macros by concrete type, but the empty
/// `expansion` body is shared here rather than triplicated.
public protocol EmptyPeerMacro: PeerMacro {}

public extension EmptyPeerMacro {
    /// Expands to no peer declarations: the attribute is only a marker.
    static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
