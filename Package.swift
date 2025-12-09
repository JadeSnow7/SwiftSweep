// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftSweep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "swiftsweep", targets: ["SwiftSweepCLI"]),
        .library(name: "SwiftSweepCore", targets: ["SwiftSweepCore"]),
        .library(name: "SwiftSweepUI", targets: ["SwiftSweepUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
    ],
    targets: [
        // Core Framework
        .target(
            name: "SwiftSweepCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftSweepCore",
            sources: [
                "CleanupEngine",
                "AnalyzerEngine", 
                "SystemMonitor",
                "OptimizationEngine",
                "UninstallEngine",
                "PrivilegedHelper",
            ]
        ),
        
        // CLI Tool
        .executableTarget(
            name: "SwiftSweepCLI",
            dependencies: [
                "SwiftSweepCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SwiftSweepCLI"
        ),
        
        // GUI Application Framework
        .target(
            name: "SwiftSweepUI",
            dependencies: ["SwiftSweepCore"],
            path: "Sources/SwiftSweepUI"
        ),
        
        // Tests
        .testTarget(
            name: "SwiftSweepTests",
            dependencies: ["SwiftSweepCore"],
            path: "Tests"
        ),
    ]
)

