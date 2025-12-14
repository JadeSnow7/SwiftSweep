// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftSweepAppInventory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SwiftSweepAppInventory",
            targets: ["AppInventoryLogic", "AppInventoryUI"]
        ),
    ],
    dependencies: [
        // No external dependencies for now, keeping it lightweight
    ],
    targets: [
        .target(
            name: "AppInventoryLogic",
            dependencies: []
        ),
        .target(
            name: "AppInventoryUI",
            dependencies: ["AppInventoryLogic"]
        ),
        .testTarget(
            name: "AppInventoryTests",
            dependencies: ["AppInventoryLogic"]
        ),
    ]
)
