// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OW120",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OW120", targets: ["OW120App"])],
    targets: [
        .target(name: "OW120Core"),
        .executableTarget(name: "OW120App", dependencies: ["OW120Core"]),
        .testTarget(name: "OW120CoreTests", dependencies: ["OW120Core"])
    ],
    swiftLanguageModes: [.v5]
)
