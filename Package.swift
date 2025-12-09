// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MoleKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "molekit", targets: ["MoleKitCLI"]),
        .library(name: "MoleKitCore", targets: ["MoleKitCore"]),
        .library(name: "MoleKitUI", targets: ["MoleKitUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
    ],
    targets: [
        // Core Framework
        .target(
            name: "MoleKitCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/MoleKitCore",
            sources: [
                "CleanupEngine",
                "AnalyzerEngine", 
                "SystemMonitor",
                "OptimizationEngine",
            ]
        ),
        
        // CLI Tool
        .executableTarget(
            name: "MoleKitCLI",
            dependencies: [
                "MoleKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MoleKitCLI"
        ),
        
        // GUI Application Framework
        .target(
            name: "MoleKitUI",
            dependencies: ["MoleKitCore"],
            path: "Sources/MoleKitUI"
        ),
        
        // Tests
        .testTarget(
            name: "MoleKitTests",
            dependencies: ["MoleKitCore"],
            path: "Tests"
        ),
    ]
)
