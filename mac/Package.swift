// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CivCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CivCoach", targets: ["CivCoach"])
    ],
    targets: [
        .executableTarget(
            name: "CivCoach",
            path: "CivCoach",
            exclude: ["Resources"]
        )
    ]
)
