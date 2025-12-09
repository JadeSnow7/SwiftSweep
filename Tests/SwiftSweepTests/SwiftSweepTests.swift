import XCTest
@testable import SwiftSweepCore

final class SwiftSweepTests: XCTestCase {
    
    // MARK: - SystemMonitor Tests
    func testSystemMetrics() async throws {
        let metrics = try await SystemMonitor.shared.getMetrics()
        
        print("CPU: \(metrics.cpuUsage)%")
        print("Memory: \(metrics.memoryUsed) / \(metrics.memoryTotal)")
        print("Disk: \(metrics.diskUsed) / \(metrics.diskTotal)")
        print("Network: ↓\(metrics.networkDownload) ↑\(metrics.networkUpload)")
        
        XCTAssertGreaterThanOrEqual(metrics.cpuUsage, 0)
        XCTAssertGreaterThan(metrics.memoryTotal, 0)
        XCTAssertGreaterThan(metrics.diskTotal, 0)
        
        // Battery might be 0 on some systems, so we just check it doesn't crash
        XCTAssertGreaterThanOrEqual(metrics.batteryLevel, 0)
    }
    
    // MARK: - CleanupEngine Tests
    func testCleanupScan() async throws {
        // This test scans real directories, so it might take a moment
        // It's strictly read-only scan
        let items = try await CleanupEngine.shared.scanForCleanableItems()
        
        print("Found \(items.count) cleanup items")
        for item in items.prefix(5) {
            print("- [\(item.category.rawValue)] \(item.name): \(item.size) bytes")
        }
        
        // We can't guarantee items are found on a clean system, so just ensure no crash
        // and that the array is returned
        XCTAssertNotNil(items)
        
        // If items are found, ensure basic integrity
        if let first = items.first {
            XCTAssertFalse(first.name.isEmpty)
            XCTAssertFalse(first.path.isEmpty)
            XCTAssertGreaterThanOrEqual(first.size, 0)
        }
    }
}
