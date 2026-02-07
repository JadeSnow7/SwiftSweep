import CoreServices
import Foundation

// MARK: - FSEvents Tracer

/// 使用 FSEvents API 监控文件系统变更
/// 无需特殊权限，可监控任意目录
public actor FSEventsTracer {
  public static let shared = FSEventsTracer()

  private var stream: FSEventStreamRef?
  private let buffer: IOEventBuffer
  private var isActive = false
  private var tracingStartTime: Date?
  private var watchedPaths: [String] = []
  private let dispatchQueue = DispatchQueue(label: "com.swiftsweep.fsevents", qos: .utility)

  /// 事件统计
  private var eventCounts: [String: Int] = [:]

  public init(bufferCapacity: Int = 20_000) {
    self.buffer = IOEventBuffer(capacity: bufferCapacity)
  }

  // MARK: - Lifecycle

  /// 开始监控指定路径
  /// - Parameter paths: 要监控的目录路径（如 "/Volumes/ExternalDisk"）
  public func startTracing(paths: [String]) async throws {
    guard !isActive else { return }
    guard !paths.isEmpty else {
      throw FSEventsTracerError.noPathsSpecified
    }

    // 验证路径存在
    let validPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
    guard !validPaths.isEmpty else {
      throw FSEventsTracerError.invalidPaths
    }

    watchedPaths = validPaths

    // 创建 FSEventStream（必须在主线程）
    let created = await MainActor.run { [weak self] () -> Bool in
      guard let self = self else { return false }

      var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self as AnyObject).toOpaque(),
        retain: nil,
        release: nil,
        copyDescription: nil
      )

      let pathsToWatch = validPaths as CFArray

      guard
        let stream = FSEventStreamCreate(
          kCFAllocatorDefault,
          fsEventCallback,
          &context,
          pathsToWatch,
          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
          0.5,  // 延迟 0.5 秒批量回调
          UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
              | kFSEventStreamCreateFlagUseCFTypes)
        )
      else {
        return false
      }

      FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

      FSEventStreamStart(stream)

      Task { @MainActor in
        await self.setStream(stream)
      }

      return true
    }

    guard created else {
      throw FSEventsTracerError.streamCreationFailed
    }

    isActive = true
    tracingStartTime = Date()
  }

  private func setStream(_ stream: FSEventStreamRef) {
    self.stream = stream
  }

  /// 停止监控
  public func stopTracing() async {
    guard isActive, let stream = stream else { return }

    let capturedStreamAddress = Int(bitPattern: stream)

    await MainActor.run {
      guard let capturedStream = OpaquePointer(bitPattern: capturedStreamAddress) else { return }
      FSEventStreamStop(capturedStream)
      FSEventStreamInvalidate(capturedStream)
      FSEventStreamRelease(capturedStream)
    }

    self.stream = nil
    isActive = false
    watchedPaths = []
  }

  /// 是否正在监控
  public func isTracingActive() -> Bool {
    isActive
  }

  /// 获取监控时长
  public func tracingDuration() -> TimeInterval {
    guard let start = tracingStartTime else { return 0 }
    return Date().timeIntervalSince(start)
  }

  /// 获取监控的路径
  public func getWatchedPaths() -> [String] {
    watchedPaths
  }

  // MARK: - Event Recording

  /// 记录 FSEvent 事件（由回调调用）
  public func recordEvent(path: String, flags: FSEventStreamEventFlags) async {
    let operation: IOOperation
    let isFile = (flags & UInt32(kFSEventStreamEventFlagItemIsFile)) != 0

    if (flags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0 {
      operation = .write
    } else if (flags & UInt32(kFSEventStreamEventFlagItemModified)) != 0 {
      operation = .write
    } else if (flags & UInt32(kFSEventStreamEventFlagItemRemoved)) != 0 {
      operation = .write
    } else if (flags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0 {
      operation = .write
    } else if isFile {
      operation = .read  // 文件被访问
    } else {
      operation = .readdir  // 目录被访问
    }

    // 统计
    let key = sanitizePath(path)
    eventCounts[key, default: 0] += 1

    // 估算字节数（FSEvents 不提供准确字节数）
    var estimatedBytes: Int64 = 0
    if isFile, operation == .write {
      // 尝试获取文件大小
      if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let size = attrs[.size] as? Int64
      {
        estimatedBytes = size
      }
    }

    let event = IOEvent(
      operation: operation,
      path: sanitizePath(path),
      bytesTransferred: estimatedBytes
    )

    await buffer.append(event)
  }

  // MARK: - Buffer Access

  public func drainEvents(maxCount: Int = 1000) async -> [IOEvent] {
    await buffer.drain(maxCount: maxCount)
  }

  public func bufferStats() async -> IOEventBuffer.BufferStats {
    await buffer.stats()
  }

  public func setSampleRate(_ rate: Double) async {
    await buffer.setSampleRate(rate)
  }

  public func clear() async {
    await buffer.clear()
    eventCounts.removeAll()
  }

  // MARK: - Helpers

  private func sanitizePath(_ path: String) -> String {
    let components = path.split(separator: "/")
    if components.count > 3 {
      return ".../\(components.suffix(3).joined(separator: "/"))"
    }
    return path
  }
}

// MARK: - FSEvent Callback

private func fsEventCallback(
  streamRef: ConstFSEventStreamRef,
  clientCallBackInfo: UnsafeMutableRawPointer?,
  numEvents: Int,
  eventPaths: UnsafeMutableRawPointer,
  eventFlags: UnsafePointer<FSEventStreamEventFlags>,
  eventIds: UnsafePointer<FSEventStreamEventId>
) {
  guard let info = clientCallBackInfo else { return }

  let tracer = Unmanaged<AnyObject>.fromOpaque(info).takeUnretainedValue() as! FSEventsTracer

  // 将 eventPaths 转换为 Swift 数组
  let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

  for i in 0..<numEvents {
    let path = paths[i]
    let flags = eventFlags[i]

    Task {
      await tracer.recordEvent(path: path, flags: flags)
    }
  }
}

// MARK: - Errors

public enum FSEventsTracerError: Error, LocalizedError {
  case noPathsSpecified
  case invalidPaths
  case streamCreationFailed

  public var errorDescription: String? {
    switch self {
    case .noPathsSpecified:
      return "No paths specified for monitoring"
    case .invalidPaths:
      return "None of the specified paths exist"
    case .streamCreationFailed:
      return "Failed to create FSEventStream"
    }
  }
}
