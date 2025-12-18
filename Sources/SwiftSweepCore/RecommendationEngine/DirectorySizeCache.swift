import Foundation

// MARK: - DirectorySizeCache

/// Caches directory size calculations to avoid redundant file system operations.
/// I/O operations run outside actor isolation to allow parallel execution.
public actor DirectorySizeCache {
  public static let shared = DirectorySizeCache()

  private var cache: [String: CachedSize] = [:]
  private var inFlight: [String: Task<(Int64, Int), Never>] = [:]
  private let cacheTTL: TimeInterval = 60  // 1 minute TTL

  private struct CachedSize {
    let size: Int64
    let timestamp: Date
    let fileCount: Int
  }

  private init() {}

  /// Get cached size or calculate and cache
  public func size(for path: String) async -> Int64 {
    // Check cache
    if let cached = cache[path] {
      if Date().timeIntervalSince(cached.timestamp) < cacheTTL {
        return cached.size
      }
    }

    // Check if already in flight
    if let task = inFlight[path] {
      let (size, _) = await task.value
      return size
    }

    // Start calculation outside actor (non-isolated)
    let task = Task.detached { () -> (Int64, Int) in
      DirectorySizeCalculator.calculateSize(at: path)
    }
    inFlight[path] = task

    let (size, count) = await task.value

    // Update cache and remove from in-flight
    cache[path] = CachedSize(size: size, timestamp: Date(), fileCount: count)
    inFlight.removeValue(forKey: path)

    return size
  }

  /// Invalidate cache for a path
  public func invalidate(path: String) {
    cache.removeValue(forKey: path)
  }

  /// Clear all cache
  public func clearAll() {
    cache.removeAll()
  }
}

// MARK: - Non-isolated Size Calculator

/// Performs directory size calculation outside actor isolation for parallel I/O
public enum DirectorySizeCalculator {
  /// Calculate total size and file count for a directory (runs on calling thread)
  public static func calculateSize(at path: String) -> (Int64, Int) {
    let url = URL(fileURLWithPath: path)
    let fm = FileManager.default
    var totalSize: Int64 = 0
    var fileCount = 0

    guard
      let enumerator = fm.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return (0, 0)
    }

    for case let fileURL as URL in enumerator {
      if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
        values.isDirectory != true,
        let size = values.fileSize
      {
        totalSize += Int64(size)
        fileCount += 1
      }
    }

    return (totalSize, fileCount)
  }
}

// MARK: - Quick Size Estimation

extension DirectorySizeCache {
  /// Quick size estimate using file system attributes (less accurate but faster)
  public nonisolated func quickSize(for path: String) -> Int64? {
    let url = URL(fileURLWithPath: path)

    // Try to get directory size from resource values
    if let values = try? url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey]),
      let size = values.totalFileSize ?? values.fileSize
    {
      return Int64(size)
    }

    return nil
  }
}

// MARK: - Concurrent Directory Scanner

public actor ConcurrentDirectoryScanner {
  public static let shared = ConcurrentDirectoryScanner()

  private init() {}

  /// Scan multiple directories concurrently (up to maxConcurrent at a time)
  public func scanDirectories(_ paths: [String], maxConcurrent: Int = 4) async -> [String: Int64] {
    await withTaskGroup(of: (String, Int64).self, returning: [String: Int64].self) { group in
      for path in paths.prefix(maxConcurrent) {
        group.addTask {
          let size = await DirectorySizeCache.shared.size(for: path)
          return (path, size)
        }
      }

      var results: [String: Int64] = [:]
      var pendingPaths = Array(paths.dropFirst(maxConcurrent))

      for await (path, size) in group {
        results[path] = size

        // Add next pending path
        if let nextPath = pendingPaths.first {
          pendingPaths.removeFirst()
          group.addTask {
            let size = await DirectorySizeCache.shared.size(for: nextPath)
            return (nextPath, size)
          }
        }
      }

      return results
    }
  }
}
