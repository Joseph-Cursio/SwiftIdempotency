// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FluentSample",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "FluentSample",
            targets: ["FluentSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/fluent-kit", from: "1.48.0"),
    ],
    targets: [
        .target(
            name: "FluentSample",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
                .product(name: "SwiftIdempotencyFluent", package: "SwiftIdempotency"),
                .product(name: "FluentKit", package: "fluent-kit"),
            ]
        ),
        .testTarget(
            name: "FluentSampleTests",
            dependencies: [
                "FluentSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
                .product(name: "SwiftIdempotencyFluent", package: "SwiftIdempotency"),
                .product(name: "FluentKit", package: "fluent-kit"),
            ]
        ),
    ]
)
