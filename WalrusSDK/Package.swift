// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WalrusSDK",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WalrusSDK",
            targets: ["WalrusSDK"]
        )
    ],
    targets: [
        .target(
            name: "WalrusSDK",
            path: "WalrusSDK"  // Points directly to your WalrusSDK folder
        ),
        .testTarget(
            name: "WalrusSDKTests",
            dependencies: ["WalrusSDK"],
            path: "WalrusSDKTests"  // Points directly to your WalrusSDKTests folder
        )
    ]
)