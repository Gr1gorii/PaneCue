// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PaneCue",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PaneCue", targets: ["PaneCue"]),
        .executable(
            name: "PaneCueExperimental",
            targets: ["PaneCueExperimental"]
        )
    ],
    targets: [
        .target(
            name: "PaneCueCore"
        ),
        .target(
            name: "PaneCueApp",
            dependencies: ["PaneCueCore"]
        ),
        .executableTarget(
            name: "PaneCue",
            dependencies: ["PaneCueApp"]
        ),
        .target(
            name: "PaneCueExperimentalFeatures",
            dependencies: ["PaneCueCore", "PaneCueApp"]
        ),
        .executableTarget(
            name: "PaneCueExperimental",
            dependencies: [
                "PaneCueApp",
                "PaneCueExperimentalFeatures"
            ]
        ),
        .testTarget(
            name: "PaneCueCoreTests",
            dependencies: ["PaneCueCore"]
        ),
        .testTarget(
            name: "PaneCueTargetStructureTests",
            dependencies: [
                "PaneCueApp",
                "PaneCueExperimentalFeatures"
            ]
        )
    ]
)
