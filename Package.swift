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
        // The asset catalog holds the app icon, which only a bundled build can show.
        .executableTarget(name: "Posteight", exclude: ["Assets.xcassets"]),
        .testTarget(name: "PosteightTests", dependencies: ["Posteight"])
    ]
)
