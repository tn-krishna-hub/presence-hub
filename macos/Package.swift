// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Presence",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PresenceCore", targets: ["PresenceCore"]),
        .executable(name: "PresenceCLI", targets: ["PresenceCLI"]),
        .executable(name: "PresenceApp", targets: ["PresenceApp"]),
        .executable(name: "PresenceDiagnose", targets: ["PresenceDiagnose"])
    ],
    targets: [
        .target(name: "PresenceCore"),
        .executableTarget(name: "PresenceCLI", dependencies: ["PresenceCore"]),
        .executableTarget(name: "PresenceApp", dependencies: ["PresenceCore"]),
        .executableTarget(name: "PresenceDiagnose"),
        .testTarget(name: "PresenceCoreTests", dependencies: ["PresenceCore"])
    ]
)