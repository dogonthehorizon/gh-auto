// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gh-auto",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GhAuto",
            path: "Sources/GhAuto",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))]
        )
    ]
)
