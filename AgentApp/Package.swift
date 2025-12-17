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
        .executableTarget(
            name: "AgentApp",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "AgentApp"
        )
    ]
)
