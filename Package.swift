// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenToGif",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ScreenToGif",
            path: "Sources/ScreenToGif",
            resources: [.process("Resources")]
        )
    ]
)
