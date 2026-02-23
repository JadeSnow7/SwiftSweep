// swift-tools-version: 5.9
import PackageDescription
import Foundation

let hasEndpointSecurityFramework: Bool = {
  if FileManager.default.fileExists(atPath: "/System/Library/Frameworks/EndpointSecurity.framework") {
    return true
  }

  if let sdkRoot = ProcessInfo.processInfo.environment["SDKROOT"] {
    let sdkFrameworkPath = sdkRoot + "/System/Library/Frameworks/EndpointSecurity.framework"
    if FileManager.default.fileExists(atPath: sdkFrameworkPath) {
      return true
    }
  }

  return false
}()

let swiftSweepCoreSwiftSettings: [SwiftSetting] = hasEndpointSecurityFramework
  ? []
  : [.define("SWIFTSWEEP_NO_ENDPOINT_SECURITY")]

let swiftSweepCoreLinkerSettings: [LinkerSetting] = {
  var settings: [LinkerSetting] = [
    .linkedFramework("IOKit"),
    .linkedFramework("ApplicationServices"),
    .linkedLibrary("sqlite3"),
  ]

  if hasEndpointSecurityFramework {
    settings.insert(.linkedFramework("EndpointSecurity"), at: 0)
  }

  return settings
}()

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
    .library(name: "SwiftSweepCapCutPlugin", targets: ["SwiftSweepCapCutPlugin"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.6.0")),
    .package(url: "https://github.com/apple/swift-log", .upToNextMinor(from: "1.6.0")),
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
        "GitRepoScanner",
        "Git",
        "RecommendationEngine",
        "RecommendationEngine/Rules",
        "Snapshot",
        "MediaAnalyzer",
        "IOAnalyzer",
        "Plugin",
        "SmartInterpreter",
        "Integration",
        "State",
        "Workspace",
      ],
      swiftSettings: swiftSweepCoreSwiftSettings,
      linkerSettings: swiftSweepCoreLinkerSettings
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
        "SwiftSweepCapCutPlugin",
        .product(name: "SwiftSweepAppInventory", package: "SwiftSweepAppInventory"),
      ],
      path: "Sources/SwiftSweepUI"
    ),

    // CapCut Plugin
    .target(
      name: "SwiftSweepCapCutPlugin",
      dependencies: ["SwiftSweepCore"],
      path: "Sources/SwiftSweepCapCutPlugin"
    ),

    // Helper Tool
    .executableTarget(
      name: "SwiftSweepHelper",
      dependencies: [],
      path: "Helper",
      exclude: [
        "Info.plist",
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
      dependencies: [
        "SwiftSweepCore",
        "SwiftSweepCLI",
        "SwiftSweepUI",
      ],
      path: "Tests"
    ),
  ]
)
