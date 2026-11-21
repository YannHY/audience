// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Audience",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Audience", targets: ["Audience"])],
    targets: [
        .target(name: "AudienceCore"),
        .executableTarget(name: "Audience", dependencies: ["AudienceCore"]),
        .testTarget(name: "AudienceCoreTests", dependencies: ["AudienceCore"])
    ]
)
