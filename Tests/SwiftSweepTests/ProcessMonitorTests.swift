import XCTest

@testable import SwiftSweepCore

final class ProcessMonitorTests: XCTestCase {

  // MARK: - Process List Tests

  func testGetProcessList() async throws {
    // Given
    let monitor = ProcessMonitor.shared

    // When
    let processes = await monitor.getProcesses(sortBy: .cpu, limit: 10)

    // Then
    XCTAssertFalse(processes.isEmpty, "Should return at least some processes")
    XCTAssertLessThanOrEqual(processes.count, 10, "Should respect limit parameter")

    print("Found \(processes.count) processes")
    for proc in processes.prefix(5) {
      print(
        "- [\(proc.id)] \(proc.name): CPU \(String(format: "%.1f", proc.cpuUsage))%, Mem \(proc.memoryUsage) bytes"
      )
    }
  }

  func testProcessHasValidData() async throws {
    // Given
    let monitor = ProcessMonitor.shared

    // When
    let processes = await monitor.getProcesses(sortBy: .memory, limit: 5)

    // Then
    guard let first = processes.first else {
      XCTFail("Should have at least one process")
      return
    }

    XCTAssertGreaterThan(first.id, 0, "PID should be positive")
    XCTAssertFalse(first.name.isEmpty, "Process name should not be empty")
    XCTAssertGreaterThanOrEqual(first.cpuUsage, 0, "CPU usage should be non-negative")
    XCTAssertGreaterThanOrEqual(first.memoryUsage, 0, "Memory usage should be non-negative")
    XCTAssertFalse(first.user.isEmpty, "User should not be empty")
  }

  func testSortByCPU() async throws {
    // Given
    let monitor = ProcessMonitor.shared

    // When
    let processes = await monitor.getProcesses(sortBy: .cpu, limit: 10)

    // Then
    for i in 0..<(processes.count - 1) {
      XCTAssertGreaterThanOrEqual(
        processes[i].cpuUsage,
        processes[i + 1].cpuUsage,
        "Processes should be sorted by CPU descending"
      )
    }
  }

  func testSortByMemory() async throws {
    // Given
    let monitor = ProcessMonitor.shared

    // When
    let processes = await monitor.getProcesses(sortBy: .memory, limit: 10)

    // Then
    for i in 0..<(processes.count - 1) {
      XCTAssertGreaterThanOrEqual(
        processes[i].memoryUsage,
        processes[i + 1].memoryUsage,
        "Processes should be sorted by memory descending"
      )
    }
  }

  func testSortByName() async throws {
    // Given
    let monitor = ProcessMonitor.shared

    // When
    let processes = await monitor.getProcesses(sortBy: .name, limit: 10)

    // Then
    for i in 0..<(processes.count - 1) {
      let comparison = processes[i].name.localizedCaseInsensitiveCompare(processes[i + 1].name)
      XCTAssertTrue(
        comparison == .orderedAscending || comparison == .orderedSame,
        "Processes should be sorted by name ascending"
      )
    }
  }
}
