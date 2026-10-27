// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LocalFlow", targets: ["LocalFlow"]),
        .library(name: "LocalFlowCore", targets: ["LocalFlowCore"])
    ],
    targets: [
        .target(
            name: "LocalFlowCore",
            path: "Sources/LocalFlowCore"
        ),
        .executableTarget(
            name: "LocalFlow",
            dependencies: ["LocalFlowCore"],
            path: "Sources/LocalFlow"
        ),
        .testTarget(
            name: "LocalFlowTests",
            dependencies: ["LocalFlowCore"],
            path: "Tests/LocalFlowTests"
        )
    ]
)
