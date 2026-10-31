// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GuanXingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GuanXingCore", targets: ["GuanXingCore"])
    ],
    targets: [
        .target(name: "GuanXingCore"),
        .testTarget(name: "GuanXingCoreTests", dependencies: ["GuanXingCore"])
    ]
)
