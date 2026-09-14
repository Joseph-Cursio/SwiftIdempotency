// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "IdempotencyTestsSample",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "IdempotencyTestsSample",
            targets: ["IdempotencyTestsSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        // The sample's production code is plain Swift; only its test target uses the macros.
        .target(name: "IdempotencyTestsSample"),
        .testTarget(
            name: "IdempotencyTestsSampleTests",
            dependencies: [
                "IdempotencyTestsSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
