import Foundation
import Logging

/// SwiftSweep 卸载引擎 - 扫描已安装应用及其残留文件
public final class UninstallEngine {
  public static let shared = UninstallEngine()

  internal let logger = Logger(label: "com.swiftsweep.uninstall")

  public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bundleID: String
    public let path: String
    public let size: Int64
    public let lastUsed: Date?
    public var residualFiles: [ResidualFile]

    public init(
      name: String, bundleID: String, path: String, size: Int64, lastUsed: Date?,
      residualFiles: [ResidualFile] = []
    ) {
      // Stable ID based on bundleID + path for consistent identity across scans
      self.id = Self.stableID(bundleID: bundleID, path: path)
      self.name = name
      self.bundleID = bundleID
      self.path = path
      self.size = size
      self.lastUsed = lastUsed
      self.residualFiles = residualFiles
    }

    /// Generates a stable UUID from bundleID and path
    private static func stableID(bundleID: String, path: String) -> UUID {
      let combined = "\(bundleID):\(path)"
      var hash = combined.utf8.reduce(0) { (result, byte) -> UInt64 in
        var h = result
        h = h &+ UInt64(byte)
        h = h &+ (h << 10)
        h ^= (h >> 6)
        return h
      }
      hash = hash &+ (hash << 3)
      hash ^= (hash >> 11)
      hash = hash &+ (hash << 15)

      // Create UUID from hash bytes
      var bytes = [UInt8](repeating: 0, count: 16)
      for i in 0..<8 {
        bytes[i] = UInt8(truncatingIfNeeded: hash >> (i * 8))
        bytes[i + 8] = UInt8(truncatingIfNeeded: hash >> ((7 - i) * 8))
      }
      bytes[6] = (bytes[6] & 0x0F) | 0x40  // Version 4
      bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant

      return UUID(
        uuid: (
          bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
          bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    public var totalSize: Int64 {
      size + residualFiles.reduce(0) { $0 + $1.size }
    }
  }

  public struct ResidualFile: Hashable, Sendable {
    public let path: String
    public let size: Int64
    public let type: ResidualType

    public init(path: String, size: Int64, type: ResidualType) {
      self.path = path
      self.size = size
      self.type = type
    }
  }

  public enum ResidualType: String, Sendable {
    case cache = "Cache"
    case preferences = "Preferences"
    case appSupport = "Application Support"
    case launchAgent = "Launch Agent"
    case container = "Container"
    case other = "Other"
  }

  private init() {}

  /// 扫描已安装的应用
  /// - Parameter includeSizes: 是否计算体积（默认 false 提升性能）
  public func scanInstalledApps(includeSizes: Bool = false) async throws -> [InstalledApp] {
    logger.info("Scanning installed applications (includeSizes: \(includeSizes))...")

    var apps: [InstalledApp] = []
    let fileManager = FileManager.default

    // 扫描 /Applications
    let systemApps = try scanApplicationsDirectory(at: "/Applications", includeSizes: includeSizes)
    apps.append(contentsOf: systemApps)

    // 扫描 ~/Applications
    let userAppsPath = NSHomeDirectory() + "/Applications"
    if fileManager.fileExists(atPath: userAppsPath) {
      let userApps = try scanApplicationsDirectory(at: userAppsPath, includeSizes: includeSizes)
      apps.append(contentsOf: userApps)
    }

    logger.info("Found \(apps.count) applications")
    return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
  }

  /// 查找应用的残留文件
  /// - Parameters:
  ///   - app: 目标应用
  ///   - calculateSizes: 是否计算体积（默认 false 提升性能）
  public func findResidualFiles(for app: InstalledApp, calculateSizes: Bool = false) throws
    -> [ResidualFile]
  {
    var residuals: [ResidualFile] = []
    let fileManager = FileManager.default
    let home = NSHomeDirectory()

    // 搜索路径
    let searchPaths: [(String, ResidualType)] = [
      ("\(home)/Library/Caches", .cache),
      ("\(home)/Library/Preferences", .preferences),
      ("\(home)/Library/Application Support", .appSupport),
      ("\(home)/Library/LaunchAgents", .launchAgent),
      ("\(home)/Library/Containers", .container),
    ]

    for (basePath, type) in searchPaths {
      guard fileManager.fileExists(atPath: basePath) else { continue }

      if let contents = try? fileManager.contentsOfDirectory(atPath: basePath) {
        for item in contents {
          // 匹配 bundleID 或应用名称
          let lowerItem = item.lowercased()
          let lowerBundle = app.bundleID.lowercased()
          let lowerName = app.name.lowercased().replacingOccurrences(of: ".app", with: "")

          if lowerItem.contains(lowerBundle) || lowerItem.contains(lowerName)
            || lowerBundle.contains(lowerItem.replacingOccurrences(of: ".plist", with: ""))
          {
            let fullPath = basePath + "/" + item
            // 仅在需要时计算体积
            let size: Int64 = calculateSizes ? calculateSize(at: fullPath) : 0
            residuals.append(ResidualFile(path: fullPath, size: size, type: type))
          }
        }
      }
    }

    return residuals
  }

  /// 计算单个路径的体积（异步，供懒加载使用）
  public func calculateSizeAsync(at path: String) async -> Int64 {
    return await Task.detached(priority: .utility) {
      self.calculateSize(at: path)
    }.value
  }

  // MARK: - Private Methods

  private func scanApplicationsDirectory(at path: String, includeSizes: Bool = false) throws
    -> [InstalledApp]
  {
    var apps: [InstalledApp] = []
    let fileManager = FileManager.default

    guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
      return []
    }

    for item in contents {
      guard item.hasSuffix(".app") else { continue }

      let appPath = path + "/" + item
      let infoPlistPath = appPath + "/Contents/Info.plist"

      // 读取 Info.plist
      var bundleID = "unknown"
      if let plist = NSDictionary(contentsOfFile: infoPlistPath) {
        bundleID = plist["CFBundleIdentifier"] as? String ?? "unknown"
      }

      // 获取应用大小（仅在需要时计算）
      let size: Int64 = includeSizes ? calculateSize(at: appPath) : 0

      // 获取最后使用时间
      let lastUsed = try? fileManager.attributesOfItem(atPath: appPath)[.modificationDate] as? Date

      let app = InstalledApp(
        name: item,
        bundleID: bundleID,
        path: appPath,
        size: size,
        lastUsed: lastUsed
      )

      apps.append(app)
    }

    return apps
  }

  private func calculateSize(at path: String) -> Int64 {
    let fileManager = FileManager.default
    var size: Int64 = 0

    var isDir: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }

    if isDir.boolValue {
      if let enumerator = fileManager.enumerator(atPath: path) {
        for case let file as String in enumerator {
          let filePath = path + "/" + file
          if let attrs = try? fileManager.attributesOfItem(atPath: filePath) {
            size += attrs[.size] as? Int64 ?? 0
          }
        }
      }
    } else {
      if let attrs = try? fileManager.attributesOfItem(atPath: path) {
        size = attrs[.size] as? Int64 ?? 0
      }
    }

    return size
  }
}
