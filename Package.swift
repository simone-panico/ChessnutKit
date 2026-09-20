// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "ChessnutKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ChessnutProtocol", targets: ["ChessnutProtocol"]),
        .library(name: "ChessnutKit", targets: ["ChessnutKit"]),
    ],
    targets: [
        .target(name: "ChessnutProtocol"),
        .target(name: "ChessnutKit", dependencies: ["ChessnutProtocol"]),
    ]
)
