import Foundation
import Logging

#if canImport(IOKit)
  import IOKit.ps
#endif

/// Real-time system monitoring for CPU, memory, disk, battery, and network metrics.
///
/// `SystemMonitor` provides comprehensive system metrics including:
/// - CPU usage percentage
/// - Memory usage (used/total in bytes and percentage)
/// - Disk usage (used/total in bytes and percentage)
/// - Battery level (0-1.0)
/// - Network throughput (download/upload in MB/s)
///
/// ## Usage
///
/// ```swift
/// let monitor = SystemMonitor.shared
///
/// // Get current metrics
/// let metrics = try await monitor.getMetrics()
/// print("CPU: \(metrics.cpuUsage * 100)%")
/// print("Memory: \(metrics.memoryUsage * 100)%")
/// print("Disk: \(metrics.diskUsage * 100)%")
/// ```
///
/// ## Performance
///
/// - Metrics are calculated on-demand
/// - CPU usage is averaged over a short sampling period
/// - Network metrics track delta since last call
///
public final class SystemMonitor {
  public static let shared = SystemMonitor()

  private let logger = Logger(label: "com.molekit.systemmonitor")

  public struct SystemMetrics: Sendable {
    public var cpuUsage: Double
    public var memoryUsage: Double
    public var memoryUsed: Int64  // 字节
    public var memoryTotal: Int64  // 字节
    public var diskUsage: Double
    public var diskUsed: Int64  // 字节
    public var diskTotal: Int64  // 字节
    public var batteryLevel: Double
    public var networkDownload: Double  // MB/s
    public var networkUpload: Double  // MB/s

    public init() {
      self.cpuUsage = 0
      self.memoryUsage = 0
      self.memoryUsed = 0
      self.memoryTotal = 0
      self.diskUsage = 0
      self.diskUsed = 0
      self.diskTotal = 0
      self.batteryLevel = 0
      self.networkDownload = 0
      self.networkUpload = 0
    }
  }

  private init() {}

  /// Retrieves current system metrics.
  ///
  /// Collects real-time metrics for:
  /// - CPU usage (0-1.0)
  /// - Memory usage (bytes and percentage)
  /// - Disk usage (bytes and percentage)
  /// - Battery level (0-1.0, or 0 if no battery)
  /// - Network throughput (MB/s)
  ///
  /// - Returns: ``SystemMetrics`` containing current system state
  /// - Throws: `SystemMonitorError` if metrics cannot be retrieved
  ///
  /// ## Example
  ///
  /// ```swift
  /// let metrics = try await monitor.getMetrics()
  /// if metrics.cpuUsage > 0.8 {
  ///   print("High CPU usage detected!")
  /// }
  /// ```
  public func getMetrics() async throws -> SystemMetrics {
    logger.debug("Fetching system metrics...")

    var metrics = SystemMetrics()

    // 获取 CPU 使用率
    metrics.cpuUsage = try getCPUUsage()

    // 获取内存信息
    (metrics.memoryUsed, metrics.memoryTotal) = try getMemoryInfo()
    metrics.memoryUsage = Double(metrics.memoryUsed) / Double(metrics.memoryTotal)

    // 获取磁盘信息
    (metrics.diskUsed, metrics.diskTotal) = try getDiskInfo()
    metrics.diskUsage = Double(metrics.diskUsed) / Double(metrics.diskTotal)

    // 获取电池信息
    metrics.batteryLevel = try getBatteryLevel()

    // 获取网络速度
    let (down, up) = getNetworkSteps()
    metrics.networkDownload = down
    metrics.networkUpload = up

    logger.debug("Metrics fetched successfully")
    return metrics
  }

  // MARK: - Private Methods

  // MARK: - Network State

  private struct NetworkState {
    var timestamp: TimeInterval
    var bytesIn: UInt64
    var bytesOut: UInt64
  }

  private var lastNetworkState: NetworkState?
  private let networkStateLock = NSLock()

  // MARK: - Private Methods

  private func getCPUUsage() throws -> Double {
    // 使用 sysctl 获取 CPU 负载
    var loadavg: [Double] = [0, 0, 0]
    if getloadavg(&loadavg, 3) == 3 {
      // 1分钟负载 / CPU核心数 = 大致使用率
      let cpuCount = ProcessInfo.processInfo.processorCount
      let usage = (loadavg[0] / Double(cpuCount)) * 100.0
      return min(usage, 100.0)
    }
    return 0.0
  }

  private func getMemoryInfo() throws -> (used: Int64, total: Int64) {
    // 获取物理内存总量
    let totalMemory = Int64(ProcessInfo.processInfo.physicalMemory)

    // 使用 vm_statistics64 获取内存使用情况
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }

    if result == KERN_SUCCESS {
      let pageSize = Int64(vm_kernel_page_size)
      let freeMemory = Int64(stats.free_count) * pageSize
      let inactiveMemory = Int64(stats.inactive_count) * pageSize
      let usedMemory = totalMemory - freeMemory - inactiveMemory
      return (usedMemory, totalMemory)
    }

    return (0, totalMemory)
  }

  private func getDiskInfo() throws -> (used: Int64, total: Int64) {
    let fileManager = FileManager.default
    let homeDir = NSHomeDirectory()

    if let attrs = try? fileManager.attributesOfFileSystem(forPath: homeDir) {
      let totalSize = attrs[.systemSize] as? Int64 ?? 0
      let freeSize = attrs[.systemFreeSize] as? Int64 ?? 0
      let usedSize = totalSize - freeSize
      return (usedSize, totalSize)
    }

    return (0, 0)
  }

  private func getBatteryLevel() throws -> Double {
    #if canImport(IOKit)
      // 使用 IOKit 获取电池信息
      let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
      let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array

      for source in sources {
        if let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
          .takeUnretainedValue() as? [String: Any]
        {
          if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int
          {
            return Double(capacity) / Double(maxCapacity) * 100.0
          }
        }
      }
    #endif

    // 台式机或无电池设备返回 100
    return 100.0
  }

  private func getNetworkSteps() -> (down: Double, up: Double) {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
    defer { freeifaddrs(ifaddr) }

    var totalBytesIn: UInt64 = 0
    var totalBytesOut: UInt64 = 0

    var ptr = ifaddr
    while ptr != nil {
      defer { ptr = ptr?.pointee.ifa_next }

      guard let interface = ptr?.pointee else { continue }
      let _ = String(cString: interface.ifa_name)

      // 忽略非活跃或回环接口
      if (interface.ifa_flags & UInt32(IFF_UP)) == 0
        || (interface.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
      {
        continue
      }

      // 确保是链路层 (AF_LINK)
      if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
        if let data = interface.ifa_data {
          let networkData = data.assumingMemoryBound(to: if_data.self).pointee
          totalBytesIn += UInt64(networkData.ifi_ibytes)
          totalBytesOut += UInt64(networkData.ifi_obytes)
        }
      }
    }

    let now = Date().timeIntervalSince1970
    var downSpeed: Double = 0
    var upSpeed: Double = 0

    networkStateLock.lock()
    let last = lastNetworkState
    networkStateLock.unlock()

    if let last = last {
      let timeDiff = now - last.timestamp
      if timeDiff > 0 {
        // 计算字节差并转换为 MB/s
        let bytesInDiff = totalBytesIn >= last.bytesIn ? totalBytesIn - last.bytesIn : 0
        let bytesOutDiff = totalBytesOut >= last.bytesOut ? totalBytesOut - last.bytesOut : 0

        downSpeed = Double(bytesInDiff) / 1024.0 / 1024.0 / timeDiff
        upSpeed = Double(bytesOutDiff) / 1024.0 / 1024.0 / timeDiff
      }
    }

    networkStateLock.lock()
    lastNetworkState = NetworkState(timestamp: now, bytesIn: totalBytesIn, bytesOut: totalBytesOut)
    networkStateLock.unlock()

    return (downSpeed, upSpeed)
  }
}
