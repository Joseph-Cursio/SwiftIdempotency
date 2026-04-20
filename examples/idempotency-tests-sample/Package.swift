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
        .target(
            name: "IdempotencyTestsSample",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "IdempotencyTestsSampleTests",
            dependencies: [
                "IdempotencyTestsSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
