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
    targets: [
        .target(
            name: "Murmur",
            path: "Sources/Murmur",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .executableTarget(
            name: "MurmurApp",
            dependencies: ["Murmur"],
            path: "Sources/MurmurApp"
        ),
        .executableTarget(
            name: "MurmurTests",
            dependencies: ["Murmur"],
            path: "tests/MurmurTests"
        ),
    ]
)
