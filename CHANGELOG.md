# Changelog

All notable changes to SwiftSweep will be documented in this file.

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
