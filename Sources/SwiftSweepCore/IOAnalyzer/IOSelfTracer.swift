import Foundation

// MARK: - I/O Self Tracer

/// 自身 I/O 追踪器
/// 无需特权，仅监控 SwiftSweep 自身的 I/O 操作
public actor IOSelfTracer {
  public static let shared = IOSelfTracer()

  private let buffer: IOEventBuffer
  private var isTracing = false
  private var tracingStartTime: Date?

  public init(bufferCapacity: Int = 10_000) {
    self.buffer = IOEventBuffer(capacity: bufferCapacity)
  }

  // MARK: - Tracing Control

  /// 开始追踪
  public func startTracing() {
    isTracing = true
    tracingStartTime = Date()
  }

  /// 停止追踪
  public func stopTracing() {
    isTracing = false
  }

  /// 是否正在追踪
  public func isActive() -> Bool {
    isTracing
  }

  // MARK: - Event Recording

  /// 记录 I/O 事件
  public func recordEvent(_ event: IOEvent) async {
    guard isTracing else { return }
    await buffer.append(event)
  }

  /// 记录读取操作
  public func recordRead(path: String, bytes: Int64, durationNanos: UInt64) async {
    guard isTracing else { return }
    await buffer.append(
      IOEvent(
        operation: .read,
        path: sanitizePath(path),
        bytesTransferred: bytes,
        durationNanos: durationNanos
      ))
  }

  /// 记录写入操作
  public func recordWrite(path: String, bytes: Int64, durationNanos: UInt64) async {
    guard isTracing else { return }
    await buffer.append(
      IOEvent(
        operation: .write,
        path: sanitizePath(path),
        bytesTransferred: bytes,
        durationNanos: durationNanos
      ))
  }

  /// 记录目录遍历
  public func recordReaddir(path: String, durationNanos: UInt64) async {
    guard isTracing else { return }
    await buffer.append(
      IOEvent(
        operation: .readdir,
        path: sanitizePath(path),
        durationNanos: durationNanos
      ))
  }

  /// 记录 stat 操作
  public func recordStat(path: String, durationNanos: UInt64) async {
    guard isTracing else { return }
    await buffer.append(
      IOEvent(
        operation: .stat,
        path: sanitizePath(path),
        durationNanos: durationNanos
      ))
  }

  // MARK: - Tracked Operations

  /// 追踪的文件读取
  public func trackedRead(at url: URL) async throws -> Data {
    let start = mach_absolute_time()
    let data = try Data(contentsOf: url)
    let end = mach_absolute_time()

    await recordRead(
      path: url.path,
      bytes: Int64(data.count),
      durationNanos: ticksToNanos(end - start)
    )

    return data
  }

  /// 追踪的文件写入
  public func trackedWrite(_ data: Data, to url: URL) async throws {
    let start = mach_absolute_time()
    try data.write(to: url)
    let end = mach_absolute_time()

    await recordWrite(
      path: url.path,
      bytes: Int64(data.count),
      durationNanos: ticksToNanos(end - start)
    )
  }

  /// 追踪的目录遍历
  public func trackedContents(at url: URL) async throws -> [URL] {
    let start = mach_absolute_time()
    let contents = try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil
    )
    let end = mach_absolute_time()

    await recordReaddir(
      path: url.path,
      durationNanos: ticksToNanos(end - start)
    )

    return contents
  }

  // MARK: - Buffer Access

  /// 获取事件（消费）
  public func drainEvents(maxCount: Int = 1000) async -> [IOEvent] {
    await buffer.drain(maxCount: maxCount)
  }

  /// 获取缓冲区统计
  public func bufferStats() async -> IOEventBuffer.BufferStats {
    await buffer.stats()
  }

  /// 设置采样率
  public func setSampleRate(_ rate: Double) async {
    await buffer.setSampleRate(rate)
  }

  /// 获取追踪时长
  public func tracingDuration() -> TimeInterval {
    guard let start = tracingStartTime else { return 0 }
    return Date().timeIntervalSince(start)
  }

  /// 清除缓冲区
  public func clear() async {
    await buffer.clear()
  }

  // MARK: - Private Helpers

  /// 路径脱敏（仅保留最后两级）
  private func sanitizePath(_ path: String) -> String {
    let components = path.split(separator: "/")
    if components.count > 2 {
      return ".../" + components.suffix(2).joined(separator: "/")
    }
    return path
  }

  private func ticksToNanos(_ ticks: UInt64) -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return ticks * UInt64(info.numer) / UInt64(info.denom)
  }
}
