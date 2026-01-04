import Foundation

// MARK: - I/O Operation Type

/// I/O 操作类型
public enum IOOperation: String, Sendable, CaseIterable {
  case read
  case write
  case open
  case close
  case stat
  case readdir
}

// MARK: - I/O Event

/// I/O 事件
public struct IOEvent: Sendable {
  public let timestamp: UInt64  // 单调时钟 ticks
  public let operation: IOOperation
  public let path: String  // 脱敏后的路径
  public let bytesTransferred: Int64
  public let durationNanos: UInt64
  public let pid: Int?  // 进程 ID（系统追踪模式）

  public init(
    timestamp: UInt64 = mach_absolute_time(),
    operation: IOOperation,
    path: String,
    bytesTransferred: Int64 = 0,
    durationNanos: UInt64 = 0,
    pid: Int? = nil
  ) {
    self.timestamp = timestamp
    self.operation = operation
    self.path = path
    self.bytesTransferred = bytesTransferred
    self.durationNanos = durationNanos
    self.pid = pid
  }

  public static let empty = IOEvent(
    timestamp: 0,
    operation: .read,
    path: "",
    bytesTransferred: 0,
    durationNanos: 0,
    pid: nil
  )
}

// MARK: - Time Slice

/// 时间窗口聚合
public struct IOTimeSlice: Sendable, Identifiable {
  public let id: UUID
  public let startTime: Date
  public let duration: TimeInterval
  public let readBytes: Int64
  public let writeBytes: Int64
  public let readOps: Int
  public let writeOps: Int
  public let avgLatencyNanos: UInt64
  public let p99LatencyNanos: UInt64

  public init(
    startTime: Date,
    duration: TimeInterval,
    readBytes: Int64,
    writeBytes: Int64,
    readOps: Int,
    writeOps: Int,
    avgLatencyNanos: UInt64,
    p99LatencyNanos: UInt64
  ) {
    self.id = UUID()
    self.startTime = startTime
    self.duration = duration
    self.readBytes = readBytes
    self.writeBytes = writeBytes
    self.readOps = readOps
    self.writeOps = writeOps
    self.avgLatencyNanos = avgLatencyNanos
    self.p99LatencyNanos = p99LatencyNanos
  }

  /// 读取吞吐量 (bytes/sec)
  public var readThroughput: Double {
    duration > 0 ? Double(readBytes) / duration : 0
  }

  /// 写入吞吐量 (bytes/sec)
  public var writeThroughput: Double {
    duration > 0 ? Double(writeBytes) / duration : 0
  }
}

// MARK: - Path Stats

/// 路径级统计
public struct IOPathStats: Sendable, Identifiable {
  public let id: UUID
  public let path: String
  public let totalBytes: Int64
  public let readBytes: Int64
  public let writeBytes: Int64
  public let operationCount: Int
  public let avgLatencyNanos: UInt64

  public init(
    path: String,
    totalBytes: Int64,
    readBytes: Int64,
    writeBytes: Int64,
    operationCount: Int,
    avgLatencyNanos: UInt64
  ) {
    self.id = UUID()
    self.path = path
    self.totalBytes = totalBytes
    self.readBytes = readBytes
    self.writeBytes = writeBytes
    self.operationCount = operationCount
    self.avgLatencyNanos = avgLatencyNanos
  }
}

// MARK: - Hotspot

/// I/O 热点类型
public enum IOHotspotType: Sendable {
  case frequentSmallReads(path: String, avgSize: Int64)
  case highLatency(path: String, avgLatencyMs: Double)
  case heavyWrite(path: String, bytesPerSec: Double)
  case fragmentedAccess(path: String, opsPerSec: Double)
}

/// 优化建议
public struct IOOptimization: Identifiable, Sendable {
  public let id: UUID
  public let type: IOHotspotType
  public let severity: Severity
  public let suggestion: String
  public let estimatedImprovement: String

  public enum Severity: String, Sendable {
    case low
    case medium
    case high
  }

  public init(
    type: IOHotspotType,
    severity: Severity,
    suggestion: String,
    estimatedImprovement: String
  ) {
    self.id = UUID()
    self.type = type
    self.severity = severity
    self.suggestion = suggestion
    self.estimatedImprovement = estimatedImprovement
  }
}

// MARK: - Analysis Result

/// I/O 分析结果
public struct IOAnalysisResult: Sendable {
  public let timeSlices: [IOTimeSlice]
  public let topPaths: [IOPathStats]
  public let optimizations: [IOOptimization]
  public let totalReadBytes: Int64
  public let totalWriteBytes: Int64
  public let tracingDuration: TimeInterval

  public init(
    timeSlices: [IOTimeSlice],
    topPaths: [IOPathStats],
    optimizations: [IOOptimization],
    totalReadBytes: Int64,
    totalWriteBytes: Int64,
    tracingDuration: TimeInterval
  ) {
    self.timeSlices = timeSlices
    self.topPaths = topPaths
    self.optimizations = optimizations
    self.totalReadBytes = totalReadBytes
    self.totalWriteBytes = totalWriteBytes
    self.tracingDuration = tracingDuration
  }
}
