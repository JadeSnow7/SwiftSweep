import Foundation

// MARK: - Scheduler Priority

/// 调度优先级（避免与 Swift.TaskPriority 冲突）
public enum SchedulerPriority: Int, Sendable, Comparable {
  case low = 0
  case normal = 1
  case high = 2
  case critical = 3

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

// MARK: - Scheduler Config

/// 调度器配置
public struct SchedulerConfig: Sendable {
  /// 最大并发数
  public var maxConcurrency: Int
  /// 单任务超时时间（秒）
  public var taskTimeoutSeconds: TimeInterval
  /// 队列最大容量（背压控制）
  public var maxQueueSize: Int

  public init(
    maxConcurrency: Int = 4,
    taskTimeoutSeconds: TimeInterval = 30,
    maxQueueSize: Int = 100
  ) {
    self.maxConcurrency = maxConcurrency
    self.taskTimeoutSeconds = taskTimeoutSeconds
    self.maxQueueSize = maxQueueSize
  }

  public static var `default`: SchedulerConfig {
    .init(maxConcurrency: 4, taskTimeoutSeconds: 30, maxQueueSize: 100)
  }

  public static var aggressive: SchedulerConfig {
    .init(maxConcurrency: 8, taskTimeoutSeconds: 60, maxQueueSize: 200)
  }

  public static var conservative: SchedulerConfig {
    .init(maxConcurrency: 2, taskTimeoutSeconds: 15, maxQueueSize: 50)
  }
}

// MARK: - Scheduler Status

/// 调度器状态
public struct SchedulerStatus: Sendable {
  public let runningCount: Int
  public let pendingCount: Int
  public let config: SchedulerConfig
}

// MARK: - Scheduler Error

/// 调度器错误
public enum SchedulerError: Error, Sendable {
  case queueFull
  case timeout
}

// MARK: - Concurrent Scheduler

/// 并发调度器 Actor
public actor ConcurrentScheduler {
  public static let shared = ConcurrentScheduler()

  private var config: SchedulerConfig
  private var runningCount: Int = 0
  private var pendingCount: Int = 0

  public init(config: SchedulerConfig = .default) {
    self.config = config
  }

  // MARK: - Schedule Single Task

  /// 调度单个任务（带超时和并发限制）
  public func schedule<T: Sendable>(
    priority: SchedulerPriority = .normal,
    operation: @Sendable @escaping () async throws -> T
  ) async throws -> T {
    // 背压控制：检查队列是否已满
    guard pendingCount + runningCount < config.maxQueueSize else {
      throw SchedulerError.queueFull
    }

    pendingCount += 1
    defer { pendingCount -= 1 }

    // 等待并发槽可用
    while runningCount >= config.maxConcurrency {
      try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
      if Task.isCancelled { throw CancellationError() }
    }

    runningCount += 1

    do {
      // 超时包装
      let result = try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
          try await operation()
        }
        group.addTask {
          try await Task.sleep(
            nanoseconds: UInt64(self.config.taskTimeoutSeconds * 1_000_000_000))
          throw SchedulerError.timeout
        }

        guard let result = try await group.next() else {
          throw SchedulerError.timeout
        }
        group.cancelAll()  // 取消超时任务
        return result
      }

      runningCount -= 1
      return result
    } catch {
      runningCount -= 1
      throw error
    }
  }

  // MARK: - Map Concurrently

  /// 批量并发处理（保持输入顺序，任一失败则整体失败）
  public func mapConcurrently<T: Sendable, R: Sendable>(
    _ items: [T],
    priority: SchedulerPriority = .normal,
    transform: @Sendable @escaping (T) async throws -> R
  ) async throws -> [R] {
    guard !items.isEmpty else { return [] }

    // 使用信号量控制并发
    return try await withThrowingTaskGroup(of: (Int, R).self) { group in
      var results: [(Int, R)] = []
      results.reserveCapacity(items.count)

      var activeCount = 0
      var nextIndex = 0

      // 添加初始批次
      while nextIndex < items.count && activeCount < config.maxConcurrency {
        let index = nextIndex
        let item = items[index]
        group.addTask {
          let result = try await transform(item)
          return (index, result)
        }
        activeCount += 1
        nextIndex += 1
      }

      // 收集结果并添加新任务
      for try await result in group {
        results.append(result)
        activeCount -= 1

        // 如果还有待处理的项，添加新任务
        if nextIndex < items.count {
          let index = nextIndex
          let item = items[index]
          group.addTask {
            let result = try await transform(item)
            return (index, result)
          }
          activeCount += 1
          nextIndex += 1
        }
      }

      // 按原始顺序返回
      return results.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
  }

  // MARK: - Status & Config

  public func status() -> SchedulerStatus {
    SchedulerStatus(
      runningCount: runningCount,
      pendingCount: pendingCount,
      config: config
    )
  }

  public func updateConfig(_ newConfig: SchedulerConfig) {
    config = newConfig
  }

  public func currentConfig() -> SchedulerConfig {
    config
  }
}
