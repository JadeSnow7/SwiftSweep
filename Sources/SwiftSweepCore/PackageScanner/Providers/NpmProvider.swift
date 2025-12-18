import Foundation

/// Provider for npm global packages
public struct NpmProvider: PackageOperator, Sendable {
  public let id = "npm"
  public let displayName = "npm Global"
  public let iconName = "shippingbox.fill"

  private let runner: ProcessRunner

  public var capabilities: Set<PackageCapability> {
    [.scan, .uninstall, .update, .cleanup, .outdated]
  }

  public var executablePath: String? {
    ToolLocator.find("npm")?.path
  }

  public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
    self.runner = runner
  }

  // MARK: - Scan

  public func scan() async -> PackageScanResult {
    let start = Date()

    guard let npmURL = ToolLocator.find("npm") else {
      return .notInstalled(providerID: id, displayName: displayName)
    }

    let result = await runner.run(
      executable: npmURL.path,
      arguments: ["ls", "-g", "--depth=0", "--json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    let duration = Date().timeIntervalSince(start)

    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
    let stderr = String(data: result.stderr, encoding: .utf8) ?? ""

    guard let jsonData = stdout.data(using: .utf8) else {
      return .failed(providerID: id, displayName: displayName, error: "No output from npm")
    }

    do {
      let packages = try parseNpmJson(jsonData)
      var warning: String? = nil
      if result.exitCode != 0 && !stderr.isEmpty {
        warning = "npm reported warnings: \(stderr.prefix(200))"
      }

      return PackageScanResult(
        providerID: id,
        displayName: displayName,
        status: .ok,
        packages: packages,
        scanDuration: duration,
        warning: warning
      )
    } catch {
      return .failed(
        providerID: id,
        displayName: displayName,
        error: "Failed to parse npm output: \(error.localizedDescription)"
      )
    }
  }

  // MARK: - Operations

  public func uninstallCommand(for package: Package) -> String {
    guard let npmPath = executablePath else { return "" }
    return "\(npmPath) uninstall -g -- \(package.name)"
  }

  public func updateCommand(for package: Package) -> String {
    guard let npmPath = executablePath else { return "" }
    return "\(npmPath) update -g -- \(package.name)"
  }

  public func cleanupCommand() -> String {
    guard let npmPath = executablePath else { return "" }
    return "\(npmPath) cache clean --force"
  }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    guard let npmURL = ToolLocator.find("npm") else {
      return .failure("npm not found", package: package)
    }

    let command = uninstallCommand(for: package)
    let result = await runner.run(
      executable: npmURL.path,
      arguments: ["uninstall", "-g", "--", package.name],
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
    guard let npmURL = ToolLocator.find("npm") else {
      return .failure("npm not found", package: package)
    }

    let command = updateCommand(for: package)
    let result = await runner.run(
      executable: npmURL.path,
      arguments: ["update", "-g", "--", package.name],
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
    guard let npmURL = ToolLocator.find("npm") else {
      return .failure("npm not found")
    }

    let command = cleanupCommand()
    let result = await runner.run(
      executable: npmURL.path,
      arguments: ["cache", "clean", "--force"],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      return .success("npm cache cleaned", command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, command: command)
    }
  }

  public func listOutdated() async -> [OutdatedPackage] {
    guard let npmURL = ToolLocator.find("npm") else { return [] }

    let result = await runner.run(
      executable: npmURL.path,
      arguments: ["outdated", "-g", "--json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    // npm outdated returns exit code 1 when packages are outdated
    guard
      let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: [String: Any]]
    else {
      return []
    }

    return json.compactMap { (name, info) -> OutdatedPackage? in
      guard let current = info["current"] as? String,
        let latest = info["latest"] as? String
      else {
        return nil
      }
      return OutdatedPackage(
        name: name, currentVersion: current, latestVersion: latest, providerID: id)
    }
  }

  // MARK: - Parsing

  private func parseNpmJson(_ data: Data) throws -> [Package] {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let dependencies = json["dependencies"] as? [String: Any]
    else {
      return []
    }

    return dependencies.compactMap { (name, value) -> Package? in
      guard let info = value as? [String: Any],
        let version = info["version"] as? String
      else {
        return nil
      }
      return Package(name: name, version: version, providerID: id)
    }
  }
}
