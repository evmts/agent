// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "plue",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/qeude/SwiftDown", branch: "main"),
        .package(url: "https://github.com/CodeEditApp/CodeEditTextView", from: "0.1.0"),
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
                .product(name: "CodeEditTextView", package: "CodeEditTextView"),
                "libplue",
                "farcaster"
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags(["-Llib", "-lpluecore", "-lfarcaster"])
            ]),
    ]
)
