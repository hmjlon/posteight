// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Posteight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Posteight", targets: ["Posteight"])
    ],
    targets: [
        .executableTarget(name: "Posteight"),
        .testTarget(name: "PosteightTests", dependencies: ["Posteight"])
    ]
)
