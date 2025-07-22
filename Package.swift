// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ImageKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ImageKit",
            targets: ["ImageKit"]),
        .library(
            name: "ImageKitExample",
            targets: ["ImageKitExample"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "ImageKit",
            dependencies: []),
        .target(
            name: "ImageKitExample",
            dependencies: ["ImageKit"]),
    ]
)
