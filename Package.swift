// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyClips",
    platforms: [.macOS(.v26)],
    products: [
        // Lowercase-first on purpose: the app and its process are called "myClips".
        .executable(name: "myClips", targets: ["MyClips"]),
        .executable(name: "myClipsDriver", targets: ["MyClipsDriver"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sitek94/mykit", from: "0.2.0"),
        // Pins the SwiftLint binary that scripts/check.sh runs (same version as myKit); no target uses it.
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.65.1"),
    ],
    targets: [
        .target(name: "MyClipsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "MyClips",
            dependencies: ["MyClipsCore", .product(name: "MyKit", package: "mykit")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "MyClipsBench", dependencies: ["MyClipsCore"]),
        .executableTarget(name: "MyClipsSeed", dependencies: ["MyClipsCore"]),
        .executableTarget(name: "MyClipsDriver"),
        .testTarget(name: "MyClipsCoreTests", dependencies: ["MyClipsCore"]),
    ]
)
