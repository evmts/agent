// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentApp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "AgentApp", targets: ["AgentApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        // C library target for libghostty
        .systemLibrary(
            name: "CGhostty",
            path: "Libraries",
            pkgConfig: nil,
            providers: []
        ),
        .executableTarget(
            name: "AgentApp",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                "CGhostty"
            ],
            path: "AgentApp",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Libraries",
                    "-lghostty"
                ]),
                .linkedFramework("Metal"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreText"),
                .linkedFramework("Security"),
                .linkedFramework("Carbon"),
                .linkedLibrary("c++")
            ]
        )
    ]
)
