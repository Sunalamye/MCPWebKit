// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MCPWebKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "MCPWebKit",
            targets: ["MCPWebKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Sunalamye/MCPKit.git", from: "0.2.0"),
        .package(url: "https://github.com/Sunalamye/WebViewBridge.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "MCPWebKit",
            dependencies: ["MCPKit", "WebViewBridge"]),
        .testTarget(
            name: "MCPWebKitTests",
            dependencies: ["MCPWebKit"]),
    ]
)
