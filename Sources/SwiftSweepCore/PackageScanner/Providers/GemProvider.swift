import Foundation

/// Provider for Ruby gem packages
public struct GemProvider: PackageOperator, Sendable {
  public let id = "gem"
  public let displayName = "Ruby Gems"
  public let iconName = "diamond.fill"

  private let runner: ProcessRunner

  public var capabilities: Set<PackageCapability> {
    [.scan, .uninstall, .update, .cleanup, .outdated]
  }

  public var executablePath: String? {
    ToolLocator.find("gem")?.path
  }

  public init(runner: ProcessRunner = ProcessRunner(config: .packageFinder)) {
    self.runner = runner
  }

  public func scan() async -> PackageScanResult {
    let start = Date()

    // Find gem executable
    guard let gemURL = ToolLocator.find("gem") else {
      return .notInstalled(providerID: id, displayName: displayName)
    }

    // Run: gem list --local
    let result = await runner.run(
      executable: gemURL.path,
      arguments: ["list", "--local"],
      environment: ToolLocator.packageFinderEnvironment
    )

    let duration = Date().timeIntervalSince(start)

    // Check for errors
    guard result.reason == .exit, let exitCode = result.exitCode, exitCode == 0 else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
      return .failed(
        providerID: id,
        displayName: displayName,
        error: stderr.isEmpty ? "Command failed with exit code \(result.exitCode ?? -1)" : stderr
      )
    }

    // Parse output
    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
    let packages = parseGemOutput(stdout)

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
    guard let gemPath = executablePath else { return "" }
    return "\(gemPath) uninstall -a -x -- \(package.name)"
  }

  public func updateCommand(for package: Package) -> String {
    guard let gemPath = executablePath else { return "" }
    return "\(gemPath) update -- \(package.name)"
  }

  public func cleanupCommand() -> String {
    guard let gemPath = executablePath else { return "" }
    return "\(gemPath) cleanup"
  }

  public func uninstall(_ package: Package) async -> PackageOperationResult {
    guard let gemURL = ToolLocator.find("gem") else {
      return .failure("gem not found", package: package)
    }

    let command = uninstallCommand(for: package)
    let result = await runner.run(
      executable: gemURL.path,
      arguments: ["uninstall", "-a", "-x", "--", package.name],
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
    guard let gemURL = ToolLocator.find("gem") else {
      return .failure("gem not found", package: package)
    }

    let command = updateCommand(for: package)
    let result = await runner.run(
      executable: gemURL.path,
      arguments: ["update", "--", package.name],
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
    guard let gemURL = ToolLocator.find("gem") else {
      return .failure("gem not found")
    }

    let command = cleanupCommand()
    let result = await runner.run(
      executable: gemURL.path,
      arguments: ["cleanup"],
      environment: ToolLocator.packageFinderEnvironment
    )

    if result.reason == .exit, result.exitCode == 0 {
      let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
      return .success("Gem cleanup complete. \(stdout.split(separator: "\n").count) items processed", command: command)
    } else {
      let stderr = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
      return .failure(stderr, command: command)
    }
  }

  public func listOutdated() async -> [OutdatedPackage] {
    guard let gemURL = ToolLocator.find("gem") else { return [] }

    let result = await runner.run(
      executable: gemURL.path,
      arguments: ["outdated"],
      environment: ToolLocator.packageFinderEnvironment
    )

    guard result.reason == .exit, result.exitCode == 0 else { return [] }

    let stdout = String(data: result.stdout, encoding: .utf8) ?? ""

    // Format: "gemname (current < latest)"
    return stdout.split(separator: "\n").compactMap { line -> OutdatedPackage? in
      let lineStr = String(line)
      guard let parenStart = lineStr.firstIndex(of: "("),
        let parenEnd = lineStr.lastIndex(of: ")")
      else {
        return nil
      }

      let name = String(lineStr[..<parenStart]).trimmingCharacters(in: .whitespaces)
      let versionsStr = String(lineStr[lineStr.index(after: parenStart)..<parenEnd])
      let parts = versionsStr.components(separatedBy: " < ")
      guard parts.count == 2 else { return nil }

      return OutdatedPackage(
        name: name,
        currentVersion: parts[0].trimmingCharacters(in: .whitespaces),
        latestVersion: parts[1].trimmingCharacters(in: .whitespaces),
        providerID: id
      )
    }
  }

  // MARK: - Parsing

  private func parseGemOutput(_ output: String) -> [Package] {
    output
      .split(separator: "\n")
      .compactMap { line -> Package? in
        let lineStr = String(line)
        guard let parenStart = lineStr.firstIndex(of: "("),
          let parenEnd = lineStr.lastIndex(of: ")")
        else {
          return nil
        }

        let name = String(lineStr[..<parenStart]).trimmingCharacters(in: .whitespaces)
        let versionsStr = String(lineStr[lineStr.index(after: parenStart)..<parenEnd])

        let versions = versionsStr.split(separator: ",").map {
          String($0).trimmingCharacters(in: .whitespaces)
        }
        guard let firstVersion = versions.first, !name.isEmpty else {
          return nil
        }

        return Package(name: name, version: firstVersion, providerID: id)
      }
  }
}

