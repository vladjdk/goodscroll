// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GoodScroll",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GoodScrollCore"),
        .executableTarget(name: "GoodScroll", dependencies: ["GoodScrollCore"]),
        .testTarget(name: "GoodScrollCoreTests", dependencies: ["GoodScrollCore"]),
    ]
)
