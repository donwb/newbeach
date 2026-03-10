// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BeachStatus",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BeachStatus", targets: ["BeachStatus"]),
    ],
    targets: [
        .target(name: "BeachStatus"),
    ]
)
