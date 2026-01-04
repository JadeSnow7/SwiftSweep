import EndpointSecurity
import Foundation

// MARK: - Endpoint Security System Tracer

/// 系统级 I/O 追踪器
/// 使用 Endpoint Security Framework 监控全系统文件操作
public actor ESSystemTracer {
  public static let shared = ESSystemTracer()

  private var client: OpaquePointer?  // es_client_t
  private let buffer: IOEventBuffer
  private var isActive = false
  private var tracingStartTime: Date?

  /// 事件过滤配置
  public struct FilterConfig: Sendable {
    /// 只监控这些路径前缀（空=全部）
    public var pathPrefixes: [String] = []
    /// 排除这些路径前缀
    public var excludePrefixes: [String] = [
      "/private/var/folders",  // 临时文件
      "/Library/Caches",
      "/System",
    ]
    /// 只监控这些进程（空=全部）
    public var processNames: [String] = []

    public init() {}
  }

  private var filterConfig = FilterConfig()

  public init(bufferCapacity: Int = 50_000) {
    self.buffer = IOEventBuffer(capacity: bufferCapacity)
  }

  // MARK: - Lifecycle

  /// 开始系统级追踪
  public func startTracing(filter: FilterConfig = FilterConfig()) async throws {
    guard !isActive else { return }

    filterConfig = filter

    // 创建 ES Client
    var newClient: OpaquePointer?
    let result = es_new_client(&newClient) { [weak self] _, message in
      guard let self = self else { return }

      Task {
        await self.handleMessage(message)
      }
    }

    guard result == ES_NEW_CLIENT_RESULT_SUCCESS, let client = newClient else {
      throw ESTracerError.clientCreationFailed(result)
    }

    self.client = client

    // 订阅文件事件
    let events: [es_event_type_t] = [
      ES_EVENT_TYPE_NOTIFY_OPEN,
      ES_EVENT_TYPE_NOTIFY_CLOSE,
      ES_EVENT_TYPE_NOTIFY_WRITE,
      ES_EVENT_TYPE_NOTIFY_CREATE,
      ES_EVENT_TYPE_NOTIFY_RENAME,
      ES_EVENT_TYPE_NOTIFY_UNLINK,
      ES_EVENT_TYPE_NOTIFY_READDIR,
    ]

    let subscribeResult = es_subscribe(client, events, UInt32(events.count))
    guard subscribeResult == ES_RETURN_SUCCESS else {
      es_delete_client(client)
      self.client = nil
      throw ESTracerError.subscribeFailed(subscribeResult)
    }

    isActive = true
    tracingStartTime = Date()
  }

  /// 停止追踪
  public func stopTracing() async {
    guard isActive, let client = client else { return }

    es_unsubscribe_all(client)
    es_delete_client(client)

    self.client = nil
    isActive = false
  }

  /// 是否正在追踪
  public func isTracingActive() -> Bool {
    isActive
  }

  /// 获取追踪时长
  public func tracingDuration() -> TimeInterval {
    guard let start = tracingStartTime else { return 0 }
    return Date().timeIntervalSince(start)
  }

  // MARK: - Event Handling

  private func handleMessage(_ message: UnsafePointer<es_message_t>) async {
    let msg = message.pointee

    // 提取进程信息
    let processName = extractString(from: msg.process.pointee.executable.pointee.path)

    // 根据事件类型处理
    let event: IOEvent?

    switch msg.event_type {
    case ES_EVENT_TYPE_NOTIFY_OPEN:
      let file = msg.event.open.file.pointee
      let path = extractString(from: file.path)
      guard shouldInclude(path: path, process: processName) else { return }
      event = IOEvent(
        operation: .read,
        path: sanitizePath(path),
        pid: Int(msg.process.pointee.audit_token.val.0)
      )

    case ES_EVENT_TYPE_NOTIFY_WRITE:
      let target = msg.event.write.target.pointee
      let path = extractString(from: target.path)
      guard shouldInclude(path: path, process: processName) else { return }
      event = IOEvent(
        operation: .write,
        path: sanitizePath(path),
        pid: Int(msg.process.pointee.audit_token.val.0)
      )

    case ES_EVENT_TYPE_NOTIFY_CREATE:
      // For create events, try to get the path from new_path if available
      // The destination_type is accessed differently in Swift
      let dest = msg.event.create.destination
      let path: String
      // Try new_path first (for new file creation)
      let dirPath = extractString(from: dest.new_path.dir.pointee.path)
      let filename = extractString(from: dest.new_path.filename)
      if !dirPath.isEmpty && !filename.isEmpty {
        path = dirPath + "/" + filename
      } else {
        // Fallback: this shouldn't normally happen for creates
        path = "(unknown)"
      }
      guard shouldInclude(path: path, process: processName) else { return }
      event = IOEvent(
        operation: .write,
        path: sanitizePath(path),
        pid: Int(msg.process.pointee.audit_token.val.0)
      )

    case ES_EVENT_TYPE_NOTIFY_UNLINK:
      let target = msg.event.unlink.target.pointee
      let path = extractString(from: target.path)
      guard shouldInclude(path: path, process: processName) else { return }
      event = IOEvent(
        operation: .write,
        path: sanitizePath(path),
        pid: Int(msg.process.pointee.audit_token.val.0)
      )

    case ES_EVENT_TYPE_NOTIFY_READDIR:
      let target = msg.event.readdir.target.pointee
      let path = extractString(from: target.path)
      guard shouldInclude(path: path, process: processName) else { return }
      event = IOEvent(
        operation: .readdir,
        path: sanitizePath(path),
        pid: Int(msg.process.pointee.audit_token.val.0)
      )

    default:
      event = nil
    }

    if let event = event {
      await buffer.append(event)
    }
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

  /// 清除缓冲区
  public func clear() async {
    await buffer.clear()
  }

  // MARK: - Filtering

  private func shouldInclude(path: String, process: String) -> Bool {
    // 排除检查
    for prefix in filterConfig.excludePrefixes {
      if path.hasPrefix(prefix) {
        return false
      }
    }

    // 路径包含检查
    if !filterConfig.pathPrefixes.isEmpty {
      let included = filterConfig.pathPrefixes.contains { path.hasPrefix($0) }
      if !included { return false }
    }

    // 进程过滤
    if !filterConfig.processNames.isEmpty {
      return filterConfig.processNames.contains(process)
    }

    return true
  }

  // MARK: - Helpers

  private func extractString(from token: es_string_token_t) -> String {
    if token.length > 0, let data = token.data {
      return String(cString: data)
    }
    return ""
  }

  private func sanitizePath(_ path: String) -> String {
    let components = path.split(separator: "/")
    if components.count > 3 {
      return ".../\(components.suffix(3).joined(separator: "/"))"
    }
    return path
  }
}

// MARK: - Errors

public enum ESTracerError: Error, LocalizedError {
  case clientCreationFailed(es_new_client_result_t)
  case subscribeFailed(es_return_t)
  case notAuthorized

  public var errorDescription: String? {
    switch self {
    case .clientCreationFailed(let result):
      return "Failed to create ES client: \(result.rawValue)"
    case .subscribeFailed(let result):
      return "Failed to subscribe to events: \(result.rawValue)"
    case .notAuthorized:
      return "Endpoint Security requires Full Disk Access permission"
    }
  }
}
