import Foundation

// MARK: - I/O Event Ring Buffer

/// 有界环形缓冲区，用于高性能事件存储
/// 防止内存无限增长，支持采样率控制
public actor IOEventBuffer {
  private var buffer: [IOEvent]
  private var head: Int = 0
  private var count: Int = 0
  private let capacity: Int

  /// 采样率 (0.0 - 1.0)
  private var sampleRate: Double = 1.0
  private var sampleCounter: UInt64 = 0

  /// 统计
  private var totalAppended: UInt64 = 0
  private var totalDropped: UInt64 = 0

  public init(capacity: Int = 10_000) {
    self.capacity = capacity
    self.buffer = Array(repeating: IOEvent.empty, count: capacity)
  }

  // MARK: - Append

  /// 追加事件（采样 + 丢弃策略）
  public func append(_ event: IOEvent) {
    totalAppended += 1

    // 采样控制
    if sampleRate < 1.0 {
      sampleCounter += 1
      // 使用哈希实现伪随机采样
      let hash = sampleCounter &* 2_654_435_761  // Knuth 乘法哈希
      let threshold = UInt64(sampleRate * Double(UInt64.max))
      if hash > threshold {
        totalDropped += 1
        return  // 丢弃
      }
    }

    // 环形覆盖
    let index = (head + count) % capacity
    buffer[index] = event

    if count < capacity {
      count += 1
    } else {
      head = (head + 1) % capacity  // 覆盖最旧
      totalDropped += 1
    }
  }

  // MARK: - Drain

  /// 批量获取（消费）
  public func drain(maxCount: Int = 1000) -> [IOEvent] {
    let toTake = min(maxCount, count)
    var result: [IOEvent] = []
    result.reserveCapacity(toTake)

    for _ in 0..<toTake {
      result.append(buffer[head])
      head = (head + 1) % capacity
      count -= 1
    }

    return result
  }

  /// 获取但不消费
  public func peek(maxCount: Int = 100) -> [IOEvent] {
    let toTake = min(maxCount, count)
    var result: [IOEvent] = []
    result.reserveCapacity(toTake)

    for i in 0..<toTake {
      let index = (head + i) % capacity
      result.append(buffer[index])
    }

    return result
  }

  // MARK: - Configuration

  /// 动态调整采样率
  public func setSampleRate(_ rate: Double) {
    sampleRate = max(0.0, min(1.0, rate))
  }

  public func getSampleRate() -> Double {
    sampleRate
  }

  // MARK: - Stats

  public func stats() -> BufferStats {
    BufferStats(
      capacity: capacity,
      count: count,
      totalAppended: totalAppended,
      totalDropped: totalDropped,
      sampleRate: sampleRate
    )
  }

  public func clear() {
    head = 0
    count = 0
  }

  public struct BufferStats: Sendable {
    public let capacity: Int
    public let count: Int
    public let totalAppended: UInt64
    public let totalDropped: UInt64
    public let sampleRate: Double

    public var dropRate: Double {
      totalAppended > 0 ? Double(totalDropped) / Double(totalAppended) : 0
    }
  }
}
