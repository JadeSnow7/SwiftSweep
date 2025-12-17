import XCTest
@testable import SwiftSweepCore

final class HelperLatencyTests: XCTestCase {
    
    private var runner: ProcessRunner!
    
    override func setUp() {
        super.setUp()
        runner = ProcessRunner(config: .testing)
    }
    
    override func tearDown() {
        runner = nil
        super.tearDown()
    }
    
    // MARK: - Fixtures
    
    private var python3Available: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/python3")
    }
    
    // MARK: - Stdout Flood
    
    func testStdoutFlood() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // Generate 2MB of stdout (well over 256KB limit)
        let script = """
        import os
        chunk = b'a' * 65536
        for _ in range(32):
            os.write(1, chunk)
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        XCTAssertEqual(result.reason, .exit)
        XCTAssertTrue(result.stdoutTruncated, "stdout should be truncated")
        XCTAssertLessThanOrEqual(result.stdout.count, 256 * 1024, "stdout should not exceed maxOutputSize")
    }
    
    // MARK: - Stderr Flood
    
    func testStderrFlood() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        let script = """
        import os
        chunk = b'e' * 65536
        for _ in range(32):
            os.write(2, chunk)
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        XCTAssertEqual(result.reason, .exit)
        XCTAssertTrue(result.stderrTruncated, "stderr should be truncated")
        XCTAssertLessThanOrEqual(result.stderr.count, 256 * 1024, "stderr should not exceed maxOutputSize")
    }
    
    // MARK: - Dual Flood
    
    func testDualFlood() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // 1.5MB to each pipe
        let script = """
        import os
        chunk = b'x' * 65536
        for _ in range(24):
            os.write(1, chunk)
            os.write(2, chunk)
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        XCTAssertEqual(result.reason, .exit)
        XCTAssertTrue(result.stdoutTruncated, "stdout should be truncated")
        XCTAssertTrue(result.stderrTruncated, "stderr should be truncated")
        XCTAssertLessThanOrEqual(result.stdout.count, 256 * 1024)
        XCTAssertLessThanOrEqual(result.stderr.count, 256 * 1024)
    }
    
    // MARK: - Interleaved Flood
    
    func testInterleavedFlood() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // Rapid alternating writes
        let script = """
        import os
        for _ in range(10000):
            os.write(1, b'o')
            os.write(2, b'e')
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        XCTAssertEqual(result.reason, .exit)
        // Should complete without hanging
    }
    
    // MARK: - Infinite Flood with Timeout
    
    func testInfiniteFloodTimeout() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // Infinite output - will be killed by timeout
        let script = """
        import os
        while True:
            os.write(1, b'x' * 65536)
            os.write(2, b'y' * 65536)
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        XCTAssertEqual(result.reason, .timeout)
        XCTAssertTrue(result.outputMayBeIncomplete)
        XCTAssertLessThanOrEqual(result.stdout.count, 256 * 1024)
        XCTAssertLessThanOrEqual(result.stderr.count, 256 * 1024)
    }
    
    // MARK: - Stdin Block
    
    func testStdinBlock() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // This would block if stdin wasn't nullDevice
        let script = "input()"
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        // Should complete quickly (with error since stdin is null)
        XCTAssertEqual(result.reason, .exit)
        // Exit code may be non-zero (EOFError), that's fine
    }
    
    // MARK: - Timeout
    
    func testTimeout() async throws {
        // Use sleep which is always available
        let result = await runner.run(executable: "/bin/sleep", arguments: ["10"])
        
        XCTAssertEqual(result.reason, .timeout)
        XCTAssertTrue(result.outputMayBeIncomplete)
        XCTAssertNil(result.exitCode)
    }
    
    // MARK: - Start Failed
    
    func testStartFailed() async throws {
        let result = await runner.run(executable: "/nonexistent/path", arguments: [])
        
        XCTAssertEqual(result.reason, .startFailed)
    }
    
    // MARK: - Signal
    
    func testSignal() async throws {
        try XCTSkipUnless(python3Available, "python3 not available")
        
        // Process that sends itself SIGTERM
        let script = """
        import os, signal
        os.kill(os.getpid(), signal.SIGTERM)
        """
        
        let result = await runner.run(executable: "/usr/bin/python3", arguments: ["-u", "-c", script])
        
        if case .signal(let sig) = result.reason {
            XCTAssertEqual(sig, SIGTERM)
        } else {
            XCTFail("Expected .signal, got \(result.reason)")
        }
    }
    
    // MARK: - Concurrency
    
    func testConcurrency() async throws {
        // Run a long and short task concurrently
        // Short task should complete before long task
        
        actor CompletionTracker {
            var shortCompleted = false
            var longCompleted = false
            var shortCompletedFirst = false
            
            func markShort() {
                shortCompleted = true
                if !longCompleted {
                    shortCompletedFirst = true
                }
            }
            
            func markLong() {
                longCompleted = true
            }
            
            func getResults() -> (short: Bool, long: Bool, shortFirst: Bool) {
                (shortCompleted, longCompleted, shortCompletedFirst)
            }
        }
        
        let tracker = CompletionTracker()
        let longStarted = AsyncStream<Void>.makeStream()
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // Long task (will timeout at 5s)
                longStarted.continuation.yield()
                _ = await self.runner.run(executable: "/bin/sleep", arguments: ["3"])
                await tracker.markLong()
            }
            
            group.addTask {
                // Wait for long to start, then run short
                for await _ in longStarted.stream { break }
                _ = await self.runner.run(executable: "/bin/echo", arguments: ["hi"])
                await tracker.markShort()
            }
            
            await group.waitForAll()
        }
        
        let results = await tracker.getResults()
        XCTAssertTrue(results.short, "Short should complete")
        XCTAssertTrue(results.long, "Long should complete")
        XCTAssertTrue(results.shortFirst, "Short task should complete before long task")
    }
}
