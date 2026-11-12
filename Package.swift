// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "GDocker",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GDocker", targets: ["GDocker"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "GDockerCore",
            dependencies: [.product(name: "AsyncHTTPClient", package: "async-http-client")]
        ),
        .target(
            name: "GDockerMCP",
            dependencies: [
                "GDockerCore",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),
        .executableTarget(
            name: "GDocker",
            dependencies: ["GDockerCore", "GDockerMCP"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GDockerCoreTests",
            dependencies: ["GDockerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "GDockerMCPTests",
            dependencies: ["GDockerMCP", "GDockerCore"]
        ),
    ]
)
