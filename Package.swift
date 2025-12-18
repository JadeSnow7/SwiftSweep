// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "SwiftSweep",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "swiftsweep", targets: ["SwiftSweepCLI"]),
    .executable(name: "SwiftSweepApp", targets: ["SwiftSweepUI"]),
    .library(name: "SwiftSweepCore", targets: ["SwiftSweepCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-log", from: "1.4.0"),
    .package(path: "Packages/SwiftSweepAppInventory"),
  ],
  targets: [
    // Core Framework
    .target(
      name: "SwiftSweepCore",
      dependencies: [
        .product(name: "Logging", package: "swift-log")
      ],
      path: "Sources/SwiftSweepCore",
      sources: [
        "CleanupEngine",
        "AnalyzerEngine",
        "SystemMonitor",
        "OptimizationEngine",
        "UninstallEngine",
        "PrivilegedHelper",
        "Shared",
        "PackageScanner",
        "RecommendationEngine",
        "RecommendationEngine/Rules",
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

    // GUI Application
    .executableTarget(
      name: "SwiftSweepUI",
      dependencies: [
        "SwiftSweepCore",
        .product(name: "SwiftSweepAppInventory", package: "SwiftSweepAppInventory"),
      ],
      path: "Sources/SwiftSweepUI"
    ),

    // Helper Tool
    .executableTarget(
      name: "SwiftSweepHelper",
      dependencies: [],
      path: "Helper",
      exclude: [
        "com.swiftsweep.helper.plist"
      ],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Helper/Info.plist",
        ])
      ]
    ),

    // Tests
    .testTarget(
      name: "SwiftSweepTests",
      dependencies: ["SwiftSweepCore"],
      path: "Tests"
    ),
  ]
)
