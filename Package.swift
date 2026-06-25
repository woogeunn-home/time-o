// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TimeO",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TimeO", targets: ["TimeO"])
    ],
    targets: [
        .executableTarget(name: "TimeO"),
        .testTarget(name: "TimeOTests", dependencies: ["TimeO"])
    ]
)
