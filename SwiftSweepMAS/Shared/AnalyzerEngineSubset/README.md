# AnalyzerEngineSubset

Read-only disk analysis module for Mac App Store version.

## Purpose

Provide safe, sandboxed disk analysis functionality for the SwiftSweep Finder Extension.

## Intentionally Excluded

This module **does not and must not** include:

- ❌ `CleanupEngine` - File deletion capabilities
- ❌ `OptimizationEngine` - System optimization functions  
- ❌ `PrivilegedHelper` - Root privilege escalation
- ❌ `UninstallEngine` - Application removal
- ❌ `SMAppService` - Background daemon management

## Design Constraints

- **Read-only**: All analysis operations have no side effects
- **Sandboxed**: Works within App Sandbox restrictions
- **Directory limit**: Host app limits registered directories to maximum 20 for Finder performance
- **No shell commands**: No `Process()` or `NSAppleScript` usage

## Maintainer Note

If you need to share code between SwiftSweep (full) and SwiftSweepMAS:

1. Only copy **pure analysis** functions
2. Review for any `Process()`, `NSAppleScript`, or system path access
3. Ensure no imports from excluded engines
4. Update this README with any additions
