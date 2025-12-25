import Foundation

// MARK: - PackageMetadata

/// 类型安全的包元数据
public struct PackageMetadata: Codable, Sendable {
  public let installPath: String?
  public let size: Int64?
  public let description: String?
  public let homepage: String?
  public let license: String?

  public init(
    installPath: String? = nil,
    size: Int64? = nil,
    description: String? = nil,
    homepage: String? = nil,
    license: String? = nil
  ) {
    self.installPath = installPath
    self.size = size
    self.description = description
    self.homepage = homepage
    self.license = license
  }
}

// MARK: - RawPackageRecord

/// 采集层返回的原始记录 (与 UI 解耦)
public struct RawPackageRecord: Sendable {
  public let identity: PackageIdentity
  public let rawJSON: Data

  public init(identity: PackageIdentity, rawJSON: Data = Data()) {
    self.identity = identity
    self.rawJSON = rawJSON
  }

  /// 解析元数据
  public func parseMetadata() throws -> PackageMetadata {
    guard !rawJSON.isEmpty else {
      return PackageMetadata()
    }
    return try JSONDecoder().decode(PackageMetadata.self, from: rawJSON)
  }
}

// MARK: - PackageNode

/// Graph 节点包装类型
public struct PackageNode: Identifiable, Sendable {
  public let identity: PackageIdentity
  public let metadata: PackageMetadata

  public var id: String { identity.canonicalKey }

  /// 生成兼容旧系统的 legacy ID
  public var legacyId: String {
    "\(identity.ecosystemId)_\(identity.name)"
  }

  public init(identity: PackageIdentity, metadata: PackageMetadata) {
    self.identity = identity
    self.metadata = metadata
  }

  /// 从现有 Package 转换
  public init(from package: Package, normalizer: PathNormalizer) {
    let fingerprint: String? = package.installPath.map { path in
      let portable = PortablePath(path, normalizer: normalizer)
      return FingerprintContext(portablePath: portable).computeFingerprint()
    }

    self.identity = PackageIdentity(
      ecosystemId: package.providerID,
      scope: nil,
      name: package.name,
      version: .exact(package.version),
      instanceFingerprint: fingerprint
    )

    self.metadata = PackageMetadata(
      installPath: package.installPath,
      size: package.size
    )
  }
}

// MARK: - DependencyEdge

/// 依赖边
public struct DependencyEdge: Sendable {
  public let source: PackageIdentity
  public let target: PackageRef
  public let constraint: VersionConstraint

  public init(source: PackageIdentity, target: PackageRef, constraint: VersionConstraint) {
    self.source = source
    self.target = target
    self.constraint = constraint
  }
}

// MARK: - IngestionResult

/// 采集结果 (支持部分成功)
public struct IngestionResult: Sendable {
  public let ecosystemId: String
  public let records: [RawPackageRecord]
  public let errors: [IngestionError]

  public var isPartial: Bool { !errors.isEmpty && !records.isEmpty }
  public var isSuccess: Bool { errors.isEmpty }
  public var isFailure: Bool { records.isEmpty && !errors.isEmpty }

  public init(
    ecosystemId: String,
    records: [RawPackageRecord] = [],
    errors: [IngestionError] = []
  ) {
    self.ecosystemId = ecosystemId
    self.records = records
    self.errors = errors
  }
}

/// 采集错误
public struct IngestionError: Error, Sendable {
  public let phase: String
  public let message: String
  public let recoverable: Bool

  public init(phase: String, message: String, recoverable: Bool = true) {
    self.phase = phase
    self.message = message
    self.recoverable = recoverable
  }
}
