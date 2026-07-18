// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Khosrow",
    platforms: [
        // macOS 12 keeps WebP off the critical path (we ship a PNG runtime asset)
        // while still supporting borderless floating windows and NSStatusItem.
        .macOS(.v12)
    ],
    products: [
        .library(name: "KhosrowKit", targets: ["KhosrowKit"]),
        .executable(name: "KhosrowApp", targets: ["KhosrowApp"]),
    ],
    targets: [
        // Pure, portable logic. No AppKit — so tests run headless and fast.
        .target(
            name: "KhosrowKit",
            resources: [
                // .copy (not .process) so our pixel-exact PNG is never re-encoded.
                .copy("Resources/khosrow.runtime.json"),
                .copy("Resources/khosrow-spritesheet.png"),
            ]
        ),
        // AppKit UI. Compiled in CI; not run there (needs a real macOS session).
        .executableTarget(
            name: "KhosrowApp",
            dependencies: ["KhosrowKit"]
        ),
        .testTarget(
            name: "KhosrowKitTests",
            dependencies: ["KhosrowKit"]
        ),
    ]
)
