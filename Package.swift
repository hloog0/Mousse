// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SmoothWheel",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic (easing + event classification/synthesis): testable without permissions.
        .target(name: "SmoothWheelCore"),
        // The menu bar app. Swift 5 mode keeps the C event-tap callback and AppKit glue simple.
        .executableTarget(
            name: "SmoothWheel",
            dependencies: ["SmoothWheelCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SmoothWheelCoreTests", dependencies: ["SmoothWheelCore"]),
    ]
)
