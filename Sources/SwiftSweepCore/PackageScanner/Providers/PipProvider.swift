import Foundation

/// Provider for pip (Python) packages
public struct PipProvider: PackageOperator, Sendable {
  public let id = "pip"
  public let displayName = "pip (Python)"
  public let iconName = "cube.box.fill"

  private let runner: ProcessRunner

  public var capabilities: Set<PackageCapability> {
    [.scan, .uninstall, .update, .cleanup, .outdated]
  }

  public var executablePath: String? {
    ToolLocator.find("python3")?.path
  }

  public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
    self.runner = runner
  }

  // MARK: - Scan

  public func scan() async -> PackageScanResult {
    let start = Date()

    guard let pythonURL = ToolLocator.find("python3") else {
      return .notInstalled(providerID: id, displayName: displayName)
    }

    let result = await runner.run(
      executable: pythonURL.path,
      arguments: ["-m", "pip", "list", "--format=json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    let duration = Date().timeIntervalSince(start)

    guard result.reason == .exit, let exitCode = result.exitCode, exitCode == 0 else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
      return .failed(
        providerID: id,
        displayName: displayName,
        error: stderr.isEmpty ? "Command failed with exit code \(result.exitCode ?? -1)" : stderr
      )
    }

    guard let jsonData = result.stdout.isEmpty ? nil : result.stdout else {
      return PackageScanResult(
        providerID: id,
        displayName: displayName,
        status: .ok,
        packages: [],
        scanDuration: duration
      )
    }

    do {
      let packages = try parsePipJson(jsonData)
      return PackageScanResult(
        providerID: id,
        displayName: displayName,
        status: .ok,
        packages: packages,
        scanDuration: duration
      )
    } catch {
      return .failed(
        providerID: id,
        displayName: displayName,
        error: "Failed to parse pip output: \(error.localizedDescription)"
      )
    }
  }

  // MARK: - Operations

  public func uninstallCommand(for package: Package) -> String {
    guard let pythonPath = executablePath else { return "" }
    return "\(pythonPath) -m pip uninstall -y -- \(package.name)"
  }

  public func updateCommand(for package: Package) -> String {
    guard let pythonPath = executablePath else { return "" }
    return "\(pythonPath) -m pip install --upgrade -- \(package.name)"
  }

  public func cleanupCommand() -> String {
    guard let pythonPath = executablePath else { return "" }
    return "\(pythonPath) -m pip cache purge"
  }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    guard let pythonURL = ToolLocator.find("python3") else {
      return .failure("Python not found", package: package)
    }

    let command = uninstallCommand(for: package)
    let result = await runner.run(
      executable: pythonURL.path,
      arguments: ["-m", "pip", "uninstall", "-y", "--", package.name],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      return .success("Uninstalled \(package.name)", package: package, command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, package: package, command: command)
    }
  }

  public func update(_ package: Package) async -> PackageOperationResult {
    guard let pythonURL = ToolLocator.find("python3") else {
      return .failure("Python not found", package: package)
    }

    let command = updateCommand(for: package)
    let result = await runner.run(
      executable: pythonURL.path,
      arguments: ["-m", "pip", "install", "--upgrade", "--", package.name],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      return .success("Updated \(package.name)", package: package, command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, package: package, command: command)
    }
  }

  public func cleanup() async -> PackageOperationResult {
    guard let pythonURL = ToolLocator.find("python3") else {
      return .failure("Python not found")
    }

    let command = cleanupCommand()
    let result = await runner.run(
      executable: pythonURL.path,
      arguments: ["-m", "pip", "cache", "purge"],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      return .success("pip cache purged", command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, command: command)
    }
  }

  public func listOutdated() async -> [OutdatedPackage] {
    guard let pythonURL = ToolLocator.find("python3") else { return [] }

    let result = await runner.run(
      executable: pythonURL.path,
      arguments: ["-m", "pip", "list", "--outdated", "--format=json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return [] }

    guard let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]]
    else {
      return []
    }

    return array.compactMap { dict -> OutdatedPackage? in
      guard let name = dict["name"] as? String,
        let version = dict["version"] as? String,
        let latestVersion = dict["latest_version"] as? String
      else {
        return nil
      }
      return OutdatedPackage(
        name: name, currentVersion: version, latestVersion: latestVersion, providerID: id)
    }
  }

  // MARK: - Parsing

  private func parsePipJson(_ data: Data) throws -> [Package] {
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return array.compactMap { dict -> Package? in
      guard let name = dict["name"] as? String,
        let version = dict["version"] as? String
      else {
        return nil
      }

      // Note: pip installPath would require 'pip show' for each package
      // to get Location field. Skipping for performance - can add later.

      return Package(
        name: name,
        version: version,
        providerID: id,
        installPath: nil  // TODO: Implement with pip show
      )
    }
  }
}
