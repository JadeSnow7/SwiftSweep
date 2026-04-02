import XCTest

@testable import SwiftSweepCore
@testable import SwiftSweepUI

@MainActor
final class ProcessMonitorViewModelTests: XCTestCase {
  func testInitUsesDefaultMetricSortAndAllowedSortKeys() {
    let viewModel = ProcessMonitorViewModel(
      initialMetric: .memory,
      provider: StubProcessProvider(batches: [[]])
    )

    XCTAssertEqual(viewModel.selectedMetric, .memory)
    XCTAssertEqual(viewModel.sortKey, .memory)
    XCTAssertEqual(viewModel.availableSortKeys, [.cpu, .memory, .name])
  }

  func testSelectingMetricResetsSortKeyToMetricDefault() {
    let viewModel = ProcessMonitorViewModel(
      initialMetric: .memory,
      provider: StubProcessProvider(batches: [[]])
    )
    viewModel.sortKey = .name

    viewModel.selectMetric(.cpu)

    XCTAssertEqual(viewModel.selectedMetric, .cpu)
    XCTAssertEqual(viewModel.sortKey, .cpu)
  }

  func testRefreshKeepsSelectedProcessWhenPidStillExists() async {
    let first = [
      makeProcess(id: 100, name: "Alpha", cpu: 12, memory: 400),
      makeProcess(id: 200, name: "Beta", cpu: 8, memory: 800),
    ]
    let second = [
      makeProcess(id: 200, name: "Beta", cpu: 20, memory: 900),
      makeProcess(id: 300, name: "Gamma", cpu: 5, memory: 100),
    ]
    let viewModel = ProcessMonitorViewModel(
      initialMetric: .cpu,
      provider: StubProcessProvider(batches: [first, second])
    )

    await viewModel.refreshForTesting()
    viewModel.selectProcess(first[1])
    await viewModel.refreshForTesting()

    XCTAssertEqual(viewModel.selectedProcess?.id, 200)
    XCTAssertEqual(viewModel.selectedProcess?.cpuUsage, 20)
  }

  func testRefreshClearsSelectedProcessWhenPidDisappears() async {
    let first = [
      makeProcess(id: 100, name: "Alpha", cpu: 12, memory: 400),
      makeProcess(id: 200, name: "Beta", cpu: 8, memory: 800),
    ]
    let second = [
      makeProcess(id: 300, name: "Gamma", cpu: 5, memory: 100)
    ]
    let viewModel = ProcessMonitorViewModel(
      initialMetric: .cpu,
      provider: StubProcessProvider(batches: [first, second])
    )

    await viewModel.refreshForTesting()
    viewModel.selectProcess(first[1])
    await viewModel.refreshForTesting()

    XCTAssertNil(viewModel.selectedProcess)
  }

  private func makeProcess(id: pid_t, name: String, cpu: Double, memory: Int64) -> SystemProcessInfo {
    SystemProcessInfo(
      id: id,
      name: name,
      cpuUsage: cpu,
      memoryUsage: memory,
      networkBytesIn: 0,
      networkBytesOut: 0,
      diskReads: 0,
      diskWrites: 0,
      diskReadRate: 0,
      diskWriteRate: 0,
      user: "tester"
    )
  }
}

private final class StubProcessProvider: ProcessDataProviding, @unchecked Sendable {
  private let batches: [[SystemProcessInfo]]
  private var index = 0

  init(batches: [[SystemProcessInfo]]) {
    self.batches = batches
  }

  func getProcesses(sortBy: ProcessSortKey, limit: Int) async -> [SystemProcessInfo] {
    guard !batches.isEmpty else { return [] }
    let batch = batches[min(index, batches.count - 1)]
    index += 1
    return Array(batch.prefix(limit))
  }

  func killProcess(_ pid: pid_t) throws {
  }
}
