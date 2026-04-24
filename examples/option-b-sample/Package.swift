// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "OptionBSample",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "OptionBSample",
            targets: ["OptionBSample"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "OptionBSample",
            dependencies: [
                /// Handlers conform to `IdempotentEffectRecorder` (protocol
                /// lives in main `SwiftIdempotency` target since v0.3.0) —
                /// production code can adopt without pulling in TestSupport.
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
            ]
        ),
        .testTarget(
            name: "OptionBSampleTests",
            dependencies: [
                "OptionBSample",
                .product(name: "SwiftIdempotency", package: "SwiftIdempotency"),
                /// `assertIdempotentEffects` lives in TestSupport — it imports
                /// `Testing` for the `.issueRecord` failure mode.
                .product(name: "SwiftIdempotencyTestSupport", package: "SwiftIdempotency"),
            ]
        ),
    ]
)
