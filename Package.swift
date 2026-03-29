// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TrackerAIMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "TrackerAIMac",
            targets: ["TrackerAIMac"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "TrackerAIMac",
            path: "Sources/TrackerAIMac"
        ),
    ]
)
