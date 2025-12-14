import XCTest
@testable import AppInventoryLogic

final class CacheStoreTests: XCTestCase {
    
    var defaults: UserDefaults!
    var cacheStore: CacheStore!
    
    override func setUp() {
        super.setUp()
        // Use a unique suite for each test to avoid data leakage
        let suiteName = "test.cachestore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        cacheStore = CacheStore(defaults: defaults)
    }
    
    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }
    
    // MARK: - Basic Operations
    
    func testSetAndGetMetadata() {
        let appID = "com.test.app"
        let metadata = CachedAppMetadata(
            sizeBytes: 1_000_000,
            scannedAt: Date(),
            bundleVersion: "1.0.0",
            bundleMTime: Date()
        )
        
        cacheStore.setMetadata(metadata, for: appID)
        let retrieved = cacheStore.getMetadata(for: appID)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.sizeBytes, 1_000_000)
        XCTAssertEqual(retrieved?.bundleVersion, "1.0.0")
    }
    
    func testGetNonExistentMetadata() {
        let retrieved = cacheStore.getMetadata(for: "com.nonexistent.app")
        XCTAssertNil(retrieved)
    }
    
    // MARK: - Validation
    
    func testCacheValidWhenVersionAndMTimeMatch() {
        let mtime = Date()
        let cached = CachedAppMetadata(
            sizeBytes: 500_000,
            scannedAt: Date().addingTimeInterval(-86400),
            bundleVersion: "2.0.0",
            bundleMTime: mtime
        )
        
        let isValid = cacheStore.isValid(
            cached: cached,
            currentVersion: "2.0.0",
            currentMTime: mtime
        )
        
        XCTAssertTrue(isValid)
    }
    
    func testCacheInvalidWhenVersionChanges() {
        let mtime = Date()
        let cached = CachedAppMetadata(
            sizeBytes: 500_000,
            scannedAt: Date().addingTimeInterval(-86400),
            bundleVersion: "1.0.0",
            bundleMTime: mtime
        )
        
        let isValid = cacheStore.isValid(
            cached: cached,
            currentVersion: "2.0.0", // Version changed
            currentMTime: mtime
        )
        
        XCTAssertFalse(isValid)
    }
    
    func testCacheInvalidWhenMTimeChanges() {
        let cached = CachedAppMetadata(
            sizeBytes: 500_000,
            scannedAt: Date().addingTimeInterval(-86400),
            bundleVersion: "1.0.0",
            bundleMTime: Date().addingTimeInterval(-1000)
        )
        
        let isValid = cacheStore.isValid(
            cached: cached,
            currentVersion: "1.0.0",
            currentMTime: Date() // mtime changed
        )
        
        XCTAssertFalse(isValid)
    }
    
    func testCacheInvalidWhenMTimeIsNil() {
        let cached = CachedAppMetadata(
            sizeBytes: 500_000,
            scannedAt: Date(),
            bundleVersion: "1.0.0",
            bundleMTime: Date()
        )
        
        let isValid = cacheStore.isValid(
            cached: cached,
            currentVersion: "1.0.0",
            currentMTime: nil // No mtime available
        )
        
        XCTAssertFalse(isValid)
    }
    
    // MARK: - Clear Cache
    
    func testClearAll() {
        let metadata = CachedAppMetadata(
            sizeBytes: 100_000,
            scannedAt: Date(),
            bundleVersion: "1.0",
            bundleMTime: Date()
        )
        
        cacheStore.setMetadata(metadata, for: "app1")
        cacheStore.setMetadata(metadata, for: "app2")
        
        cacheStore.clearAll()
        
        XCTAssertNil(cacheStore.getMetadata(for: "app1"))
        XCTAssertNil(cacheStore.getMetadata(for: "app2"))
    }
}
