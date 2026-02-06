# Phase 2: Testing Infrastructure - Coverage Analysis

## Baseline Coverage Assessment

**Date:** 2026-02-06
**Total Coverage:** 5.74% (2,408 / 41,962 lines)
**Target Coverage:** 80%+

## Current Test Suite

**Total Tests:** 88 tests
**Test Files:** 14 files
**All Tests Passing:** ✅

### Existing Test Files
1. `CLIJSONContractTests.swift` - CLI JSON output validation
2. `ConcurrentSchedulerTests.swift` - Scheduler tests (15 tests)
3. `DiagnosticsGuideTests.swift` - Diagnostics guide tests
4. `PerformanceMonitorTests.swift` - Performance monitoring tests
5. `PeripheralInspectorTests.swift` - Peripheral inspection tests (4 tests)
6. `ProcessMonitorTests.swift` - Process monitoring tests (5 tests)
7. `ReducerTests.swift` - State reducer tests (18 tests)
8. `StatusMonitorViewModelTests.swift` - Status view model tests (2 tests)
9. `SwiftSweepTests.swift` - Basic integration tests (2 tests)
10. `PackageScannerTests.swift` - Package scanner tests (14 tests)

## Coverage by Module

### Well-Covered Modules (>70%)
- ✅ `PeripheralModels.swift` - 100.00%
- ✅ `PackageSizeCalculator.swift` - 100.00%
- ✅ `DiagnosticsGuideService.swift` - 75.56%
- ✅ `HardwareJSONDTO.swift` - 97.96%
- ✅ `ConcurrentScheduler.swift` - 97.98%
- ✅ `SystemMonitor.swift` - 85.87%
- ✅ `CleanupEngine.swift` - 80.80%
- ✅ `ProcessRunner.swift` - 85.69%
- ✅ `Reducer.swift` - 80.54%
- ✅ `ProcessMonitor.swift` - 78.97%

### Partially Covered Modules (30-70%)
- ⚠️ `GraphStore.swift` - 68.83%
- ⚠️ `PackageIdentity.swift` - 86.96%
- ⚠️ `PathNormalizer.swift` - 52.17%
- ⚠️ `PerformanceMonitor.swift` - 59.49%
- ⚠️ `CleanupAllowlist.swift` - 64.71%
- ⚠️ `AppState.swift` - 52.63%
- ⚠️ `DirectorySizeCache.swift` - 41.38%
- ⚠️ `ToolLocator.swift` - 37.33%

### Uncovered Modules (0%)
**Critical Engines:**
- ❌ `UninstallEngine.swift` - 25.64% (needs 90% target)
- ❌ `RecommendationEngine.swift` - 0.00%
- ❌ `AnalyzerEngine.swift` - 0.00%
- ❌ `OptimizationEngine.swift` - 0.00%

**Package Management:**
- ❌ `PackageScanner.swift` - 0.00%
- ❌ `HomebrewProvider.swift` - 0.00%
- ❌ `NpmProvider.swift` - 0.00%
- ❌ `PipProvider.swift` - 0.00%
- ❌ `GemProvider.swift` - 0.00%

**Media & I/O:**
- ❌ `MediaAnalyzer.swift` - 0.00%
- ❌ `IOAnalyzer.swift` - 0.00%
- ❌ `FSEventsTracer.swift` - 0.00%
- ❌ `ESSystemTracer.swift` - 0.00%

**Git:**
- ❌ `GitRepoScanner.swift` - 0.00%
- ❌ `GitRepoCleaner.swift` - 0.00%

**Recommendation Rules (all 0%):**
- ❌ `BrowserCacheRule.swift`
- ❌ `BuildArtifactsRule.swift`
- ❌ `DeveloperCacheRule.swift`
- ❌ `LargeCacheRule.swift`
- ❌ `LowDiskSpaceRule.swift`
- ❌ `MailAttachmentsRule.swift`
- ❌ `OldDownloadsRule.swift`
- ❌ `ScreenshotCleanupRule.swift`
- ❌ `TrashReminderRule.swift`
- ❌ `UnusedAppsRule.swift`

**UI (all 0%):**
- All SwiftUI views have 0% coverage (expected, UI testing is different)

## Coverage Gaps Analysis

### Priority 1: Core Engines (Target: 90%)
1. **UninstallEngine** - Currently 25.64%
   - Need tests for: `scanInstalledApps()`, `findResiduals()`, `createDeletionPlan()`
   - Estimated: 20 tests

2. **RecommendationEngine** - Currently 0%
   - Need tests for: `evaluateWithSystemContext()`, rule evaluation, caching
   - Estimated: 25 tests

3. **AnalyzerEngine** - Currently 0%
   - Need tests for: disk scanning, treemap generation, file analysis
   - Estimated: 15 tests

### Priority 2: Package Management (Target: 75%)
4. **PackageScanner** - Currently 0%
   - Need tests for: Homebrew/npm/pip/gem scanning
   - Estimated: 30 tests

### Priority 3: Media & I/O (Target: 60%)
5. **MediaAnalyzer** - Currently 0%
   - Need tests for: perceptual hashing, similarity detection
   - Estimated: 15 tests

6. **IOAnalyzer** - Currently 0%
   - Need tests for: I/O monitoring, hotspot detection
   - Estimated: 10 tests

### Priority 4: Git (Target: 70%)
7. **GitRepoScanner** - Currently 0%
   - Need tests for: repo scanning, status detection
   - Estimated: 12 tests

## Test Implementation Plan

### Week 4: Coverage Analysis & UninstallEngine
- [x] Run baseline coverage assessment
- [ ] Create `UninstallEngineTests.swift` (20 tests)
- [ ] Target: 40% → 55% overall coverage

### Week 5: RecommendationEngine & SystemMonitor
- [ ] Create `RecommendationEngineTests.swift` (25 tests)
- [ ] Expand `SystemMonitorTests.swift` (10 more tests)
- [ ] Target: 55% → 70% overall coverage

### Week 6: PackageScanner & MediaAnalyzer
- [ ] Expand `PackageScannerTests.swift` (20 more tests)
- [ ] Create `MediaAnalyzerTests.swift` (15 tests)
- [ ] Target: 70% → 80% overall coverage

### Week 7: Integration & Performance Tests
- [ ] Create integration test suite
- [ ] Create performance benchmarks
- [ ] Target: 80%+ overall coverage

## Success Metrics

- ✅ Baseline: 5.74% coverage
- 🎯 Week 4 Target: 55% coverage
- 🎯 Week 5 Target: 70% coverage
- 🎯 Week 6 Target: 80% coverage
- 🎯 Final Target: 80%+ coverage

## Notes

- UI tests (SwiftUI views) are excluded from coverage targets
- Focus on core business logic and engines
- Integration tests will cover cross-module interactions
- Performance tests will establish baselines for future optimization

---

**Status:** ✅ Baseline Assessment Complete
**Next:** Create UninstallEngineTests.swift
