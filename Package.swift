// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TheConductor",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ConductorCore",
            targets: ["ConductorCore"]
        ),
        .executable(
            name: "TheConductorApp",
            targets: ["TheConductorApp"]
        ),
    ],
    targets: [
        .target(
            name: "ConductorCore"
        ),
        .executableTarget(
            name: "TheConductorApp",
            dependencies: ["ConductorCore"]
        ),
        .testTarget(
            name: "ConductorCoreTests",
            dependencies: ["ConductorCore"]
        ),
    ]
)
