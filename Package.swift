// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "clawpypaste",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "clawpypaste", targets: ["clawpypaste"]),
    ],
    targets: [
        .executableTarget(
            name: "clawpypaste",
            path: "Sources/clawpypaste"
        ),
    ]
)
