// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuotaDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexQuotaDock", targets: ["CodexQuotaDock"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "CodexQuotaDock", dependencies: ["QuotaCore"]),
        .executableTarget(name: "QuotaCoreChecks", dependencies: ["QuotaCore"], path: "Tests/QuotaCoreTests")
    ]
)
