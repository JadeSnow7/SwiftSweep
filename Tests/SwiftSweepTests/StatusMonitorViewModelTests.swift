import XCTest

@testable import SwiftSweepCore
@testable import SwiftSweepUI

@MainActor
final class StatusMonitorViewModelTests: XCTestCase {
  func testRefreshSkipsReentryWhenPreviousRefreshIsRunning() async {
    let metricsProvider = SlowMetricsProvider(delayNanos: 300_000_000)
    let peripheralProvider = CountingPeripheralProvider()
    let viewModel = StatusMonitorViewModel(
      metricsProvider: metricsProvider,
      peripheralProvider: peripheralProvider
    )

    async let firstRefresh: Void = viewModel.refreshForTesting(includePeripherals: true)
    async let secondRefresh: Void = viewModel.refreshForTesting(includePeripherals: true)
    _ = await (firstRefresh, secondRefresh)

    let metricsCalls = await metricsProvider.invocationCount()
    let peripheralCalls = await peripheralProvider.invocationCount()
    XCTAssertEqual(metricsCalls, 1)
    XCTAssertEqual(peripheralCalls, 1)
  }

  func testRefreshWithoutPeripheralsDoesNotFetchSnapshot() async {
    let metricsProvider = SlowMetricsProvider(delayNanos: 100_000_000)
    let peripheralProvider = CountingPeripheralProvider()
    let viewModel = StatusMonitorViewModel(
      metricsProvider: metricsProvider,
      peripheralProvider: peripheralProvider
    )

    async let firstRefresh: Void = viewModel.refreshForTesting(includePeripherals: false)
    async let secondRefresh: Void = viewModel.refreshForTesting(includePeripherals: false)
    _ = await (firstRefresh, secondRefresh)

    let metricsCalls = await metricsProvider.invocationCount()
    let peripheralCalls = await peripheralProvider.invocationCount()
    XCTAssertEqual(metricsCalls, 1)
    XCTAssertEqual(peripheralCalls, 0)
  }
}

private actor SlowMetricsProvider: StatusMetricsProviding {
  private var calls = 0
  private let delayNanos: UInt64

  init(delayNanos: UInt64) {
    self.delayNanos = delayNanos
  }

  func getMetrics() async throws -> SystemMonitor.SystemMetrics {
    calls += 1
    try await Task.sleep(nanoseconds: delayNanos)
    var metrics = SystemMonitor.SystemMetrics()
    metrics.cpuUsage = 8
    metrics.memoryUsage = 0.25
    return metrics
  }

  func invocationCount() -> Int {
    calls
  }
}

private actor CountingPeripheralProvider: PeripheralSnapshotProviding {
  private var calls = 0

  func getSnapshot() async -> PeripheralSnapshot {
    calls += 1
    return PeripheralSnapshot()
  }

  func invocationCount() -> Int {
    calls
  }
}
