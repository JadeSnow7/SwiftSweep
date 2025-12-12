// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftSweep",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SwiftSweepApp", targets: ["SwiftSweepUI"]),
        .library(name: "SwiftSweepCore", targets: ["SwiftSweepCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
    ],
    targets: [
        // Core Framework (Sandbox-compliant only)
        .target(
            name: "SwiftSweepCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/SwiftSweepCore",
            sources: [
                "AnalyzerEngine",
                "SystemMonitor",
            ]
        ),
        
        // GUI Application
        .executableTarget(
            name: "SwiftSweepUI",
            dependencies: ["SwiftSweepCore"],
            path: "Sources/SwiftSweepUI"
        ),
    ]
)
