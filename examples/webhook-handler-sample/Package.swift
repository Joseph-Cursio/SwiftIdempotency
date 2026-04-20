// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WebhookHandlerSample",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "WebhookHandlerSample",
            targets: ["WebhookHandlerSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "WebhookHandlerSample",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "WebhookHandlerSampleTests",
            dependencies: ["WebhookHandlerSample"]
        ),
    ]
)
