import Foundation
import Logging

// MARK: - Process Info Model

/// 进程信息模型
public struct SystemProcessInfo: Identifiable, Sendable, Hashable {
  public let id: pid_t
  public let name: String
  public let cpuUsage: Double  // 百分比 (0-100)
  public let memoryUsage: Int64  // 字节
  public let user: String

  public init(id: pid_t, name: String, cpuUsage: Double, memoryUsage: Int64, user: String) {
    self.id = id
    self.name = name
    self.cpuUsage = cpuUsage
    self.memoryUsage = memoryUsage
    self.user = user
  }
}

// MARK: - Sort Key

public enum ProcessSortKey: String, CaseIterable, Sendable {
  case cpu = "CPU"
  case memory = "Memory"
  case name = "Name"
}

// MARK: - Process Monitor

/// 进程监控器 - 获取系统进程列表和资源使用情况
public final class ProcessMonitor: @unchecked Sendable {
  public static let shared = ProcessMonitor()

  private let logger = Logger(label: "com.swiftsweep.processmonitor")
  private let queue = DispatchQueue(label: "com.swiftsweep.processmonitor.queue")

  private init() {}

  // 缓存上一次的 CPU 时间数据：PID -> (UserTime + SystemTime) in nanoseconds
  private var lastCPUTimes: [pid_t: UInt64] = [:]
  private var lastSampleTime: TimeInterval = 0

  /// 获取进程列表
  /// - Parameters:
  ///   - sortBy: 排序方式
  ///   - limit: 返回数量限制
  /// - Returns: 排序后的进程列表
  public func getProcesses(sortBy: ProcessSortKey = .cpu, limit: Int = 20) async
    -> [SystemProcessInfo]
  {
    return await withCheckedContinuation { continuation in
      queue.async { [weak self] in
        guard let self = self else {
          continuation.resume(returning: [])
          return
        }

        let processes = self.fetchAllProcesses()
        let sorted = self.sortProcesses(processes, by: sortBy)
        let limited = Array(sorted.prefix(limit))

        continuation.resume(returning: limited)
      }
    }
  }

  // MARK: - Private Methods

  /// 获取所有进程信息
  private func fetchAllProcesses() -> [SystemProcessInfo] {
    var processes: [SystemProcessInfo] = []

    // 当前采样时间
    let currentSampleTime = Date().timeIntervalSince1970
    let timeDiff = currentSampleTime - lastSampleTime

    // 是否是有效的 CPU 计算周期（避免过短间隔导致数据抖动，且防止除以零）
    let isValidCPUSample = lastSampleTime > 0 && timeDiff > 0.1

    // 新的 CPU 时间缓存
    var currentCPUTimes: [pid_t: UInt64] = [:]

    // 使用 sysctl 获取进程列表
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var size: size_t = 0

    // 第一次调用获取需要的缓冲区大小
    guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else {
      logger.error("Failed to get process buffer size")
      return []
    }

    // 分配缓冲区
    let count = size / MemoryLayout<kinfo_proc>.stride
    var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

    // 第二次调用获取进程数据
    guard sysctl(&mib, UInt32(mib.count), &procList, &size, nil, 0) == 0 else {
      logger.error("Failed to get process list")
      return []
    }

    let actualCount = size / MemoryLayout<kinfo_proc>.stride

    // 遍历所有进程
    for i in 0..<actualCount {
      let proc = procList[i]
      let pid = proc.kp_proc.p_pid

      // 跳过 PID 0 (kernel_task) 虽然也可以监控，但一般不杀死
      guard pid >= 0 else { continue }

      // 获取当前 CPU 总时间 (ns) 和内存 (bytes)
      let (totalCPUTime, memory) = getRawResourceUsage(for: pid)

      // 更新缓存
      currentCPUTimes[pid] = totalCPUTime

      // 计算 CPU 使用率
      var cpuUsage: Double = 0.0
      if isValidCPUSample, let lastTime = lastCPUTimes[pid] {
        // 差值
        let cpuDiff = Double(totalCPUTime) - Double(lastTime)
        // 纳秒转秒: / 1e9
        // Usage = (cpuSeconds / timeDiffSeconds) * 100.0
        if cpuDiff > 0 {
          cpuUsage = (cpuDiff / 1_000_000_000.0) / timeDiff * 100.0
        }
      }

      // 获取进程名和用户
      let name = getProcessName(from: proc)
      let user = getUserName(uid: proc.kp_eproc.e_ucred.cr_uid)

      let info = SystemProcessInfo(
        id: pid,
        name: name,
        cpuUsage: cpuUsage,  // 这里不再限制 100%，多核可能超过 100%
        memoryUsage: memory,
        user: user
      )
      processes.append(info)
    }

    // 更新状态
    lastCPUTimes = currentCPUTimes
    lastSampleTime = currentSampleTime

    return processes
  }

  /// 从 kinfo_proc 获取进程名
  private func getProcessName(from proc: kinfo_proc) -> String {
    var name = proc.kp_proc.p_comm
    return withUnsafePointer(to: &name) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
        String(cString: $0)
      }
    }
  }

  /// 获取进程的 原始CPU时间(ns) 和 内存使用(bytes)
  private func getRawResourceUsage(for pid: pid_t) -> (cpuTime: UInt64, memory: Int64) {
    var rusage = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &rusage) {
      $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { ptr in
        proc_pid_rusage(pid, RUSAGE_INFO_V4, ptr)
      }
    }

    guard result == 0 else {
      return (0, 0)
    }

    let memory = Int64(rusage.ri_phys_footprint)
    let cpuTime = rusage.ri_user_time + rusage.ri_system_time

    return (cpuTime, memory)
  }

  /// 获取用户名
  private func getUserName(uid: uid_t) -> String {
    if let pwd = getpwuid(uid) {
      return String(cString: pwd.pointee.pw_name)
    }
    return String(uid)
  }

  /// 排序进程
  private func sortProcesses(_ processes: [SystemProcessInfo], by key: ProcessSortKey)
    -> [SystemProcessInfo]
  {
    switch key {
    case .cpu:
      return processes.sorted { $0.cpuUsage > $1.cpuUsage }
    case .memory:
      return processes.sorted { $0.memoryUsage > $1.memoryUsage }
    case .name:
      return processes.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
    }
  }
}
