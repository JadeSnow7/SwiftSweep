# Changelog

All notable changes to SwiftSweep will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-01-01

### Added
- **Sidebar Navigation Reorganization**:
  - App Management
  - Media & Storage
  - Developer & Diagnostics 

### Fixed
- **Git Pack Index**: Resolves "non-monotonic index" errors by removing problematic AppleDouble (`._*`) files from `.git/objects/pack/`.

## [0.2.0] - 2025-12-27

### Added
- **Galaxy View**: Interactive dependency graph visualization
  - Canvas-based rendering for 200+ nodes
  - Force-directed layout with animated simulation
  - Level of Detail (LOD) rendering (cluster/overview/detail)
  - Viewport culling for large graphs (>200 nodes)
  - Ecosystem-specific coloring (Homebrew/npm/pip/gem)
  - Node hover highlight (1.2x scale)
  - Context menu (Select/Focus/Copy)
  - Double-click to focus and zoom
  - Edge coloring by source ecosystem
  - Zoom-dependent edge opacity and line width

- **Time Machine**: Package snapshot and comparison
  - Capture current package state with metadata
  - ISO-8601 JSON export/import
  - Automatic classification: Requested vs Transitive packages
  - Diff view (Added/Removed/Changed)
  - Impact analysis with cross-ecosystem warnings
  - Enhanced GhostBuster with removal impact preview

- **Ghost Buster**: Orphan package detection
  - Identify packages with no incoming dependencies
  - Impact analysis before deletion
  - System package warnings (openssl, python, node, etc.)

- **Package Scanner Enhancements**:
  - Added size calculation for all package types
  - Pip package metadata provider
  - Dependency edge extraction for Homebrew, npm, and pip
  - GraphStore with SQLite backend
  - Batch query API for large graphs

### Improved
- Enhanced `RemovalImpact` struct with warnings field
- Better error handling in SnapshotView with loading states
- Improved dark mode adaptation across all views
- Project structure reorganization

### Fixed
- Zoom edge misalignment in Galaxy View
- Actor isolation warnings in build
- ResolvedVersion API usage
- Package.swift sources configuration

## [0.1.0] - Initial Release

### Added
- System monitoring (CPU, Memory, Disk, Network)
- Smart Insights with rule-based recommendations
- System cache cleaning
- Application uninstaller with residue scan
- System optimization tools
- Disk space analyzer (Treemap/Tree/List views)
- Application inventory manager
- Package manager integration (Homebrew/npm/pip/gem)
- Git repository scanner and maintenance tools
- Privileged Helper integration
- CLI tool (`swiftsweep`)
