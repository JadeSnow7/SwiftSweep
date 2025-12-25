import Foundation

// MARK: - Package Data

/// A package discovered by a package manager
public struct Package: Identifiable, Hashable, Sendable {
  public let id: String  // "{providerID}_{name}"
  public let name: String
  public let version: String
  public let providerID: String

  // Phase 1.2: Extended metadata
  public let installPath: String?  // Installation directory path
  public let size: Int64?  // Package size in bytes

  public init(
    name: String,
    version: String,
    providerID: String,
    installPath: String? = nil,
    size: Int64? = nil
  ) {
    self.id = "\(providerID)_\(name)"
    self.name = name
    self.version = version
    self.providerID = providerID
    self.installPath = installPath
    self.size = size
  }
}

// MARK: - Scan Result

/// Result of scanning a package manager
public struct PackageScanResult: Sendable {
  public enum Status: Sendable, Equatable {
    case ok
    case notInstalled
    case failed(String)
  }

  public let providerID: String
  public let displayName: String
  public let status: Status
  public let packages: [Package]
  public let scanDuration: TimeInterval
  public let warning: String?  // Non-fatal issues (e.g., npm non-zero exit with valid output)

  public init(
    providerID: String,
    displayName: String,
    status: Status,
    packages: [Package] = [],
    scanDuration: TimeInterval = 0,
    warning: String? = nil
  ) {
    self.providerID = providerID
    self.displayName = displayName
    self.status = status
    self.packages = packages
    self.scanDuration = scanDuration
    self.warning = warning
  }

  /// Helper for creating "not installed" result
  public static func notInstalled(providerID: String, displayName: String) -> PackageScanResult {
    PackageScanResult(providerID: providerID, displayName: displayName, status: .notInstalled)
  }

  /// Helper for creating "failed" result
  public static func failed(providerID: String, displayName: String, error: String)
    -> PackageScanResult
  {
    PackageScanResult(providerID: providerID, displayName: displayName, status: .failed(error))
  }
}

// MARK: - Package Provider Protocol

/// Protocol for package manager providers
public protocol PackageProvider: Sendable {
  /// Unique identifier for this provider
  var id: String { get }

  /// Human-readable display name
  var displayName: String { get }

  /// SF Symbol name for the icon
  var iconName: String { get }

  /// Scan for packages. Returns a result (never throws).
  func scan() async -> PackageScanResult
}
