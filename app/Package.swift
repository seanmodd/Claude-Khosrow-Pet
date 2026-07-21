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
                .copy("Resources/faravahar-menubar.png"),
                // Hand-drawn per-state frame sequences (transparent 192×208),
                // shown instead of a sheet clip for these moods. See
                // PetController.customAnims / KhosrowResources.customFrameURLs.
                .copy("Resources/khosrow-sleeping-1.png"),
                .copy("Resources/khosrow-sleeping-2.png"),
                .copy("Resources/khosrow-sleeping-3.png"),
                .copy("Resources/khosrow-sleeping-4.png"),
                .copy("Resources/khosrow-sleeping-5.png"),
                .copy("Resources/khosrow-sleeping-6.png"),
                .copy("Resources/khosrow-reading-1.png"),
                .copy("Resources/khosrow-reading-2.png"),
                .copy("Resources/khosrow-reading-3.png"),
                .copy("Resources/khosrow-reading-4.png"),
                .copy("Resources/khosrow-reading-5.png"),
                .copy("Resources/khosrow-reading-6.png"),
                .copy("Resources/khosrow-success-1.png"),
                .copy("Resources/khosrow-success-2.png"),
                .copy("Resources/khosrow-success-3.png"),
                .copy("Resources/khosrow-success-4.png"),
                .copy("Resources/khosrow-success-5.png"),
                // Gemini-generated animation frame sequences (magenta-keyed
                // grids processed by scripts/make_frames_from_sheet.py).
                .copy("Resources/khosrow-writing-1.png"),
                .copy("Resources/khosrow-writing-2.png"),
                .copy("Resources/khosrow-writing-3.png"),
                .copy("Resources/khosrow-writing-4.png"),
                .copy("Resources/khosrow-writing-5.png"),
                .copy("Resources/khosrow-writing-6.png"),
                .copy("Resources/khosrow-runningCommand-1.png"),
                .copy("Resources/khosrow-runningCommand-2.png"),
                .copy("Resources/khosrow-runningCommand-3.png"),
                .copy("Resources/khosrow-runningCommand-4.png"),
                .copy("Resources/khosrow-runningCommand-5.png"),
                .copy("Resources/khosrow-runningCommand-6.png"),
                .copy("Resources/khosrow-runningCommand-7.png"),
                .copy("Resources/khosrow-attentive-1.png"),
                .copy("Resources/khosrow-attentive-2.png"),
                .copy("Resources/khosrow-attentive-3.png"),
                .copy("Resources/khosrow-attentive-4.png"),
                .copy("Resources/khosrow-attentive-5.png"),
                .copy("Resources/khosrow-attentive-6.png"),
                .copy("Resources/khosrow-waitingForPermission-1.png"),
                .copy("Resources/khosrow-waitingForPermission-2.png"),
                .copy("Resources/khosrow-waitingForPermission-3.png"),
                .copy("Resources/khosrow-waitingForPermission-4.png"),
                .copy("Resources/khosrow-waitingForPermission-5.png"),
                .copy("Resources/khosrow-waitingForPermission-6.png"),
                .copy("Resources/khosrow-searching-1.png"),
                .copy("Resources/khosrow-searching-2.png"),
                .copy("Resources/khosrow-searching-3.png"),
                .copy("Resources/khosrow-searching-4.png"),
                .copy("Resources/khosrow-searching-5.png"),
                .copy("Resources/khosrow-searching-6.png"),
                .copy("Resources/khosrow-praying-1.png"),
                .copy("Resources/khosrow-praying-2.png"),
                .copy("Resources/khosrow-praying-3.png"),
                .copy("Resources/khosrow-praying-4.png"),
                .copy("Resources/khosrow-praying-5.png"),
                .copy("Resources/khosrow-praying-6.png"),
                // Gemini illustrated single-image "visual acts" (transparent
                // cut-outs of one pose each), imported by
                // scripts/import_gemini_acts.py and shown for their mood.
                .copy("Resources/gemini-attentive.png"),
                .copy("Resources/gemini-searching.png"),
                .copy("Resources/gemini-waiting.png"),
                .copy("Resources/gemini-writing.png"),
                .copy("Resources/gemini-running.png"),
                .copy("Resources/gemini-praying.png"),
                .copy("Resources/watch_claude.py"),
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
