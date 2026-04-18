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
    ],
    dependencies: [
        // Pinned to match SwiftProjectLint's swift-syntax version so attribute-
        // parsing work stays cross-package-compatible. 602.0.0 targets Swift
        // 6.x; the macros plugin is loaded by the user's toolchain, so this
        // pin is effectively a compile-time dependency rather than a runtime
        // version gate.
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "602.0.0"),
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
        .testTarget(
            name: "SwiftIdempotencyTests",
            dependencies: [
                "SwiftIdempotency",
                "SwiftIdempotencyMacros",
                "SwiftIdempotencyTestSupport",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
