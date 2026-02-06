# Architecture Overview

Understanding SwiftSweepCore's architecture and design patterns.

## Overview

SwiftSweepCore is built on modern Swift concurrency and follows a Unidirectional Data Flow (UDF) architecture for predictable state management.

## Core Principles

### 1. Separation of Concerns

The framework is organized into specialized engines:

- **CleanupEngine**: System file cleanup
- **UninstallEngine**: Application removal
- **AnalyzerEngine**: Disk space analysis
- **SystemMonitor**: Real-time metrics
- **RecommendationEngine**: Intelligent suggestions
- **PackageScanner**: Package manager integration

### 2. Unidirectional Data Flow

All state changes flow in one direction:

```
User Action → Dispatch Action → Reducer → New State → UI Update
                    ↓
                 Effects (async operations)
```

Key components:

- ``AppState``: Single source of truth
- ``AppAction``: All possible state changes
- ``AppStore``: State container and dispatcher
- **Reducers**: Pure functions that update state
- **Effects**: Handle side effects (network, file I/O)

### 3. Swift Concurrency

SwiftSweepCore leverages modern Swift concurrency:

- `async/await` for asynchronous operations
- `@MainActor` for UI-safe operations
- `Task` for concurrent execution
- `AsyncStream` for real-time monitoring

### 4. Safety First

Security and safety are paramount:

- **Dry-run mode**: Preview before execution
- **Path validation**: Prevent accidental deletions
- **Privilege separation**: Helper tool for elevated operations
- **Audit logging**: Track all operations

## Module Structure

### Core Engines

```
SwiftSweepCore/
├── CleanupEngine/       # System cleanup
├── UninstallEngine/     # App uninstallation
├── AnalyzerEngine/      # Disk analysis
├── SystemMonitor/       # Real-time monitoring
├── RecommendationEngine/ # Intelligent suggestions
├── OptimizationEngine/  # System optimization
├── PackageScanner/      # Package management
├── GitRepoScanner/      # Git repository management
├── MediaAnalyzer/       # Media deduplication
└── IOAnalyzer/          # I/O performance
```

### State Management

```
State/
├── AppState.swift       # Global state
├── AppAction.swift      # All actions
├── AppStore.swift       # State container
└── Reducer.swift        # State reducers
```

### Shared Components

```
Shared/
├── PerformanceMonitor.swift  # Performance tracking
├── ConcurrentScheduler.swift # Task scheduling
└── Models/                   # Shared data models
```

## Design Patterns

### Engine Pattern

Each engine follows a consistent pattern:

```swift
public final class SomeEngine {
  // Singleton or dependency injection
  public static let shared = SomeEngine()

  // Scan/analyze
  public func scan() async throws -> [Item] { }

  // Execute action
  public func execute(items: [Item]) async throws -> Result { }
}
```

### State Pattern

State management follows UDF:

```swift
// 1. Define state
public struct FeatureState: Equatable, Sendable {
  public var items: [Item]
  public var isLoading: Bool
}

// 2. Define actions
public enum FeatureAction: Equatable, Sendable {
  case startScan
  case scanCompleted([Item])
  case scanFailed(String)
}

// 3. Implement reducer
func featureReducer(_ state: FeatureState, _ action: FeatureAction) -> FeatureState {
  var state = state
  switch action {
  case .startScan:
    state.isLoading = true
  case .scanCompleted(let items):
    state.items = items
    state.isLoading = false
  case .scanFailed:
    state.isLoading = false
  }
  return state
}

// 4. Handle effects
@MainActor
final class FeatureEffects {
  func handle(_ action: FeatureAction) {
    switch action {
    case .startScan:
      Task {
        let items = try await engine.scan()
        store.dispatch(.scanCompleted(items))
      }
    default:
      break
    }
  }
}
```

## Performance Considerations

### Concurrency

- Use `TaskGroup` for parallel operations
- Implement cancellation support
- Avoid blocking the main thread

### Memory Management

- Stream large datasets with `AsyncStream`
- Use `@unchecked Sendable` carefully
- Implement proper cleanup in `deinit`

### Caching

- Cache expensive computations
- Invalidate caches appropriately
- Use `NSCache` for automatic memory management

## Testing Strategy

### Unit Tests

Test individual engines in isolation:

```swift
final class CleanupEngineTests: XCTestCase {
  func testScanForCleanableItems() async throws {
    let engine = CleanupEngine()
    let items = try await engine.scanForCleanableItems()
    XCTAssertFalse(items.isEmpty)
  }
}
```

### Integration Tests

Test complete workflows:

```swift
func testCleanupWorkflow() async throws {
  // Scan → Preview → Execute → Verify
}
```

### Performance Tests

Benchmark critical operations:

```swift
func testScanPerformance() throws {
  measure {
    _ = try await engine.scan()
  }
}
```

## Best Practices

1. **Always use async/await** for I/O operations
2. **Dispatch actions** instead of mutating state directly
3. **Handle errors gracefully** with proper error types
4. **Document public APIs** with DocC comments
5. **Write tests** for all public interfaces
6. **Use dependency injection** for testability

## See Also

- <doc:GettingStarted>
- ``AppStore``
- ``CleanupEngine``
- ``SystemMonitor``
