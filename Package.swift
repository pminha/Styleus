// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Styleus",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "StyleusCore", targets: ["StyleusCore"])],
    targets: [
        .target(name: "StyleusCore", path: "Shared"),
        .testTarget(name: "StyleusCoreTests", dependencies: ["StyleusCore"], path: "Tests")
    ]
)
