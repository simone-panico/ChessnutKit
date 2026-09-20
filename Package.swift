// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ChessnutKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "ChessnutKit",
            targets: ["ChessnutKit"]
        ),
    ],
    targets: [
        .target(
            name: "ChessnutKit",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),

    ]
)
