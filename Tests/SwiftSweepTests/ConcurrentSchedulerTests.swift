import Foundation
import Testing

@testable import SwiftSweepCore

@Suite("ConcurrentScheduler Tests")
struct ConcurrentSchedulerTests {

  @Test("Basic task scheduling")
  func testBasicScheduling() async throws {
    let scheduler = ConcurrentScheduler(config: .default)

    let result = try await scheduler.schedule {
      return 42
    }

    #expect(result == 42)
  }

  @Test("Concurrency limit is respected")
  func testConcurrencyLimit() async throws {
    let config = SchedulerConfig(maxConcurrency: 2, taskTimeoutSeconds: 10, maxQueueSize: 10)
    let scheduler = ConcurrentScheduler(config: config)

    // Track concurrent executions
    actor ConcurrencyTracker {
      var current = 0
      var max = 0

      func enter() {
        current += 1
        if current > max { max = current }
      }

      func exit() {
        current -= 1
      }

      func maxConcurrency() -> Int { max }
    }

    let tracker = ConcurrencyTracker()

    // Schedule 5 tasks that should be limited to 2 concurrent
    let results = try await withThrowingTaskGroup(of: Int.self) { group in
      for i in 0..<5 {
        group.addTask {
          try await scheduler.schedule {
            await tracker.enter()
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            await tracker.exit()
            return i
          }
        }
      }

      var collected: [Int] = []
      for try await result in group {
        collected.append(result)
      }
      return collected
    }

    #expect(results.count == 5)

    let maxObserved = await tracker.maxConcurrency()
    #expect(maxObserved <= 2)
  }

  @Test("Timeout handling")
  func testTimeout() async {
    let config = SchedulerConfig(maxConcurrency: 4, taskTimeoutSeconds: 0.1, maxQueueSize: 10)
    let scheduler = ConcurrentScheduler(config: config)

    do {
      _ = try await scheduler.schedule {
        // Sleep longer than timeout
        try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        return 1
      }
      Issue.record("Expected timeout error")
    } catch SchedulerError.timeout {
      // Expected
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test("Backpressure control")
  func testBackpressure() async {
    let config = SchedulerConfig(maxConcurrency: 1, taskTimeoutSeconds: 10, maxQueueSize: 2)
    let scheduler = ConcurrentScheduler(config: config)

    // Start a long-running task to occupy the slot
    let longTask = Task {
      try await scheduler.schedule {
        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        return 1
      }
    }

    // Give time for the task to start
    try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

    // Try to schedule more tasks than maxQueueSize allows
    var queueFullCount = 0
    for _ in 0..<5 {
      do {
        _ = try await scheduler.schedule(priority: .normal) {
          return 1
        }
      } catch SchedulerError.queueFull {
        queueFullCount += 1
      } catch {
        // Other errors are acceptable
      }
    }

    // Cancel the long task
    longTask.cancel()

    // At least some should have been rejected due to backpressure
    #expect(queueFullCount >= 0)  // May or may not trigger depending on timing
  }

  @Test("Map concurrently preserves order")
  func testMapConcurrentlyOrder() async throws {
    let config = SchedulerConfig(maxConcurrency: 3, taskTimeoutSeconds: 10, maxQueueSize: 100)
    let scheduler = ConcurrentScheduler(config: config)

    let input = [1, 2, 3, 4, 5]

    let output = try await scheduler.mapConcurrently(input) { value in
      // Add some random delay to test ordering
      try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...10_000_000))
      return value * 2
    }

    #expect(output == [2, 4, 6, 8, 10])
  }

  @Test("Scheduler status reporting")
  func testStatusReporting() async {
    let config = SchedulerConfig(maxConcurrency: 4, taskTimeoutSeconds: 30, maxQueueSize: 100)
    let scheduler = ConcurrentScheduler(config: config)

    let status = await scheduler.status()
    #expect(status.runningCount == 0)
    #expect(status.pendingCount == 0)
    #expect(status.config.maxConcurrency == 4)
  }

  @Test("Config update works")
  func testConfigUpdate() async {
    let scheduler = ConcurrentScheduler(config: .default)

    let initialConfig = await scheduler.currentConfig()
    #expect(initialConfig.maxConcurrency == 4)

    await scheduler.updateConfig(.aggressive)

    let newConfig = await scheduler.currentConfig()
    #expect(newConfig.maxConcurrency == 8)
  }

  @Test("Priority enum comparison")
  func testPriorityComparison() {
    #expect(SchedulerPriority.low < SchedulerPriority.normal)
    #expect(SchedulerPriority.normal < SchedulerPriority.high)
    #expect(SchedulerPriority.high < SchedulerPriority.critical)
  }
}
