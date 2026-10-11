// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenItRecorder",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ScreenItRecorder", path: "Sources/ScreenItRecorder")
    ],
    swiftLanguageModes: [.v5]
)
