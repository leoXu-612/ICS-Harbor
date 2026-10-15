// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Harbor", targets: ["Harbor"]), .library(name: "HarborCore", targets: ["HarborCore"])],
    targets: [
        .target(name: "HarborCore"),
        .executableTarget(name: "Harbor", dependencies: ["HarborCore"], resources: [.copy("Resources")]),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"])
    ]
)
