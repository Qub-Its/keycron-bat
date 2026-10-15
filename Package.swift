// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KeycronBat",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KeycronBatCore"),
        .testTarget(name: "KeycronBatCoreTests", dependencies: ["KeycronBatCore"]),
    ]
)
