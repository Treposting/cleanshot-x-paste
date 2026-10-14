// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShotPaste",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ShotPaste",
            path: "Sources/ShotPaste"
        )
    ]
)
