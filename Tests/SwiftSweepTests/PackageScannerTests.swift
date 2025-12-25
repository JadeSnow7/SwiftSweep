import XCTest

@testable import SwiftSweepCore

final class PackageScannerTests: XCTestCase {

  // MARK: - ToolLocator Tests

  func testToolLocatorIncludesHomebrewPaths() {
    let paths = ToolLocator.searchPaths

    // Should include both Intel and Apple Silicon Homebrew paths
    XCTAssertTrue(paths.contains("/opt/homebrew/bin"), "Missing Apple Silicon Homebrew path")
    XCTAssertTrue(paths.contains("/usr/local/bin"), "Missing Intel Homebrew path")
  }

  func testToolLocatorIncludesCargoPath() {
    let home = NSHomeDirectory()
    let cargoPath = "\(home)/.cargo/bin"

    XCTAssertTrue(
      ToolLocator.searchPaths.contains(cargoPath),
      "ToolLocator should include Cargo path: \(cargoPath)"
    )
  }

  func testToolLocatorIncludesGoPath() {
    let home = NSHomeDirectory()
    let goPath = "\(home)/go/bin"

    XCTAssertTrue(
      ToolLocator.searchPaths.contains(goPath),
      "ToolLocator should include Go path: \(goPath)"
    )
  }

  func testToolLocatorIncludesComposerPath() {
    let home = NSHomeDirectory()
    let composerPath = "\(home)/.composer/vendor/bin"

    XCTAssertTrue(
      ToolLocator.searchPaths.contains(composerPath),
      "ToolLocator should include Composer path"
    )
  }

  func testToolLocatorPathCount() {
    // Should have significantly more paths than before (was 4, now 15+)
    XCTAssertGreaterThan(
      ToolLocator.searchPaths.count, 10,
      "ToolLocator should have at least 10 search paths"
    )
  }

  // MARK: - Package Model Tests

  func testPackageWithInstallPath() {
    let package = Package(
      name: "test-package",
      version: "1.2.3",
      providerID: "test",
      installPath: "/opt/test/package",
      size: 1024
    )

    XCTAssertEqual(package.name, "test-package")
    XCTAssertEqual(package.version, "1.2.3")
    XCTAssertEqual(package.providerID, "test")
    XCTAssertEqual(package.installPath, "/opt/test/package")
    XCTAssertEqual(package.size, 1024)
    XCTAssertEqual(package.id, "test_test-package")
  }

  func testPackageBackwardCompatibility() {
    // Old code using only name/version/providerID should still work
    let package = Package(
      name: "legacy",
      version: "1.0.0",
      providerID: "homebrew"
    )

    XCTAssertEqual(package.name, "legacy")
    XCTAssertEqual(package.version, "1.0.0")
    XCTAssertNil(package.installPath, "installPath should default to nil")
    XCTAssertNil(package.size, "size should default to nil")
  }

  func testPackageOptionalFields() {
    let package = Package(
      name: "test",
      version: "1.0.0",
      providerID: "npm",
      installPath: "/path/to/package"
        // size omitted
    )

    XCTAssertNotNil(package.installPath)
    XCTAssertNil(package.size)
  }

  // MARK: - PackageSizeCalculator Tests

  func testCalculateSizeWithNilPath() async {
    let package = Package(
      name: "no-path",
      version: "1.0.0",
      providerID: "test",
      installPath: nil
    )

    let size = await PackageSizeCalculator.calculateSize(for: package)
    XCTAssertNil(size, "Size should be nil when installPath is nil")
  }

  func testCalculateSizeWithInvalidPath() async {
    let package = Package(
      name: "invalid",
      version: "1.0.0",
      providerID: "test",
      installPath: "/this/path/does/not/exist/at/all"
    )

    let size = await PackageSizeCalculator.calculateSize(for: package)
    XCTAssertTrue(
      size == nil || size == 0,
      "Size should be nil or 0 for non-existent path"
    )
  }

  func testCalculateSizeWithValidPath() async throws {
    // Create a temporary directory with known content
    let tempDir = NSTemporaryDirectory() + "test_package_\(UUID().uuidString)"
    let fm = FileManager.default

    try fm.createDirectory(
      atPath: tempDir,
      withIntermediateDirectories: true
    )

    // Write a test file with known size
    let testContent = String(repeating: "x", count: 1024)  // 1KB
    let testFile = tempDir + "/test.txt"
    try testContent.write(toFile: testFile, atomically: true, encoding: .utf8)

    let package = Package(
      name: "test",
      version: "1.0.0",
      providerID: "test",
      installPath: tempDir
    )

    let size = await PackageSizeCalculator.calculateSize(for: package)

    XCTAssertNotNil(size, "Size should not be nil for valid path")
    XCTAssertGreaterThan(size ?? 0, 0, "Size should be greater than 0")
    XCTAssertGreaterThan(size ?? 0, 1000, "Size should be at least 1KB")

    // Cleanup
    try? fm.removeItem(atPath: tempDir)
  }

  func testCalculateSizesForMultiplePackages() async throws {
    let fm = FileManager.default
    let tempBase = NSTemporaryDirectory() + "test_multi_\(UUID().uuidString)"

    // Create multiple test directories
    var packages: [Package] = []
    for i in 1...3 {
      let path = "\(tempBase)/package\(i)"
      try fm.createDirectory(atPath: path, withIntermediateDirectories: true)

      let content = String(repeating: "x", count: i * 1024)
      try content.write(
        toFile: "\(path)/file.txt",
        atomically: true,
        encoding: .utf8
      )

      packages.append(
        Package(
          name: "pkg\(i)",
          version: "1.0.0",
          providerID: "test",
          installPath: path
        )
      )
    }

    let sizes = await PackageSizeCalculator.calculateSizes(for: packages, maxConcurrent: 2)

    XCTAssertEqual(sizes.count, 3, "Should calculate size for all 3 packages")

    for package in packages {
      XCTAssertNotNil(sizes[package.id], "Should have size for \(package.name)")
      XCTAssertGreaterThan(sizes[package.id] ?? 0, 0, "\(package.name) size should be > 0")
    }

    // Cleanup
    try? fm.removeItem(atPath: tempBase)
  }

  func testCalculateSizeWithCache() async throws {
    let tempDir = NSTemporaryDirectory() + "test_cache_\(UUID().uuidString)"
    let fm = FileManager.default

    try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    try "test".write(toFile: "\(tempDir)/test.txt", atomically: true, encoding: .utf8)

    let package = Package(
      name: "cached",
      version: "1.0.0",
      providerID: "test",
      installPath: tempDir
    )

    // First call - should calculate
    let start1 = Date()
    let size1 = await PackageSizeCalculator.calculateSizeWithCache(for: package)
    let duration1 = Date().timeIntervalSince(start1)

    // Second call - should hit cache
    let start2 = Date()
    let size2 = await PackageSizeCalculator.calculateSizeWithCache(for: package)
    let duration2 = Date().timeIntervalSince(start2)

    XCTAssertEqual(size1, size2, "Cached size should equal original")
    XCTAssertLessThan(duration2, duration1, "Cached call should be faster")

    // Cleanup
    try? fm.removeItem(atPath: tempDir)
  }

  // MARK: - Integration Tests

  func testPackageScanResultWithGitRepoCount() {
    let result = PackageScanResult(
      providerID: "test",
      displayName: "Test Provider",
      status: .ok,
      packages: [],
      scanDuration: 0.5
    )

    XCTAssertEqual(result.providerID, "test")
    XCTAssertEqual(result.status, .ok)
    XCTAssertEqual(result.scanDuration, 0.5, accuracy: 0.01)
  }
}
