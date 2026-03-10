// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoopSnap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LoopSnap",
            path: "Sources/LoopSnap",
            resources: [.process("Resources")]
        )
    ]
)
