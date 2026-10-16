// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitGlaze",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GitGlaze", targets: ["GitGlaze"])],
    targets: [
        .target(name: "GitGlazeCore"),
        .executableTarget(name: "GitGlaze", dependencies: ["GitGlazeCore"]),
        .testTarget(name: "GitGlazeCoreTests", dependencies: ["GitGlazeCore"])
    ]
)
