// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WalrusSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "WalrusSDK",
            targets: ["WalrusSDK"]),
    ],
    targets: [
        .target(
            name: "WalrusSDK",
            path: "WalrusSDK"  // Points to your source files
        ),
        .testTarget(
            name: "WalrusSDKTests",
            dependencies: ["WalrusSDK"],
            path: "Tests/WalrusSDKTests"
        ),
    ]
)
