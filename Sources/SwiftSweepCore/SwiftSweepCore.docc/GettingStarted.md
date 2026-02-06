# Getting Started with SwiftSweepCore

Learn how to integrate SwiftSweepCore into your macOS application.

## Overview

SwiftSweepCore provides a comprehensive set of tools for system cleanup, analysis, and optimization on macOS. This guide will help you get started with the framework.

## Installation

### Swift Package Manager

Add SwiftSweepCore to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/JadeSnow7/SwiftSweep.git", from: "0.6.0")
]
```

Then add it to your target:

```swift
.target(
  name: "YourTarget",
  dependencies: [
    .product(name: "SwiftSweepCore", package: "SwiftSweep")
  ]
)
```

## Basic Usage

### Scanning for Cleanable Items

```swift
import SwiftSweepCore

// Create cleanup engine
let engine = CleanupEngine()

// Scan for cleanable items
let items = try await engine.scanForCleanableItems()

// Display results
for item in items {
  print("\(item.name): \(item.size) bytes")
}
```

### System Monitoring

```swift
import SwiftSweepCore

// Get system metrics
let monitor = SystemMonitor.shared
let metrics = try await monitor.getMetrics()

print("CPU Usage: \(metrics.cpuUsage)%")
print("Memory Usage: \(metrics.memoryUsage)%")
print("Disk Usage: \(metrics.diskUsage)%")
```

### Uninstalling Applications

```swift
import SwiftSweepCore

// Create uninstall engine
let engine = UninstallEngine()

// Scan installed apps
let apps = try await engine.scanInstalledApps()

// Find residuals for an app
let residuals = try await engine.findResiduals(for: app)

// Create deletion plan
let plan = try engine.createDeletionPlan(for: app, residuals: residuals)

// Execute (with user confirmation)
try await engine.execute(plan: plan)
```

## Architecture

SwiftSweepCore follows a Unidirectional Data Flow (UDF) architecture:

- **State**: Centralized app state in ``AppState``
- **Actions**: All state changes via ``AppAction``
- **Store**: ``AppStore`` manages state and dispatches actions
- **Effects**: Side effects handled by dedicated effect handlers

## Next Steps

- Explore the ``CleanupEngine`` for cleaning system files
- Learn about ``SystemMonitor`` for real-time metrics
- Check out ``RecommendationEngine`` for intelligent suggestions
- Read the <doc:Architecture> guide for advanced patterns
