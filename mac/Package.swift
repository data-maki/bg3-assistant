// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BG3HonorAssistant",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BG3HonorAssistant", targets: ["BG3HonorAssistant"])
    ],
    targets: [
        .executableTarget(
            name: "BG3HonorAssistant",
            path: "BG3Assistant",
            exclude: ["Resources"]
        )
    ]
)
