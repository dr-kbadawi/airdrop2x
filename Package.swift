// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "airdrop2x",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AirDrop2xApp", targets: ["AirDrop2xApp"]),
        .executable(name: "airdrop2x", targets: ["airdrop2x"]),
    ],
    targets: [
        .target(name: "AirDrop2xCore", path: "Sources/AirDrop2xCore"),
        .executableTarget(name: "AirDrop2xApp", dependencies: ["AirDrop2xCore"], path: "Sources/AirDrop2xApp"),
        .executableTarget(name: "airdrop2x", dependencies: ["AirDrop2xCore"], path: "Sources/airdrop2x"),
    ],
    swiftLanguageVersions: [.v5]
)
