// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PaneCue",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PaneCue", targets: ["PaneCue"])
    ],
    targets: [
        .target(
            name: "PaneCueCore"
        ),
        .executableTarget(
            name: "PaneCue",
            dependencies: ["PaneCueCore"]
        ),
        .testTarget(
            name: "PaneCueCoreTests",
            dependencies: ["PaneCueCore"]
        )
    ]
)
