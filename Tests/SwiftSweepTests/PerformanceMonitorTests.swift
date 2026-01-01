import Foundation
import Testing

@testable import SwiftSweepCore

@Suite("PerformanceMonitor Tests")
struct PerformanceMonitorTests {

  @Test("Record and retrieve metrics")
  func testRecordAndRetrieve() async {
    let monitor = PerformanceMonitor(maxStoredMetrics: 100)

    let metric = OperationMetrics(
      operationName: "test.operation",
      startTicks: 1000,
      endTicks: 2000,
      durationNanos: 1_000_000,  // 1ms
      itemsProcessed: 10,
      bytesProcessed: 1024,
      outcome: .success
    )

    await monitor.record(metric)

    let snapshot = await monitor.snapshot(limit: 10)
    #expect(snapshot.count == 1)
    #expect(snapshot[0].operationName == "test.operation")
    #expect(snapshot[0].itemsProcessed == 10)
    #expect(snapshot[0].bytesProcessed == 1024)
    #expect(snapshot[0].outcome == .success)
  }

  @Test("Ring buffer overflow handling")
  func testRingBufferOverflow() async {
    let maxMetrics = 10
    let monitor = PerformanceMonitor(maxStoredMetrics: maxMetrics)

    // Record more than maxStoredMetrics
    for i in 0..<20 {
      await monitor.record(
        OperationMetrics(
          operationName: "op.\(i)",
          startTicks: UInt64(i * 1000),
          endTicks: UInt64(i * 1000 + 100),
          durationNanos: 100_000,
          outcome: .success
        ))
    }

    let snapshot = await monitor.snapshot(limit: 100)
    #expect(snapshot.count == maxMetrics)

    // Should only have the last 10 operations (10-19)
    #expect(snapshot[0].operationName == "op.10")
    #expect(snapshot[9].operationName == "op.19")
  }

  @Test("Aggregated statistics calculation")
  func testAggregatedStats() async {
    let monitor = PerformanceMonitor(maxStoredMetrics: 100)

    // Record 5 successful operations with varying durations
    for i in 1...5 {
      await monitor.record(
        OperationMetrics(
          operationName: "aggregate.test",
          startTicks: 0,
          endTicks: UInt64(i),
          durationNanos: UInt64(i) * 1_000_000_000,  // i seconds
          itemsProcessed: i,
          bytesProcessed: Int64(i * 100),
          outcome: .success
        ))
    }

    // Record 1 failed operation
    await monitor.record(
      OperationMetrics(
        operationName: "aggregate.test",
        startTicks: 0,
        endTicks: 1,
        durationNanos: 1_000_000_000,
        itemsProcessed: 0,
        bytesProcessed: 0,
        outcome: .failed(message: "Test failure")
      ))

    let stats = await monitor.aggregatedStats()

    #expect(stats["aggregate.test"] != nil)

    let testStats = stats["aggregate.test"]!
    #expect(testStats.count == 6)
    #expect(testStats.successCount == 5)
    #expect(testStats.totalItems == 15)  // 1+2+3+4+5
    #expect(testStats.totalBytes == 1500)  // 100+200+300+400+500
  }

  @Test("Track wrapper captures success")
  func testTrackSuccess() async throws {
    let monitor = PerformanceMonitor(maxStoredMetrics: 100)

    let result = await monitor.track("track.success") {
      // Simulate some work
      try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
      return 42
    }

    #expect(result == 42)

    let snapshot = await monitor.snapshot()
    #expect(snapshot.count == 1)
    #expect(snapshot[0].operationName == "track.success")
    #expect(snapshot[0].outcome == .success)
    #expect(snapshot[0].durationSeconds > 0)
  }

  @Test("Track wrapper captures failure")
  func testTrackFailure() async {
    let monitor = PerformanceMonitor(maxStoredMetrics: 100)

    struct TestError: Error {}

    do {
      _ = try await monitor.track("track.failure") {
        throw TestError()
      }
      Issue.record("Expected error to be thrown")
    } catch {
      // Expected
    }

    let snapshot = await monitor.snapshot()
    #expect(snapshot.count == 1)
    #expect(snapshot[0].operationName == "track.failure")

    if case .failed = snapshot[0].outcome {
      // Expected
    } else {
      Issue.record("Expected failed outcome")
    }
  }

  @Test("Duration calculation uses monotonic clock")
  func testDurationCalculation() async {
    let metric = OperationMetrics(
      operationName: "duration.test",
      startTicks: 0,
      endTicks: 1000,
      durationNanos: 1_500_000_000,  // 1.5 seconds
      outcome: .success
    )

    #expect(metric.durationSeconds == 1.5)
  }

  @Test("Clear removes all metrics")
  func testClear() async {
    let monitor = PerformanceMonitor(maxStoredMetrics: 100)

    await monitor.record(
      OperationMetrics(
        operationName: "clear.test",
        startTicks: 0,
        endTicks: 1,
        durationNanos: 1000,
        outcome: .success
      ))

    let beforeClear = await monitor.snapshot()
    #expect(beforeClear.count == 1)

    await monitor.clear()

    let afterClear = await monitor.snapshot()
    #expect(afterClear.isEmpty)
  }
}
