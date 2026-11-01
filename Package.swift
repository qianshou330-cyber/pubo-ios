// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PUBOCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PUBOCore", targets: ["PUBOCore"])],
    targets: [
        .target(name: "PUBOCore"),
        .testTarget(name: "PUBOCoreTests", dependencies: ["PUBOCore"])
    ]
)
