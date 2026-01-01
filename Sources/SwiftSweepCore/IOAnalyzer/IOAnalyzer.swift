import Foundation

// MARK: - I/O Analyzer

/// I/O 性能分析器主入口
/// 整合追踪、聚合、热点检测
public actor IOAnalyzer {
  public static let shared = IOAnalyzer()

  private let tracer: IOSelfTracer
  private let aggregator: IOAggregator
  private let detector = IOHotspotDetector()

  public init(
    tracer: IOSelfTracer = .shared,
    aggregator: IOAggregator = .shared
  ) {
    self.tracer = tracer
    self.aggregator = aggregator
  }

  // MARK: - Lifecycle

  /// 开始分析
  public func startAnalysis(
    aggregationInterval: TimeInterval = 1.0,
    onSlice: (@Sendable (IOTimeSlice) -> Void)? = nil
  ) async {
    await tracer.startTracing()
    await aggregator.startAggregation(interval: aggregationInterval, onSlice: onSlice)
  }

  /// 停止分析
  public func stopAnalysis() async {
    await tracer.stopTracing()
    await aggregator.stopAggregation()
  }

  /// 是否正在分析
  public func isAnalyzing() async -> Bool {
    await tracer.isActive()
  }

  // MARK: - Data Access

  /// 获取实时时间片
  public func getTimeSlices(limit: Int = 60) async -> [IOTimeSlice] {
    await aggregator.getTimeSlices(limit: limit)
  }

  /// 获取热点路径
  public func getTopPaths(limit: Int = 20) async -> [IOPathStats] {
    await aggregator.getTopPaths(limit: limit)
  }

  /// 获取完整分析结果
  public func getAnalysisResult() async -> IOAnalysisResult {
    let timeSlices = await aggregator.getTimeSlices()
    let topPaths = await aggregator.getTopPaths()
    let duration = await tracer.tracingDuration()

    let optimizations = detector.analyze(
      pathStats: topPaths,
      timeSlices: timeSlices,
      tracingDuration: duration
    )

    let totalRead = timeSlices.reduce(0) { $0 + $1.readBytes }
    let totalWrite = timeSlices.reduce(0) { $0 + $1.writeBytes }

    return IOAnalysisResult(
      timeSlices: timeSlices,
      topPaths: topPaths,
      optimizations: optimizations,
      totalReadBytes: totalRead,
      totalWriteBytes: totalWrite,
      tracingDuration: duration
    )
  }

  // MARK: - Configuration

  /// 设置采样率
  public func setSampleRate(_ rate: Double) async {
    await tracer.setSampleRate(rate)
  }

  /// 获取缓冲区统计
  public func getBufferStats() async -> IOEventBuffer.BufferStats {
    await tracer.bufferStats()
  }

  /// 清除所有数据
  public func clear() async {
    await tracer.clear()
    await aggregator.clear()
  }

  // MARK: - Tracked Operations

  /// 追踪的文件读取
  public func trackedRead(at url: URL) async throws -> Data {
    try await tracer.trackedRead(at: url)
  }

  /// 追踪的文件写入
  public func trackedWrite(_ data: Data, to url: URL) async throws {
    try await tracer.trackedWrite(data, to: url)
  }

  /// 追踪的目录遍历
  public func trackedContents(at url: URL) async throws -> [URL] {
    try await tracer.trackedContents(at: url)
  }
}
