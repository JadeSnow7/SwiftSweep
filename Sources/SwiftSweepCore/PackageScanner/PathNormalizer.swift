import Foundation

// MARK: - PathNormalizer

/// 路径规范化器 - 将绝对路径转换为可移植格式
/// 使用依赖注入模式，保持值对象纯净
public struct PathNormalizer: Sendable {

  public let homeDir: String
  public let brewPrefix: String?

  public init(
    homeDir: String = ProcessInfo.processInfo.environment["HOME"] ?? "",
    brewPrefix: String? = nil
  ) {
    self.homeDir = homeDir
    self.brewPrefix = brewPrefix
  }

  /// 将绝对路径规范化为可移植格式
  /// - Parameter path: 绝对路径
  /// - Returns: 使用 $HOME, $HOMEBREW_PREFIX 等变量的规范化路径
  public func normalize(_ path: String) -> String {
    var result = path

    // 优先替换更长的路径 (brewPrefix 通常在 homeDir 内)
    if let bp = brewPrefix, !bp.isEmpty {
      result = result.replacingOccurrences(of: bp, with: "$HOMEBREW_PREFIX")
    }

    if !homeDir.isEmpty {
      result = result.replacingOccurrences(of: homeDir, with: "$HOME")
    }

    return result
  }

  /// 将规范化路径解析为绝对路径
  /// - Parameter normalized: 规范化路径
  /// - Returns: 当前机器上的绝对路径
  public func resolve(_ normalized: String) -> String {
    var result = normalized

    // 优先替换 $HOMEBREW_PREFIX (避免与 $HOME 冲突)
    if let bp = brewPrefix {
      result = result.replacingOccurrences(of: "$HOMEBREW_PREFIX", with: bp)
    }

    result = result.replacingOccurrences(of: "$HOME", with: homeDir)

    return result
  }
}

// MARK: - PortablePath

/// 可移植路径 - 支持跨机器共享的路径表示
public struct PortablePath: Hashable, Codable, Sendable {

  /// 规范化后的路径 (含 $HOME 等变量)
  public let normalized: String

  public init(_ absolutePath: String, normalizer: PathNormalizer) {
    self.normalized = normalizer.normalize(absolutePath)
  }

  public init(normalized: String) {
    self.normalized = normalized
  }

  /// 解析为当前机器的绝对路径
  public func resolve(with normalizer: PathNormalizer) -> String {
    normalizer.resolve(normalized)
  }
}

// MARK: - SystemInfo

/// 系统信息工具
public enum SystemInfo {

  /// 获取机器架构 (e.g., "arm64", "x86_64")
  public static var machineArch: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return sysctlMachine() ?? "unknown"
    #endif
  }

  /// 获取 macOS 版本 (e.g., "14.2")
  public static var osVersion: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion)"
  }

  /// 完整系统标识 (e.g., "macos-14.2-arm64")
  public static var systemId: String {
    "macos-\(osVersion)-\(machineArch)"
  }

  // MARK: - Private

  private static func sysctlMachine() -> String? {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    guard size > 0 else { return nil }

    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.machine", &machine, &size, nil, 0)
    return String(cString: machine)
  }
}

// MARK: - FingerprintContext

/// 指纹计算上下文
public struct FingerprintContext: Sendable {
  public let portablePath: PortablePath
  public let arch: String

  public init(portablePath: PortablePath, arch: String = SystemInfo.machineArch) {
    self.portablePath = portablePath
    self.arch = arch
  }

  /// 计算稳定指纹
  public func computeFingerprint() -> String {
    PackageIdentity.computeFingerprint(
      normalizedPath: portablePath.normalized,
      arch: arch
    )
  }
}
