// swift-tools-version: 6.0
import PackageDescription

// macOS-only developer tool. It reads DIM card images (BIN) and writes sprite sheets into PrivateAssets/dim.
// Card/slot/frame-spec data comes from DigiWalkerCore so the mapping has one source of truth.
let package = Package(
    name: "dim-extract",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "dim-extract", targets: ["dim-extract"]),
    ],
    dependencies: [
        .package(path: "../../Packages/DigiWalkerCore"),
    ],
    targets: [
        .target(name: "DIMCardFormat", dependencies: [.product(name: "DigiWalkerCore", package: "DigiWalkerCore")]),
        .executableTarget(name: "dim-extract", dependencies: ["DIMCardFormat"]),
        .testTarget(name: "DIMCardFormatTests", dependencies: ["DIMCardFormat"]),
    ]
)
