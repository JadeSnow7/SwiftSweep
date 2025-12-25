import Foundation

/// Provider for Homebrew formula packages
public struct HomebrewFormulaProvider: PackageOperator, Sendable {
  public let id = "homebrew_formula"
  public let displayName = "Homebrew Formulae"
  public let iconName = "mug.fill"

  private let runner: ProcessRunner

  public var capabilities: Set<PackageCapability> {
    [.scan, .uninstall, .update, .cleanup, .outdated]
  }

  public var executablePath: String? {
    ToolLocator.find("brew")?.path
  }

  public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
    self.runner = runner
  }

  // MARK: - Scan

  public func scan() async -> PackageScanResult {
    let start = Date()

    guard let brewURL = ToolLocator.find("brew") else {
      return .notInstalled(providerID: id, displayName: displayName)
    }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["list", "--formula", "--versions"],
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

    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
    // Get Homebrew prefix for installPath
    let brewPrefix = await getBrewPrefix()
    let packages = parseBrewOutput(stdout, brewPrefix: brewPrefix)

    return PackageScanResult(
      providerID: id,
      displayName: displayName,
      status: .ok,
      packages: packages,
      scanDuration: duration
    )
  }

  // MARK: - Operations

  public func uninstallCommand(for package: Package) -> String {
    guard let brewPath = executablePath else { return "" }
    return "\(brewPath) uninstall --force -- \(package.name)"
  }

  public func updateCommand(for package: Package) -> String {
    guard let brewPath = executablePath else { return "" }
    return "\(brewPath) upgrade -- \(package.name)"
  }

  public func cleanupCommand() -> String {
    guard let brewPath = executablePath else { return "" }
    return "\(brewPath) cleanup --prune=all"
  }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    guard let brewURL = ToolLocator.find("brew") else {
      return .failure("Homebrew not found", package: package)
    }

    let command = uninstallCommand(for: package)
    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["uninstall", "--force", "--", package.name],
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
    guard let brewURL = ToolLocator.find("brew") else {
      return .failure("Homebrew not found", package: package)
    }

    let command = updateCommand(for: package)
    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["upgrade", "--", package.name],
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
    guard let brewURL = ToolLocator.find("brew") else {
      return .failure("Homebrew not found")
    }

    let command = cleanupCommand()
    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["cleanup", "--prune=all"],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
      return .success(
        "Cleanup complete. \(stdout.split(separator: "\n").count) items processed", command: command
      )
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, command: command)
    }
  }

  public func listOutdated() async -> [OutdatedPackage] {
    guard let brewURL = ToolLocator.find("brew") else { return [] }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["outdated", "--json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return [] }

    // Parse JSON: {"formulae": [{"name": "...", "installed_versions": ["..."], "current_version": "..."}]}
    guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
      let formulae = json["formulae"] as? [[String: Any]]
    else {
      return []
    }

    return formulae.compactMap { item -> OutdatedPackage? in
      guard let name = item["name"] as? String,
        let installedVersions = item["installed_versions"] as? [String],
        let currentVersion = item["current_version"] as? String,
        let installed = installedVersions.first
      else {
        return nil
      }
      return OutdatedPackage(
        name: name, currentVersion: installed, latestVersion: currentVersion, providerID: id)
    }
  }

  // MARK: - Parsing

  /// Get Homebrew installation prefix (e.g., "/opt/homebrew" or "/usr/local")
  private func getBrewPrefix() async -> String? {
    guard let brewURL = ToolLocator.find("brew") else { return nil }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["--prefix"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return nil }

    let prefix = String(data: result.stdout, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return prefix?.isEmpty == false ? prefix : nil
  }

  private func parseBrewOutput(_ output: String, brewPrefix: String?) -> [Package] {
    output
      .split(separator: "\n")
      .compactMap { line -> Package? in
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let name = String(parts[0])
        let version = String(parts[1])

        // Construct installPath: <prefix>/Cellar/<name>/<version>
        let installPath: String?
        if let prefix = brewPrefix {
          installPath = "\(prefix)/Cellar/\(name)/\(version)"
        } else {
          installPath = nil
        }

        return Package(
          name: name,
          version: version,
          providerID: id,
          installPath: installPath
        )
      }
  }
}

/// Provider for Homebrew cask packages
public struct HomebrewCaskProvider: PackageOperator, Sendable {
  public let id = "homebrew_cask"
  public let displayName = "Homebrew Casks"
  public let iconName = "macwindow"

  private let runner: ProcessRunner

  public var capabilities: Set<PackageCapability> {
    [.scan, .uninstall, .update, .outdated]
  }

  public var executablePath: String? {
    ToolLocator.find("brew")?.path
  }

  public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
    self.runner = runner
  }

  public func scan() async -> PackageScanResult {
    let start = Date()

    guard let brewURL = ToolLocator.find("brew") else {
      return .notInstalled(providerID: id, displayName: displayName)
    }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["list", "--cask", "--versions"],
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

    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
    // Get Homebrew prefix for installPath
    let brewPrefix = await getBrewPrefix()
    let packages = parseBrewCaskOutput(stdout, brewPrefix: brewPrefix)

    return PackageScanResult(
      providerID: id,
      displayName: displayName,
      status: .ok,
      packages: packages,
      scanDuration: duration
    )
  }

  public func uninstallCommand(for package: Package) -> String {
    guard let brewPath = executablePath else { return "" }
    return "\(brewPath) uninstall --cask --force -- \(package.name)"
  }

  public func updateCommand(for package: Package) -> String {
    guard let brewPath = executablePath else { return "" }
    return "\(brewPath) upgrade --cask -- \(package.name)"
  }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    guard let brewURL = ToolLocator.find("brew") else {
      return .failure("Homebrew not found", package: package)
    }

    let command = uninstallCommand(for: package)
    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["uninstall", "--cask", "--force", "--", package.name],
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
    guard let brewURL = ToolLocator.find("brew") else {
      return .failure("Homebrew not found", package: package)
    }

    let command = updateCommand(for: package)
    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["upgrade", "--cask", "--", package.name],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      return .success("Updated \(package.name)", package: package, command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, package: package, command: command)
    }
  }

  public func listOutdated() async -> [OutdatedPackage] {
    guard let brewURL = ToolLocator.find("brew") else { return [] }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["outdated", "--cask", "--json"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return [] }

    guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
      let casks = json["casks"] as? [[String: Any]]
    else {
      return []
    }

    return casks.compactMap { item -> OutdatedPackage? in
      guard let name = item["name"] as? String,
        let installed = item["installed_versions"] as? String,
        let current = item["current_version"] as? String
      else {
        return nil
      }
      return OutdatedPackage(
        name: name, currentVersion: installed, latestVersion: current, providerID: id)
    }
  }

  /// Get Homebrew installation prefix
  private func getBrewPrefix() async -> String? {
    guard let brewURL = ToolLocator.find("brew") else { return nil }

    let result = await runner.run(
      executable: brewURL.path,
      arguments: ["--prefix"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return nil }

    let prefix = String(data: result.stdout, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return prefix?.isEmpty == false ? prefix : nil
  }

  private func parseBrewCaskOutput(_ output: String, brewPrefix: String?) -> [Package] {
    output
      .split(separator: "\n")
      .compactMap { line -> Package? in
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let name = String(parts[0])
        let version = String(parts[1])

        // Construct installPath: <prefix>/Caskroom/<name>/<version>
        let installPath: String?
        if let prefix = brewPrefix {
          installPath = "\(prefix)/Caskroom/\(name)/\(version)"
        } else {
          installPath = nil
        }

        return Package(
          name: name,
          version: version,
          providerID: id,
          installPath: installPath
        )
      }
  }
}
