// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpriteRoom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpriteRoomCore", targets: ["SpriteRoomCore"]),
        .library(name: "SpriteRoomScene", targets: ["SpriteRoomScene"]),
        .executable(name: "spriteroom", targets: ["SpriteRoomApp"]),
        .executable(name: "spriteroom-replay", targets: ["SpriteRoomReplay"]),
    ],
    targets: [
        // Pure logic. Must not import AppKit or SpriteKit — enforced by
        // Tests/SpriteRoomCoreTests/ImportBoundaryTests.swift.
        .target(
            name: "SpriteRoomCore",
            path: "Sources/SpriteRoomCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SpriteRoomScene",
            dependencies: ["SpriteRoomCore"],
            path: "Sources/SpriteRoomScene",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SpriteRoomApp",
            dependencies: ["SpriteRoomCore", "SpriteRoomScene"],
            path: "Sources/SpriteRoomApp",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SpriteRoomReplay",
            dependencies: ["SpriteRoomCore"],
            path: "Sources/SpriteRoomReplay",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpriteRoomCoreTests",
            dependencies: ["SpriteRoomCore"],
            path: "Tests/SpriteRoomCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SpriteRoomSceneTests",
            dependencies: ["SpriteRoomScene", "SpriteRoomCore"],
            path: "Tests/SpriteRoomSceneTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
