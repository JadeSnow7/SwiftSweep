import Foundation

#if canImport(SwiftSweepCore)
  // DirectorySizeCalculator is already imported via SwiftSweepCore
#endif

/// Helper for calculating package sizes
public enum PackageSizeCalculator {

  /// Calculate size for a package using its install path
  /// Returns nil if path is invalid or calculation fails
  public static func calculateSize(for package: Package) async -> Int64? {
    guard let path = package.installPath else { return nil }

    // Use existing DirectorySizeCalculator for consistency
    let (size, _) = await Task.detached {
      DirectorySizeCalculator.calculateSize(at: path)
    }.value

    return size > 0 ? size : nil
  }

  /// Calculate sizes for multiple packages concurrently
  /// - Parameter packages: Array of packages to calculate sizes for
  /// - Parameter maxConcurrent: Maximum number of concurrent calculations (default: 4)
  /// - Returns: Dictionary mapping package ID to calculated size
  public static func calculateSizes(
    for packages: [Package],
    maxConcurrent: Int = 4
  ) async -> [String: Int64] {
    await withTaskGroup(of: (String, Int64?).self) { group in
      var results: [String: Int64] = [:]
      var packagesWithPath = packages.filter { $0.installPath != nil }

      // Start initial batch
      for package in packagesWithPath.prefix(maxConcurrent) {
        group.addTask {
          let size = await calculateSize(for: package)
          return (package.id, size)
        }
      }

      var pendingPackages = Array(packagesWithPath.dropFirst(maxConcurrent))

      for await (id, size) in group {
        if let size = size {
          results[id] = size
        }

        // Add next pending package
        if let nextPackage = pendingPackages.first {
          pendingPackages.removeFirst()
          group.addTask {
            let size = await calculateSize(for: nextPackage)
            return (nextPackage.id, size)
          }
        }
      }

      return results
    }
  }

  /// Calculate size with caching (uses shared DirectorySizeCache)
  public static func calculateSizeWithCache(for package: Package) async -> Int64? {
    guard let path = package.installPath else { return nil }
    return await DirectorySizeCache.shared.size(for: path)
  }
}
