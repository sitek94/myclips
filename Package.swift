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
    targets: [
        .target(name: "MyClipsCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "MyClips",
            dependencies: ["MyClipsCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "MyClipsBench", dependencies: ["MyClipsCore"]),
        .executableTarget(name: "MyClipsSeed", dependencies: ["MyClipsCore"]),
        .executableTarget(name: "MyClipsDriver"),
        .testTarget(name: "MyClipsCoreTests", dependencies: ["MyClipsCore"]),
    ]
)
