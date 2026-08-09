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
        ),
        .executable(
            name: "PaneCueDialogueBenchmark",
            targets: ["PaneCueDialogueBenchmark"]
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
        .target(
            name: "PaneCueBenchmarkKit",
            dependencies: ["PaneCueCore"]
        ),
        .executableTarget(
            name: "PaneCueDialogueBenchmark",
            dependencies: ["PaneCueBenchmarkKit"]
        ),
        .testTarget(
            name: "PaneCueCoreTests",
            dependencies: ["PaneCueCore"]
        ),
        .testTarget(
            name: "PaneCueTargetStructureTests",
            dependencies: [
                "PaneCueApp",
                "PaneCueBenchmarkKit",
                "PaneCueExperimentalFeatures"
            ]
        )
    ]
)
