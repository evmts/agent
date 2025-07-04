// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "plue",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "plue", targets: ["plue"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/qeude/SwiftDown", branch: "main"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .systemLibrary(
            name: "libplue",
            path: "include"
        ),
        .systemLibrary(
            name: "farcaster",
            path: "src"
        ),
        .executableTarget(
            name: "plue",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "SwiftDown", package: "SwiftDown"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "libplue",
                "farcaster"
            ],
            exclude: ["Info.plist", "UnifiedMessageBubbleDocumentation.md"],
            resources: [
                .process("Plue.sdef"),
                .process("TerminalShaders.metal")
            ],
            linkerSettings: [
                .unsafeFlags(["-Lzig-out/lib", "-llibplue", "-lfarcaster", "-lghostty", "-lghostty_terminal", "-lterminal"])
            ]),
        .testTarget(
            name: "plueTests",
            dependencies: ["plue"],
            path: "Tests/plueTests"
        ),
        .testTarget(
            name: "PlueUITests",
            dependencies: [],
            path: "Tests/PlueUITests"
        ),
    ]
)
