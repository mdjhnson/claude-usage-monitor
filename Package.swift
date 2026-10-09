// swift-tools-version:6.0
// PaceBar has zero third-party dependencies. Keep it that way.
import PackageDescription

let package = Package(
    name: "PaceBar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic and the two I/O services. Foundation + Security only, no AppKit.
        .target(name: "PaceBarCore", path: "Sources/PaceBarCore"),
        // The menu bar app: AppKit + SwiftUI. build.sh wraps it into PaceBar.app.
        .executableTarget(
            name: "PaceBar",
            dependencies: ["PaceBarCore"],
            path: "Sources/PaceBar"
        ),
        .testTarget(
            name: "PaceBarCoreTests",
            dependencies: ["PaceBarCore"],
            path: "Tests/PaceBarCoreTests"
        ),
    ]
)
