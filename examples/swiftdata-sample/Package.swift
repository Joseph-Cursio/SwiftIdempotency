// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SwiftDataSample",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "SwiftDataSample",
            targets: ["SwiftDataSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "SwiftDataSample",
            dependencies: [
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "SwiftDataSampleTests",
            dependencies: [
                "SwiftDataSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
