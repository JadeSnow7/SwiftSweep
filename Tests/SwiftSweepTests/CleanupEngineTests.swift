import XCTest
@testable import SwiftSweepCore

final class CleanupEngineTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Mocks
    
    final class MockPrivilegedDeleter: PrivilegedDeleting, @unchecked Sendable {
        var deleteCalled = false
        var lastDeletedURL: URL?
        var shouldSucceed: Bool = true
        var simulateRealDeletion: Bool = false
        
        func deleteItem(at url: URL) async throws {
            deleteCalled = true
            lastDeletedURL = url
            
            if !shouldSucceed {
                throw NSError(domain: "MockError", code: -1, userInfo: nil)
            }
            
            if simulateRealDeletion {
                // Forcefully delete the file to satisfy Engin's check
                // In real life, this happens via XPC. Here we cheat by chmod-ing back.
                let path = url.path
                if FileManager.default.fileExists(atPath: path) {
                    // Try to make parent writable if possible? 
                    // Actually, for this mock to work in user space, we might just assume
                    // the file is deletable by us, but we pretend it wasn't earlier.
                    // Or for the "permission denied" test, we actually rely on chmod.
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        
        func status() async -> PrivilegedHelperStatus {
            return .available
        }
    }
    
    // MARK: - Tests
    
    func testStandardDeletion() async throws {
        // Given
        let fileURL = tempDir.appendingPathComponent("test.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let engine = CleanupEngine() // No mock needed for standard
        let item = CleanupEngine.CleanupItem(
            name: "test.txt",
            path: fileURL.path,
            size: 100,
            itemCount: 1,
            category: .userCache
        )
        
        // When
        let result = try await engine.performCleanup(items: [item], dryRun: false)
        
        // Then
        XCTAssertEqual(result, 100)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    func testPrivilegedEscalationRejectedByAllowlist() async throws {
        // Given: A file in a read-only directory OUTSIDE the allowlist
        // This tests that Engine pre-check rejects paths not in /Library/Logs or /Library/Caches
        let subDir = tempDir.appendingPathComponent("ReadOnly")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let fileURL = subDir.appendingPathComponent("protected.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Make parent read-only to trigger permission error
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: subDir.path)
        
        let mockDeleter = MockPrivilegedDeleter()
        let engine = CleanupEngine(privilegedDeleter: mockDeleter)
        
        let item = CleanupEngine.CleanupItem(
            name: "protected.txt",
            path: fileURL.path,
            size: 200,
            itemCount: 1,
            category: .systemCache
        )
        
        // When
        let results = await engine.performRobustCleanup(items: [item], dryRun: false)
        
        // Clean up permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: subDir.path)
        
        // Then: Should fail with allowlist rejection, Helper NOT called
        guard let result = results.first else {
            XCTFail("No result returned")
            return
        }
        
        XCTAssertFalse(mockDeleter.deleteCalled, "Helper should NOT be called for paths outside allowlist")
        if case .failed(let reason) = result.outcome {
            XCTAssertTrue(reason.contains("not in allowed list"), "Should mention allowlist: \(reason)")
        } else {
            XCTFail("Expected failed outcome, got \(result.outcome)")
        }
    }
    
    func testDryRun() async throws {
        // Given
        let fileURL = tempDir.appendingPathComponent("dry.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let engine = CleanupEngine()
        let item = CleanupEngine.CleanupItem(
            name: "dry.txt",
            path: fileURL.path,
            size: 50,
            itemCount: 1,
            category: .logs
        )
        
        // When
        let results = await engine.performRobustCleanup(items: [item], dryRun: true)
        
        // Then
        XCTAssertEqual(results.first?.outcome, .skippedDryRun)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
}

// Helper for Equatable comparison of Outcome if needed or just switch match
extension CleanupEngine.CleanupResultItem.Outcome: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.deleted, .deleted): return true
        case (.deletedPrivileged, .deletedPrivileged): return true
        case (.skippedDryRun, .skippedDryRun): return true
        case (.failed(let r1), .failed(let r2)): return r1 == r2
        default: return false
        }
    }
}
