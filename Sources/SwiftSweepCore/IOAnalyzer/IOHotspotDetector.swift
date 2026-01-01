import Foundation

// MARK: - Hotspot Detector

/// I/O 热点检测器
/// 分析统计数据，生成优化建议
public struct IOHotspotDetector {

  // MARK: - Thresholds

  /// 小读取阈值（平均 < 4KB 认为是碎片化）
  private let smallReadThreshold: Int64 = 4096

  /// 高延迟阈值（> 10ms）
  private let highLatencyThresholdNanos: UInt64 = 10_000_000

  /// 高写入阈值（> 10MB/s）
  private let heavyWriteThreshold: Double = 10 * 1024 * 1024

  /// 高操作频率阈值（> 100 ops/s）
  private let highOpsThreshold: Double = 100

  // MARK: - Analysis

  /// 分析并生成优化建议
  public func analyze(
    pathStats: [IOPathStats],
    timeSlices: [IOTimeSlice],
    tracingDuration: TimeInterval
  ) -> [IOOptimization] {
    var optimizations: [IOOptimization] = []

    // 分析路径级热点
    for stats in pathStats {
      // 检测频繁小读取
      if stats.operationCount > 10 && stats.readBytes > 0 {
        let avgSize = stats.readBytes / Int64(stats.operationCount)
        if avgSize < smallReadThreshold {
          optimizations.append(
            IOOptimization(
              type: .frequentSmallReads(path: stats.path, avgSize: avgSize),
              severity: .medium,
              suggestion: "考虑批量读取或使用 mmap 映射文件：\(stats.path)",
              estimatedImprovement: "减少 syscall 开销约 \(stats.operationCount / 10)x"
            ))
        }
      }

      // 检测高延迟
      let avgLatencyMs = Double(stats.avgLatencyNanos) / 1_000_000
      if avgLatencyMs > Double(highLatencyThresholdNanos) / 1_000_000 {
        optimizations.append(
          IOOptimization(
            type: .highLatency(path: stats.path, avgLatencyMs: avgLatencyMs),
            severity: .high,
            suggestion: "检查磁盘健康状态或考虑使用 SSD：\(stats.path)",
            estimatedImprovement: "潜在延迟降低 \(Int(avgLatencyMs))ms"
          ))
      }

      // 检测高写入量
      if tracingDuration > 0 {
        let bytesPerSec = Double(stats.writeBytes) / tracingDuration
        if bytesPerSec > heavyWriteThreshold {
          optimizations.append(
            IOOptimization(
              type: .heavyWrite(path: stats.path, bytesPerSec: bytesPerSec),
              severity: .medium,
              suggestion: "考虑使用异步写入或批量缓冲：\(stats.path)",
              estimatedImprovement: "减少磁盘压力约 \(Int(bytesPerSec / 1024 / 1024))MB/s"
            ))
        }

        // 检测碎片化访问
        let opsPerSec = Double(stats.operationCount) / tracingDuration
        if opsPerSec > highOpsThreshold {
          optimizations.append(
            IOOptimization(
              type: .fragmentedAccess(path: stats.path, opsPerSec: opsPerSec),
              severity: .low,
              suggestion: "考虑合并 I/O 操作或使用缓存：\(stats.path)",
              estimatedImprovement: "减少操作频率约 \(Int(opsPerSec))ops/s"
            ))
        }
      }
    }

    // 按严重性排序
    return optimizations.sorted { lhs, rhs in
      severityOrder(lhs.severity) < severityOrder(rhs.severity)
    }
  }

  private func severityOrder(_ severity: IOOptimization.Severity) -> Int {
    switch severity {
    case .high: return 0
    case .medium: return 1
    case .low: return 2
    }
  }
}
