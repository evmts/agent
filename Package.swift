// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "plue",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", from: "0.1.0")
    ],
    targets: [
        .systemLibrary(
            name: "libplue",
            path: "include"
        ),
        .executableTarget(
            name: "plue",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                "libplue"
            ],
            linkerSettings: [
                .unsafeFlags(["-Llib", "-lpluecore"])
            ]),
    ]
)
