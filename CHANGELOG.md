# Changelog

All notable changes to SwiftSweep will be documented in this file.

## [0.6.0] - 2026-01-14

### Added
- **Per-Process I/O Tracking**: Real-time disk read/write rates (bytes/sec) for each process
  - Delta-based calculation for accurate throughput measurement
  - Display format: `↓50M/s ↑10M/s` or `–` when idle
  - Sort processes by I/O activity to identify disk-heavy operations
- **Process Detail Drawer**: Click any process row to view detailed metrics
  - Metrics grid showing CPU, Memory, Disk Read/Write rates
  - CPU usage sparkline chart (last 5 samples) for trend visualization
  - Quick actions: Force Quit (functional), Pause/Limit (placeholders)
  - Smooth slide-in animation with backdrop overlay
- **Process History Tracking**: Automatic recording of last 5 snapshots per process
- **Enhanced Process List**: Network and I/O columns now visible in all process views

### Changed
- **I/O Sorting**: Changed from cumulative totals to real-time rates for more meaningful sorting
- **ProcessMonitor**: Extended with I/O counter caching for delta calculation

### Fixed
- **Git Repository Size**: Fixed issue where Git repositories showed 0 bytes in Disk Analyzer
  - Now correctly scans repository contents while excluding `.git` directory
- **FSEvents Deprecation**: Replaced deprecated `FSEventStreamScheduleWithRunLoop` with `FSEventStreamSetDispatchQueue`
- **Swift 6 Compatibility**: Fixed Sendable capture warnings in FSEventsTracer

---

## [0.5.1] - 2026-01-05

### Added
- **Kill Process**: Force quit processes from the process list with confirmation dialog.
- Hover over a process row to reveal the quit button.

---

## [0.5.0] - 2026-01-05

### Added
- **Process Monitor Details**: Click on CPU or Memory cards in Status view to see detailed process list.
- **Process Info**: Real-time CPU usage (delta-based), Memory usage, PID, and User info.
- **Auto-refresh**: Process list automatically refreshes every 2 seconds.
- **Localized UI**: Complete English and Chinese (Simplified) support for process monitoring.

### Fixed
- **CPU Calculation**: Fixed an issue where CPU usage was incorrectly reported as 100% (now uses differential sampling).
- **UI Improvements**: Fixed layout issues in process list header and column widths.


## [0.3.0] - 2026-01-01

### Added

#### Plugin Architecture
- **SweepPlugin Protocol**: Extensible plugin interface for third-party features
- **PluginManager**: Singleton registry with UserDefaults-based enable/disable
- **PluginContext**: Safe execution context for plugins
- **CapCut Plugin MVP**: Draft parsing, orphan media detection

#### Commercial Frontend Components
- **InsightsAdvancedConfigView**: Rule grouping, drag-and-drop priority, gray-release toggles
- **DataGridView**: NSTableView-based virtualization for 10,000+ rows
- **ResultDashboardView**: Swift Charts with trends, bar charts, and pie charts
- **RuleSettings**: Added `priority()` and `grayRelease()` methods

#### AI Coding Features
- **SmartInterpreter**: Evidence to natural language explanation (Explainable AI)
- **NLCommandParser**: Natural language to filter conditions (English + Chinese)
- **DecisionGraphView**: Visual evidence tree for white-box AI decisions

#### Experience Unification
- **UnifiedStorageView**: Combined Disk Analyzer + Media Analyzer
- **CleanupHistoryView**: Before/after space comparisons, cleanup timeline

### Changed
- **Package.swift**: Added `SwiftSweepCapCutPlugin` target and `SmartInterpreter` source
- **SwiftSweepApp.swift**: Plugin registration and conditional sidebar entry
- **SettingsView.swift**: Added Plugins configuration section

---

## [0.2.0] - 2025-12-20

### Added
- Media Analyzer with pHash and LSH
- I/O Analyzer with real-time throughput/latency
- Sidebar reorganization

---

## [0.1.0] - 2025-12-15

### Added
- Core cleanup, uninstall, and analyze engines
- System monitor (CPU, Memory, Disk, Network)
- SwiftUI interface
- Smart Insights with rules engine
- Package Finder (Homebrew, npm, pip, gem)
- Git repository scanner
- Privileged Helper via SMAppService
