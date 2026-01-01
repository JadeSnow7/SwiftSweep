import Foundation

// MARK: - I/O Aggregator

/// I/O 事件聚合器
/// 将原始事件聚合为时间片和路径统计
public actor IOAggregator {
  public static let shared = IOAggregator()

  private let tracer: IOSelfTracer
  private var timeSlices: [IOTimeSlice] = []
  private var pathStats: [String: MutablePathStats] = [:]
  private var aggregationTask: Task<Void, Never>?

  /// 最多保留的时间片数量
  private let maxTimeSlices = 300  // 5 分钟 @ 1秒/slice

  public init(tracer: IOSelfTracer = .shared) {
    self.tracer = tracer
  }

  // MARK: - Aggregation Control

  /// 开始聚合
  public func startAggregation(
    interval: TimeInterval = 1.0,
    onSlice: (@Sendable (IOTimeSlice) -> Void)? = nil
  ) {
    stopAggregation()

    aggregationTask = Task {
      var sliceStart = Date()

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

        // 批量获取事件
        let events = await tracer.drainEvents(maxCount: 5000)

        if !events.isEmpty {
          // 聚合为时间片
          let slice = aggregateToSlice(events: events, startTime: sliceStart, duration: interval)
          timeSlices.append(slice)

          // 限制保留数量
          if timeSlices.count > maxTimeSlices {
            timeSlices.removeFirst(timeSlices.count - maxTimeSlices)
          }

          // 更新路径统计
          updatePathStats(events: events)

          // 回调
          onSlice?(slice)
        }

        sliceStart = Date()
      }
    }
  }

  /// 停止聚合
  public func stopAggregation() {
    aggregationTask?.cancel()
    aggregationTask = nil
  }

  // MARK: - Data Access

  /// 获取时间片
  public func getTimeSlices(limit: Int = 60) -> [IOTimeSlice] {
    Array(timeSlices.suffix(limit))
  }

  /// 获取热点路径
  public func getTopPaths(limit: Int = 20) -> [IOPathStats] {
    pathStats.values
      .map { $0.toStats() }
      .sorted { $0.totalBytes > $1.totalBytes }
      .prefix(limit)
      .map { $0 }
  }

  /// 清除所有数据
  public func clear() {
    timeSlices.removeAll()
    pathStats.removeAll()
  }

  // MARK: - Private Helpers

  private func aggregateToSlice(
    events: [IOEvent],
    startTime: Date,
    duration: TimeInterval
  ) -> IOTimeSlice {
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
    var readOps = 0
    var writeOps = 0
    var latencies: [UInt64] = []

    for event in events {
      switch event.operation {
      case .read:
        readBytes += event.bytesTransferred
        readOps += 1
      case .write:
        writeBytes += event.bytesTransferred
        writeOps += 1
      default:
        break
      }

      if event.durationNanos > 0 {
        latencies.append(event.durationNanos)
      }
    }

    // 计算延迟统计
    let avgLatency: UInt64
    let p99Latency: UInt64

    if latencies.isEmpty {
      avgLatency = 0
      p99Latency = 0
    } else {
      avgLatency = latencies.reduce(0, +) / UInt64(latencies.count)
      let sorted = latencies.sorted()
      let p99Index = Int(Double(sorted.count) * 0.99)
      p99Latency = sorted[min(p99Index, sorted.count - 1)]
    }

    return IOTimeSlice(
      startTime: startTime,
      duration: duration,
      readBytes: readBytes,
      writeBytes: writeBytes,
      readOps: readOps,
      writeOps: writeOps,
      avgLatencyNanos: avgLatency,
      p99LatencyNanos: p99Latency
    )
  }

  private func updatePathStats(events: [IOEvent]) {
    for event in events {
      let path = event.path

      if pathStats[path] == nil {
        pathStats[path] = MutablePathStats(path: path)
      }

      pathStats[path]!.addEvent(event)
    }
  }

  // MARK: - Mutable Stats Helper

  private class MutablePathStats {
    let path: String
    var totalBytes: Int64 = 0
    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
    var operationCount: Int = 0
    var totalLatencyNanos: UInt64 = 0

    init(path: String) {
      self.path = path
    }

    func addEvent(_ event: IOEvent) {
      operationCount += 1
      totalBytes += event.bytesTransferred
      totalLatencyNanos += event.durationNanos

      switch event.operation {
      case .read:
        readBytes += event.bytesTransferred
      case .write:
        writeBytes += event.bytesTransferred
      default:
        break
      }
    }

    func toStats() -> IOPathStats {
      IOPathStats(
        path: path,
        totalBytes: totalBytes,
        readBytes: readBytes,
        writeBytes: writeBytes,
        operationCount: operationCount,
        avgLatencyNanos: operationCount > 0 ? totalLatencyNanos / UInt64(operationCount) : 0
      )
    }
  }
}
