// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dustpan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "dustpan", targets: ["DustpanCLI"]),
        .executable(name: "DustpanApp", targets: ["DustpanApp"]),
        .library(name: "DustpanCore", targets: ["DustpanCore"]),
    ],
    targets: [
        .target(name: "DustpanCore"),
        .executableTarget(name: "DustpanCLI", dependencies: ["DustpanCore"]),
        .executableTarget(name: "DustpanApp", dependencies: ["DustpanCore"]),
        .testTarget(name: "DustpanCoreTests", dependencies: ["DustpanCore"]),
    ]
)
