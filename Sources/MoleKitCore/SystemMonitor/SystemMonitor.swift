import Foundation
import Logging
#if canImport(IOKit)
import IOKit.ps
#endif

/// MoleKit 系统监控引擎 - 实时监控 CPU、内存、磁盘等系统指标
public final class SystemMonitor {
    public static let shared = SystemMonitor()
    
    private let logger = Logger(label: "com.molekit.systemmonitor")
    
    public struct SystemMetrics {
        public var cpuUsage: Double
        public var memoryUsage: Double
        public var memoryUsed: Int64  // 字节
        public var memoryTotal: Int64 // 字节
        public var diskUsage: Double
        public var diskUsed: Int64    // 字节
        public var diskTotal: Int64   // 字节
        public var batteryLevel: Double
        public var networkDownload: Double    // MB/s
        public var networkUpload: Double      // MB/s
        
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
    
    /// 获取当前系统指标
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
        
        logger.debug("Metrics fetched successfully")
        return metrics
    }
    
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
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
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
            if let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
                if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                   let maxCapacity = info[kIOPSMaxCapacityKey] as? Int {
                    return Double(capacity) / Double(maxCapacity) * 100.0
                }
            }
        }
        #endif
        
        // 台式机或无电池设备返回 100
        return 100.0
    }
}
