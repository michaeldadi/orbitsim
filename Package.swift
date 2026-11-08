// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrbitSim",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "OrbitSimCore", targets: ["OrbitSimCore"]),
        .library(name: "OrbitSimUpdater", targets: ["OrbitSimUpdater"]),
        .executable(name: "orbitsim", targets: ["OrbitSimCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "OrbitSimCore"),
        .target(name: "OrbitSimUpdater", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .executableTarget(name: "OrbitSimCLI", dependencies: ["OrbitSimCore"]),
        .testTarget(name: "OrbitSimCoreTests", dependencies: ["OrbitSimCore"]),
    ]
)
