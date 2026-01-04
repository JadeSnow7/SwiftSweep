import Foundation

// MARK: - I/O Analyzer

/// I/O 性能分析器主入口
/// 整合追踪、聚合、热点检测
/// 支持两种模式：Self（应用内）和 System（全系统）
public actor IOAnalyzer {
  public static let shared = IOAnalyzer()

  /// 追踪模式
  public enum TracerMode: Sendable {
    case selfOnly  // 仅追踪应用自身 I/O（无需权限）
    case systemWide  // 全系统 I/O（需要 Endpoint Security）
  }

  private let selfTracer: IOSelfTracer
  private let systemTracer: ESSystemTracer
  private let aggregator: IOAggregator
  private let detector = IOHotspotDetector()

  private var currentMode: TracerMode = .selfOnly

  public init(
    selfTracer: IOSelfTracer = .shared,
    systemTracer: ESSystemTracer = .shared,
    aggregator: IOAggregator = .shared
  ) {
    self.selfTracer = selfTracer
    self.systemTracer = systemTracer
    self.aggregator = aggregator
  }

  // MARK: - Mode Selection

  /// 获取当前模式
  public func mode() -> TracerMode {
    currentMode
  }

  /// 检查系统模式是否可用
  public func isSystemModeAvailable() -> Bool {
    ESPermissionManager.shared.isAuthorized
  }

  // MARK: - Lifecycle

  /// 开始分析（指定模式）
  public func startAnalysis(
    mode: TracerMode = .selfOnly,
    aggregationInterval: TimeInterval = 1.0,
    filter: ESSystemTracer.FilterConfig = .init(),
    onSlice: (@Sendable (IOTimeSlice) -> Void)? = nil
  ) async throws {
    currentMode = mode

    switch mode {
    case .selfOnly:
      await selfTracer.startTracing()

    case .systemWide:
      try await systemTracer.startTracing(filter: filter)
    }

    await aggregator.startAggregation(
      interval: aggregationInterval,
      source: mode == .selfOnly ? .selfTracer(selfTracer) : .systemTracer(systemTracer),
      onSlice: onSlice
    )
  }

  /// 停止分析
  public func stopAnalysis() async {
    switch currentMode {
    case .selfOnly:
      await selfTracer.stopTracing()
    case .systemWide:
      await systemTracer.stopTracing()
    }
    await aggregator.stopAggregation()
  }

  /// 是否正在分析
  public func isAnalyzing() async -> Bool {
    switch currentMode {
    case .selfOnly:
      return await selfTracer.isActive()
    case .systemWide:
      return await systemTracer.isTracingActive()
    }
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

    let duration: TimeInterval
    switch currentMode {
    case .selfOnly:
      duration = await selfTracer.tracingDuration()
    case .systemWide:
      duration = await systemTracer.tracingDuration()
    }

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
    switch currentMode {
    case .selfOnly:
      await selfTracer.setSampleRate(rate)
    case .systemWide:
      await systemTracer.setSampleRate(rate)
    }
  }

  /// 获取缓冲区统计
  public func getBufferStats() async -> IOEventBuffer.BufferStats {
    switch currentMode {
    case .selfOnly:
      return await selfTracer.bufferStats()
    case .systemWide:
      return await systemTracer.bufferStats()
    }
  }

  /// 清除所有数据
  public func clear() async {
    await selfTracer.clear()
    await systemTracer.clear()
    await aggregator.clear()
  }

  // MARK: - Tracked Operations (Self Mode Only)

  /// 追踪的文件读取
  public func trackedRead(at url: URL) async throws -> Data {
    try await selfTracer.trackedRead(at: url)
  }

  /// 追踪的文件写入
  public func trackedWrite(_ data: Data, to url: URL) async throws {
    try await selfTracer.trackedWrite(data, to: url)
  }

  /// 追踪的目录遍历
  public func trackedContents(at url: URL) async throws -> [URL] {
    try await selfTracer.trackedContents(at: url)
  }
}
