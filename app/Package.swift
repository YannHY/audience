// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Audience",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.executable(name: "Audience", targets: ["Audience"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "AudienceCore"),
        .executableTarget(name: "Audience", dependencies: ["AudienceCore", .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))]),
        .testTarget(name: "AudienceCoreTests", dependencies: ["AudienceCore"])
    ]
)
