// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AssertIdempotentSample",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "AssertIdempotentSample",
            targets: ["AssertIdempotentSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "AssertIdempotentSample",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "AssertIdempotentSampleTests",
            dependencies: [
                "AssertIdempotentSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
