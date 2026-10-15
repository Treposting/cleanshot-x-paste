// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marquee",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Marquee",
            path: "Sources/Marquee"
        ),
        .testTarget(
            name: "MarqueeTests",
            dependencies: ["Marquee"],
            path: "Tests/MarqueeTests"
        ),
    ]
)
