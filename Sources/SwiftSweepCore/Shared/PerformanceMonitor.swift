import Foundation

// MARK: - Operation Outcome

/// 操作结果（Sendable 安全，使用 String 存储错误信息）
public enum OperationOutcome: Sendable, Equatable {
  case success
  case cancelled
  case failed(message: String)
  case timeout
}

// MARK: - Operation Metrics

/// 操作指标（使用单调时钟）
public struct OperationMetrics: Sendable {
  public let operationName: String
  public let startTicks: UInt64
  public let endTicks: UInt64
  public let durationNanos: UInt64
  public let itemsProcessed: Int
  public let bytesProcessed: Int64
  public let outcome: OperationOutcome

  public var durationSeconds: Double {
    Double(durationNanos) / 1_000_000_000
  }

  public init(
    operationName: String,
    startTicks: UInt64,
    endTicks: UInt64,
    durationNanos: UInt64,
    itemsProcessed: Int = 0,
    bytesProcessed: Int64 = 0,
    outcome: OperationOutcome
  ) {
    self.operationName = operationName
    self.startTicks = startTicks
    self.endTicks = endTicks
    self.durationNanos = durationNanos
    self.itemsProcessed = itemsProcessed
    self.bytesProcessed = bytesProcessed
    self.outcome = outcome
  }
}

// MARK: - Aggregated Stats

/// 聚合统计
public struct AggregatedStats: Sendable {
  public let operationName: String
  public let count: Int
  public let successCount: Int
  public let avgDurationSeconds: Double
  public let p95DurationSeconds: Double
  public let totalItems: Int
  public let totalBytes: Int64
}

// MARK: - Performance Monitor

/// 性能监控器 Actor
public actor PerformanceMonitor {
  public static let shared = PerformanceMonitor()

  private var metrics: [OperationMetrics] = []
  private let maxStoredMetrics: Int

  public init(maxStoredMetrics: Int = 1000) {
    self.maxStoredMetrics = maxStoredMetrics
  }

  // MARK: - Track Wrapper

  /// 包装函数，自动记录操作指标（保证收尾）
  public func track<T: Sendable>(
    _ name: String,
    operation: @Sendable () async throws -> T
  ) async rethrows -> T {
    let start = mach_absolute_time()

    do {
      let result = try await operation()
      let end = mach_absolute_time()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          outcome: .success
        ))
      return result
    } catch is CancellationError {
      let end = mach_absolute_time()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          outcome: .cancelled
        ))
      throw CancellationError()
    } catch {
      let end = mach_absolute_time()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          outcome: .failed(message: error.localizedDescription)
        ))
      throw error
    }
  }

  /// 用于线程安全累加的辅助 actor
  public actor MetricsAccumulator {
    var items: Int = 0
    var bytes: Int64 = 0

    func addItems(_ count: Int) { items += count }
    func addBytes(_ size: Int64) { bytes += size }
    func snapshot() -> (items: Int, bytes: Int64) { (items, bytes) }
  }

  /// 带计数的 track 包装（返回累加器供操作内调用）
  public func trackWithMetrics<T: Sendable>(
    _ name: String,
    operation: @Sendable (MetricsAccumulator) async throws -> T
  ) async rethrows -> T {
    let start = mach_absolute_time()
    let accumulator = MetricsAccumulator()

    do {
      let result = try await operation(accumulator)
      let end = mach_absolute_time()
      let snapshot = await accumulator.snapshot()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          itemsProcessed: snapshot.items,
          bytesProcessed: snapshot.bytes,
          outcome: .success
        ))
      return result
    } catch is CancellationError {
      let end = mach_absolute_time()
      let snapshot = await accumulator.snapshot()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          itemsProcessed: snapshot.items,
          bytesProcessed: snapshot.bytes,
          outcome: .cancelled
        ))
      throw CancellationError()
    } catch {
      let end = mach_absolute_time()
      let snapshot = await accumulator.snapshot()
      record(
        OperationMetrics(
          operationName: name,
          startTicks: start,
          endTicks: end,
          durationNanos: ticksToNanos(end - start),
          itemsProcessed: snapshot.items,
          bytesProcessed: snapshot.bytes,
          outcome: .failed(message: error.localizedDescription)
        ))
      throw error
    }
  }

  // MARK: - Record & Query

  public func record(_ metric: OperationMetrics) {
    metrics.append(metric)
    if metrics.count > maxStoredMetrics {
      metrics.removeFirst(metrics.count - maxStoredMetrics)
    }
  }

  public func snapshot(limit: Int = 100) -> [OperationMetrics] {
    Array(metrics.suffix(limit))
  }

  public func clear() {
    metrics.removeAll()
  }

  // MARK: - Aggregation

  public func aggregatedStats() -> [String: AggregatedStats] {
    var grouped: [String: [OperationMetrics]] = [:]
    for m in metrics {
      grouped[m.operationName, default: []].append(m)
    }

    var result: [String: AggregatedStats] = [:]
    for (name, list) in grouped {
      let sorted = list.map { $0.durationSeconds }.sorted()
      let p95Index = Int(Double(sorted.count) * 0.95)
      let p95 = sorted.isEmpty ? 0 : sorted[min(p95Index, sorted.count - 1)]

      result[name] = AggregatedStats(
        operationName: name,
        count: list.count,
        successCount: list.filter { $0.outcome == .success }.count,
        avgDurationSeconds: sorted.reduce(0, +) / Double(max(list.count, 1)),
        p95DurationSeconds: p95,
        totalItems: list.map { $0.itemsProcessed }.reduce(0, +),
        totalBytes: list.map { $0.bytesProcessed }.reduce(0, +)
      )
    }
    return result
  }

  // MARK: - Private Helpers

  private func ticksToNanos(_ ticks: UInt64) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return ticks * UInt64(info.numer) / UInt64(info.denom)
  }
}
