// swift-tools-version: 5.10

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftIdempotency",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        /// User-facing library. Import this for `@Idempotent`, `@NonIdempotent`,
        /// `@Observational`, `@ExternallyIdempotent` attributes and the
        /// `IdempotencyKey` strong type.
        .library(
            name: "SwiftIdempotency",
            targets: ["SwiftIdempotency"]
        ),
        /// Test-only helpers for `#assertIdempotent`. Add this to test targets
        /// that use the freestanding expression macro.
        .library(
            name: "SwiftIdempotencyTestSupport",
            targets: ["SwiftIdempotencyTestSupport"]
        ),
        /// Opt-in library for Fluent adopters. Provides
        /// `IdempotencyKey.init(fromFluentModel:)` for Fluent `Model` types
        /// whose `IDValue: CustomStringConvertible`, routing through
        /// FluentKit's own `requireID()` for a clean throw on pre-save id.
        /// Depending on this library pulls in `vapor/fluent-kit`; non-Fluent
        /// adopters should not add it.
        .library(
            name: "SwiftIdempotencyFluent",
            targets: ["SwiftIdempotencyFluent"]
        ),
    ],
    dependencies: [
        // Allow 602.x or 603.x — the macro APIs SwiftIdempotency uses
        // (SwiftSyntax node types, SwiftSyntaxMacros context, SwiftDiagnostics)
        // are stable across these minors. A previous `exact: "602.0.0"` pin
        // caused dep-graph friction on adopters who transitively required
        // 603 (surfaced by Penny's DiscordBM via `@UnstableEnum`, which
        // only expands correctly on swift-syntax 603+). Upper bound stays
        // exclusive of 604 until verified on that version.
        .package(url: "https://github.com/apple/swift-syntax.git", "602.0.0"..<"604.0.0"),
        // FluentKit is an optional dependency for the `SwiftIdempotencyFluent`
        // product. Only adopters that declare a dependency on
        // `SwiftIdempotencyFluent` pay the compile cost. `requireID()` and
        // the `Model.IDValue` associated type have been stable since Fluent 4,
        // so the conservative `from: "1.48.0"` floor is well ahead of the
        // API surface this integration uses.
        .package(url: "https://github.com/vapor/fluent-kit", from: "1.48.0"),
        // Test-only: property-based testing for `#assertIdempotent`. Scoped
        // to the SwiftIdempotencyTests target; adopters do not pull this in.
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
    ],
    targets: [
        /// Public API declarations. Contains the `@macro` declarations that
        /// point to the plugin's implementations, plus `IdempotencyKey`.
        /// Users import this and nothing else for the annotation + strong-
        /// typing surface.
        .target(
            name: "SwiftIdempotency",
            dependencies: ["SwiftIdempotencyMacros"]
        ),
        /// Compiler plugin that implements the macros. Users never import this
        /// directly; it's loaded by the Swift compiler when expanding `@Idempotent`
        /// et al.
        .macro(
            name: "SwiftIdempotencyMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        /// Runtime helpers for `#assertIdempotent`. Separate target so
        /// production code isn't forced to link test-only symbols.
        .target(
            name: "SwiftIdempotencyTestSupport",
            dependencies: ["SwiftIdempotency"]
        ),
        /// Fluent-specific integration. Adds a dedicated
        /// `IdempotencyKey.init(fromFluentModel:)` initializer for Fluent
        /// `Model` types, addressing the reachability gap surfaced by the
        /// hellovapor package-adoption trial (Fluent Models don't conform to
        /// `Identifiable`; their `@ID` is `UUID?`, blocking the generic
        /// `init(fromEntity:)` path). The constructor throws
        /// `FluentError.idRequired` via `model.requireID()` when the id is
        /// nil (pre-save state).
        .target(
            name: "SwiftIdempotencyFluent",
            dependencies: [
                "SwiftIdempotency",
                .product(name: "FluentKit", package: "fluent-kit"),
            ]
        ),
        .testTarget(
            name: "SwiftIdempotencyTests",
            dependencies: [
                "SwiftIdempotency",
                "SwiftIdempotencyMacros",
                "SwiftIdempotencyTestSupport",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "PropertyBased", package: "swift-property-based"),
            ]
        ),
        .testTarget(
            name: "SwiftIdempotencyFluentTests",
            dependencies: [
                "SwiftIdempotencyFluent",
                .product(name: "FluentKit", package: "fluent-kit"),
            ]
        ),
    ]
)
