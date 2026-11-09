// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PuttCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "PuttCore", targets: ["PuttCore"])
    ],
    targets: [
        .target(name: "PuttCore"),
        .testTarget(name: "PuttCoreTests", dependencies: ["PuttCore"])
    ]
)
