import CryptoKit
import Foundation

// MARK: - PackageIdentity

/// 全局唯一的包标识符
/// 用于 Graph 节点、Snapshot Key、Cache Key
public struct PackageIdentity: Hashable, Sendable {

  /// 生态系统 ID (e.g., "homebrew_formula", "npm", "pip")
  public let ecosystemId: String

  /// 命名空间/域 (e.g., "@types", "homebrew/core")
  public let scope: String?

  /// 标准化包名 (e.g., "openssl", "react")
  public let name: String

  /// 已解析的版本
  public let version: ResolvedVersion

  /// 实例指纹 (基于 PortablePath 的稳定哈希)
  public let instanceFingerprint: String?

  public init(
    ecosystemId: String,
    scope: String? = nil,
    name: String,
    version: ResolvedVersion,
    instanceFingerprint: String? = nil
  ) {
    self.ecosystemId = ecosystemId
    self.scope = scope
    self.name = name
    self.version = version
    self.instanceFingerprint = instanceFingerprint
  }

  // MARK: - Keys

  /// 逻辑键 (忽略实例) - 用于依赖图边连接
  public var logicalKey: String {
    let parts = [
      ecosystemId,
      scope.map(Self.escape) ?? "",
      Self.escape(name),
      version.normalized,
    ]
    return parts.joined(separator: "::")
  }

  /// 规范键 (含实例) - 用于 Snapshot/Cache 唯一性
  public var canonicalKey: String {
    guard let fp = instanceFingerprint else { return logicalKey }
    return "\(logicalKey)#\(fp)"
  }

  // MARK: - Fingerprint

  /// 从 PortablePath 计算稳定指纹 (SHA256 前 8 字节)
  public static func computeFingerprint(
    normalizedPath: String,
    arch: String
  ) -> String {
    let input = "\(normalizedPath)|\(arch)"
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Escaping

  /// URL-safe 编码特殊字符
  private static func escape(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
  }
}

// MARK: - Codable

extension PackageIdentity: Codable {
  enum CodingKeys: String, CodingKey {
    case ecosystemId = "ecosystem"
    case scope
    case name
    case version
    case instanceFingerprint = "fingerprint"
  }
}

// MARK: - ResolvedVersion

/// 已安装的具体版本
public enum ResolvedVersion: Hashable, Sendable {
  case exact(String)
  case unknown

  public var normalized: String {
    switch self {
    case .exact(let v): return v
    case .unknown: return "unknown"
    }
  }

  public var isKnown: Bool {
    if case .unknown = self { return false }
    return true
  }
}

extension ResolvedVersion: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let str = try container.decode(String.self)
    self = str == "unknown" ? .unknown : .exact(str)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(normalized)
  }
}

// MARK: - VersionConstraint

/// 依赖约束 (用于 package.json 等)
public enum VersionConstraint: Hashable, Sendable {
  case exact(String)  // "1.2.3"
  case range(String)  // "^1.0.0", ">=2.0"
  case any  // "*"

  public var description: String {
    switch self {
    case .exact(let v): return v
    case .range(let r): return r
    case .any: return "*"
    }
  }
}

extension VersionConstraint: Codable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let str = try container.decode(String.self)
    if str == "*" {
      self = .any
    } else if str.hasPrefix("^") || str.hasPrefix("~") || str.hasPrefix(">") || str.hasPrefix("<") {
      self = .range(str)
    } else {
      self = .exact(str)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}

// MARK: - PackageRef

/// 轻量级包引用 (不含版本和指纹)
public struct PackageRef: Hashable, Codable, Sendable {
  public let ecosystemId: String
  public let scope: String?
  public let name: String

  public init(ecosystemId: String, scope: String? = nil, name: String) {
    self.ecosystemId = ecosystemId
    self.scope = scope
    self.name = name
  }

  public var key: String {
    let sc = scope.map { "\($0)/" } ?? ""
    return "\(ecosystemId)::\(sc)\(name)"
  }

  /// 从 PackageIdentity 创建 Ref
  public init(from identity: PackageIdentity) {
    self.ecosystemId = identity.ecosystemId
    self.scope = identity.scope
    self.name = identity.name
  }
}
