import XCTest
@testable import AppInventoryLogic

final class SmartFiltersTests: XCTestCase {
    
    // MARK: - Test Data
    
    func makeApp(
        id: String,
        estimatedSize: Int64? = nil,
        accurateSize: Int64? = nil,
        lastUsed: Date? = nil,
        contentModified: Date? = nil
    ) -> AppItem {
        AppItem(
            id: id,
            url: URL(fileURLWithPath: "/Applications/\(id).app"),
            displayName: id,
            version: "1.0.0",
            estimatedSizeBytes: estimatedSize,
            lastUsedDate: lastUsed,
            contentModifiedDate: contentModified,
            accurateSizeBytes: accurateSize,
            source: .spotlight
        )
    }
    
    // MARK: - Large Apps
    
    func testLargeAppsFiltersBySize() {
        let apps = [
            makeApp(id: "small", accurateSize: 100_000_000), // 100MB
            makeApp(id: "large", accurateSize: 600_000_000), // 600MB
            makeApp(id: "medium", estimatedSize: 400_000_000), // 400MB (no accurate)
        ]
        
        let result = SmartFilters.largeApps(apps)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "large")
    }
    
    func testLargeAppsFallsBackToEstimated() {
        let apps = [
            makeApp(id: "noSize"),
            makeApp(id: "estimatedLarge", estimatedSize: 700_000_000),
        ]
        
        let result = SmartFilters.largeApps(apps)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "estimatedLarge")
    }
    
    // MARK: - Unused Apps
    
    func testUnusedAppsFiltersOldApps() {
        let now = Date()
        let apps = [
            makeApp(id: "recent", lastUsed: now.addingTimeInterval(-86400 * 30)), // 30 days
            makeApp(id: "unused", lastUsed: now.addingTimeInterval(-86400 * 120)), // 120 days
            makeApp(id: "neverUsed"), // nil lastUsed, should be excluded
        ]
        
        let result = SmartFilters.unusedApps(apps)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "unused")
    }
    
    func testUnusedAppsExcludesNilLastUsed() {
        let apps = [
            makeApp(id: "noData"),
            makeApp(id: "alsoNoData"),
        ]
        
        let result = SmartFilters.unusedApps(apps)
        
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Recently Updated
    
    func testRecentlyUpdatedFiltersRecentApps() {
        let now = Date()
        let apps = [
            makeApp(id: "recent", contentModified: now.addingTimeInterval(-86400 * 5)), // 5 days
            makeApp(id: "old", contentModified: now.addingTimeInterval(-86400 * 60)), // 60 days
        ]
        
        let result = SmartFilters.recentlyUpdated(apps)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "recent")
    }
    
    // MARK: - Uncategorized
    
    func testUncategorizedFiltersAppsWithoutCategory() {
        let catID = UUID()
        let apps = [
            makeApp(id: "categorized"),
            makeApp(id: "uncategorized"),
        ]
        let assignments = ["categorized": catID]
        
        let result = SmartFilters.uncategorized(apps, assignments: assignments)
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "uncategorized")
    }
}
