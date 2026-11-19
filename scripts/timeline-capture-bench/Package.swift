// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TimelineCaptureBenchmark",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "PUBOCore", path: "../..")],
    targets: [.executableTarget(name: "CaptureBench", dependencies: [.product(name: "PUBOCore", package: "PUBOCore")])]
)
