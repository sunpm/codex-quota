// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexQuota", targets: ["CodexQuota"])],
    targets: [
        .target(name: "CZstd"),
        .target(name: "QuotaCore", dependencies: ["CZstd"]),
        .executableTarget(name: "CodexQuota", dependencies: ["QuotaCore"]),
        .executableTarget(name: "QuotaCoreChecks", dependencies: ["QuotaCore"], path: "Tests/QuotaCoreTests")
    ]
)
