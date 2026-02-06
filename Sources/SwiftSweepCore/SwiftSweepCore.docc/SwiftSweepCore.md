# ``SwiftSweepCore``

A comprehensive macOS system cleanup and optimization framework.

## Overview

SwiftSweepCore is the core framework powering SwiftSweep, a native macOS system maintenance tool. It provides powerful engines for cleaning, analyzing, and optimizing your Mac.

### Key Features

- **Cleanup Engine**: Scan and remove system caches, logs, and temporary files
- **Uninstall Engine**: Completely remove applications and their residual files
- **System Monitor**: Real-time monitoring of CPU, memory, disk, and network
- **Disk Analyzer**: Visualize disk usage with treemap and tree views
- **Recommendation Engine**: Intelligent suggestions based on system analysis
- **Package Scanner**: Manage Homebrew, npm, pip, and gem packages
- **Media Analyzer**: Detect duplicate and similar images/videos using perceptual hashing
- **I/O Analyzer**: Real-time I/O performance monitoring and optimization suggestions

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>

### Cleanup & Optimization

- ``CleanupEngine``
- ``UninstallEngine``
- ``OptimizationEngine``

### System Analysis

- ``SystemMonitor``
- ``AnalyzerEngine``
- ``RecommendationEngine``

### Package Management

- ``PackageScanner``
- ``GitRepoScanner``

### Advanced Features

- ``MediaAnalyzer``
- ``IOAnalyzer``

### State Management

- ``AppStore``
- ``AppState``
- ``AppAction``

### Shared Utilities

- ``PerformanceMonitor``
- ``ConcurrentScheduler``
