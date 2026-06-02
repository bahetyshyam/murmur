// swift-tools-version: 5.9
import PackageDescription

// Structure: Murmur is a *library* holding all the app logic.
// MurmurApp is a tiny executable that owns main.swift + NSApplication
// bootstrap. Tests are a second executable (`swift run MurmurTests`)
// because Command Line Tools ships neither XCTest nor a working
// swift-testing cross-import overlay for Foundation.
let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Murmur", targets: ["MurmurApp"]),
    ],
    dependencies: [
        // Auto-update framework. Linked into the Murmur library; the
        // Sparkle.framework binary is copied into the .app bundle and
        // re-signed by scripts/build_release.sh (Xcode's "Embed Frameworks"
        // phase has no SPM/CLI equivalent).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Dependency-free design primitives (Ink palette, serif font helper,
        // hand-drawn arrow geometry). Pure AppKit/Foundation — NO Sparkle, no
        // SwiftUI — so the DMGAssets build-time tool can reuse the tokens
        // without dragging in the auto-update framework or app UI code.
        .target(
            name: "DesignSystemCore",
            path: "Sources/DesignSystemCore"
        ),
        .target(
            name: "Murmur",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "DesignSystemCore",
            ],
            path: "Sources/Murmur",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .executableTarget(
            name: "MurmurApp",
            dependencies: ["Murmur"],
            path: "Sources/MurmurApp",
            // Sparkle.framework lives in Contents/Frameworks of the bundle;
            // teach the executable to resolve @rpath dylibs from there.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .executableTarget(
            name: "MurmurTests",
            dependencies: ["Murmur"],
            path: "tests/MurmurTests"
        ),
        // Build-time tool that renders the DMG background image. Depends on
        // DesignSystemCore ONLY (not Murmur) so it reuses the Ink palette /
        // serif font / arrow geometry without linking Sparkle or app UI code.
        .executableTarget(
            name: "DMGAssets",
            dependencies: ["DesignSystemCore"],
            path: "Sources/DMGAssets"
        ),
    ]
)
