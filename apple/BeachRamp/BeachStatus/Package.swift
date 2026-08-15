// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BeachStatus",
    platforms: [
        .iOS("18.0"),
        .watchOS("11.0"),
        .tvOS("18.0"),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BeachStatus", targets: ["BeachStatus"]),
    ],
    targets: [
        .target(name: "BeachStatus"),
        .testTarget(name: "BeachStatusTests", dependencies: ["BeachStatus"]),
    ]
)
