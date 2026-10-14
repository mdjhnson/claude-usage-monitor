// swift-tools-version:6.0
// PaceBar has zero third-party dependencies. Keep it that way.
import PackageDescription

let package = Package(
    name: "PaceBar",
    platforms: [.macOS(.v14)],
    // The app and its widget build from PaceBar.xcodeproj (see project.yml). This package
    // builds the same PaceBarCore sources for `swift test`.
    targets: [
        // Pure logic and the two I/O services. Foundation + Security only, no AppKit.
        .target(name: "PaceBarCore", path: "Sources/PaceBarCore"),
        .testTarget(
            name: "PaceBarCoreTests",
            dependencies: ["PaceBarCore"],
            path: "Tests/PaceBarCoreTests"
        ),
    ]
)
