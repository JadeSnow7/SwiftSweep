import Foundation

// MARK: - Package Operation Types

/// Capabilities a package provider can support
public enum PackageCapability: String, CaseIterable, Sendable {
  case scan  // List installed packages
  case uninstall  // Remove packages
  case update  // Upgrade packages
  case cleanup  // Clean caches/old versions
  case outdated  // List outdated packages
}

/// Result of a package operation
public struct PackageOperationResult: Sendable {
  public let success: Bool
  public let message: String
  public let package: Package?
  public let command: String  // Full command that was executed

  public init(success: Bool, message: String, package: Package? = nil, command: String = "") {
    self.success = success
    self.message = message
    self.package = package
    self.command = command
  }

  public static func success(_ message: String, package: Package? = nil, command: String = "")
    -> PackageOperationResult
  {
    PackageOperationResult(success: true, message: message, package: package, command: command)
  }

  public static func failure(_ message: String, package: Package? = nil, command: String = "")
    -> PackageOperationResult
  {
    PackageOperationResult(success: false, message: message, package: package, command: command)
  }
}

/// Package with available update info
public struct OutdatedPackage: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let currentVersion: String
  public let latestVersion: String
  public let providerID: String

  public init(name: String, currentVersion: String, latestVersion: String, providerID: String) {
    self.id = "\(providerID):\(name)"
    self.name = name
    self.currentVersion = currentVersion
    self.latestVersion = latestVersion
    self.providerID = providerID
  }
}

// MARK: - PackageOperator Protocol

/// Extended protocol for package providers that support operations beyond scanning
public protocol PackageOperator: PackageProvider {
  /// Capabilities this provider supports
  var capabilities: Set<PackageCapability> { get }

  /// Path to the executable being used (for display in confirmation dialogs)
  var executablePath: String? { get }

  /// Generate the command that would be executed (for "Copy Command" feature)
  func uninstallCommand(for package: Package) -> String
  func updateCommand(for package: Package) -> String
  func cleanupCommand() -> String

  /// Execute package operations
  func uninstall(_ package: Package) async -> PackageOperationResult
  func update(_ package: Package) async -> PackageOperationResult
  func cleanup() async -> PackageOperationResult
  func listOutdated() async -> [OutdatedPackage]
}

// MARK: - Default Implementations

extension PackageOperator {
  /// Default: only scan capability
  public var capabilities: Set<PackageCapability> {
    [.scan]
  }

  public var executablePath: String? { nil }

  public func uninstallCommand(for package: Package) -> String { "" }
  public func updateCommand(for package: Package) -> String { "" }
  public func cleanupCommand() -> String { "" }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    .failure("Uninstall not supported by \(displayName)")
  }

  public func update(_ package: Package) async -> PackageOperationResult {
    .failure("Update not supported by \(displayName)")
  }

  public func cleanup() async -> PackageOperationResult {
    .failure("Cleanup not supported by \(displayName)")
  }

  public func listOutdated() async -> [OutdatedPackage] {
    []
  }
}
