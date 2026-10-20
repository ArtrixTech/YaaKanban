// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "YaaKanban",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "YaaKanban", targets: ["YaaKanban"]),
        .executable(name: "yaak", targets: ["yaak"]),
    ],
    targets: [
        .target(name: "YaaCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "YaaIntegrations", dependencies: ["YaaCore"]),
        .executableTarget(name: "yaak", dependencies: ["YaaCore", "YaaIntegrations"]),
        .executableTarget(name: "YaaKanban", dependencies: ["YaaCore", "YaaIntegrations"]),
        .testTarget(name: "YaaCoreTests", dependencies: ["YaaCore"]),
        .testTarget(name: "YaaIntegrationsTests", dependencies: ["YaaIntegrations"]),
    ],
    swiftLanguageModes: [.v5]
)
