// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DigiWalkerCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "DigiWalkerCore", targets: ["DigiWalkerCore"]),
    ],
    targets: [
        .target(name: "DigiWalkerCore"),
        .testTarget(name: "DigiWalkerCoreTests", dependencies: ["DigiWalkerCore"]),
    ]
)
