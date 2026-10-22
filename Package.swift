// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroTab",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "AeroTab", targets: ["AeroTab"])],
    targets: [
        .target(name: "AeroTabCore"),
        .executableTarget(name: "AeroTab", dependencies: ["AeroTabCore"]),
        .testTarget(name: "AeroTabCoreTests", dependencies: ["AeroTabCore"])
    ]
)
