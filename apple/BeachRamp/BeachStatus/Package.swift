// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BeachStatus",
    platforms: [
        .iOS("18.0"),
        .watchOS("11.0"),
        .tvOS("18.0"),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BeachStatus", targets: ["BeachStatus"]),
    ],
    targets: [
        .target(
            name: "BeachStatus",
            resources: [
                .copy("Resources/Fonts")
            ]
        ),
        .testTarget(name: "BeachStatusTests", dependencies: ["BeachStatus"]),
    ]
)
