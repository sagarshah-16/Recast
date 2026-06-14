// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Recast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Recast",
            path: "Sources/Recast"
        ),
    ]
)
