// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexQuota", targets: ["CodexQuota"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "CZstd"),
        .target(name: "QuotaCore", dependencies: ["CZstd"]),
        .executableTarget(
            name: "CodexQuota",
            dependencies: ["QuotaCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(name: "QuotaCoreChecks", dependencies: ["QuotaCore"], path: "Tests/QuotaCoreTests")
    ]
)
