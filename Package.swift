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
    ],
    targets: [
        .target(
            name: "GDockerCore",
            dependencies: [.product(name: "AsyncHTTPClient", package: "async-http-client")]
        ),
        .executableTarget(
            name: "GDocker",
            dependencies: ["GDockerCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GDockerCoreTests",
            dependencies: ["GDockerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
