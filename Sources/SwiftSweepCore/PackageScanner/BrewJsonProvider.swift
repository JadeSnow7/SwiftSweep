import Foundation

// MARK: - PackageMetadataProvider Protocol

/// 负责从源头采集原始元数据的协议
public protocol PackageMetadataProvider: Sendable {
  /// 生态系统 ID
  var ecosystemId: String { get }

  /// 获取全量已安装包
  func fetchInstalledRecords() async -> IngestionResult
}

// MARK: - BrewJsonProvider

/// 基于 JSON 的 Homebrew Formula 采集器
public actor BrewJsonProvider: PackageMetadataProvider {
  public let ecosystemId = "homebrew_formula"

  private let brewPath: String
  private let normalizer: PathNormalizer

  public init(
    brewPath: String = "/opt/homebrew/bin/brew",
    normalizer: PathNormalizer = PathNormalizer()
  ) {
    self.brewPath = brewPath
    self.normalizer = normalizer
  }

  public func fetchInstalledRecords() async -> IngestionResult {
    do {
      // 执行 brew info --json=v2 --installed
      let jsonData = try await executeBrewCommand()

      // 解析 JSON
      let records = try parseBrewJson(jsonData)

      return IngestionResult(
        ecosystemId: ecosystemId,
        records: records
      )
    } catch {
      return IngestionResult(
        ecosystemId: ecosystemId,
        errors: [
          IngestionError(
            phase: "fetch",
            message: error.localizedDescription,
            recoverable: true
          )
        ]
      )
    }
  }

  // MARK: - Private

  private func findBrewPath() -> String {
    // Check common brew locations
    let paths = [
      "/opt/homebrew/bin/brew",  // Apple Silicon
      "/usr/local/bin/brew",  // Intel
      brewPath,
    ]

    for path in paths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    return brewPath
  }

  private func executeBrewCommand() async throws -> Data {
    let actualBrewPath = findBrewPath()

    guard FileManager.default.fileExists(atPath: actualBrewPath) else {
      throw IngestionError(
        phase: "execute",
        message: "brew not found at \(actualBrewPath)",
        recoverable: true
      )
    }

    // Execute in detached task to avoid blocking actor
    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: actualBrewPath)
      process.arguments = ["info", "--json=v2", "--installed"]
      process.environment = ToolLocator.packageFinderEnvironment

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      // Read data BEFORE waitUntilExit to prevent pipe buffer deadlock
      var outputData = Data()
      stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        outputData.append(handle.availableData)
      }

      try process.run()

      // Set timeout of 60 seconds
      let deadline = Date().addingTimeInterval(60)
      while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }

      if process.isRunning {
        process.terminate()
        throw IngestionError(
          phase: "execute",
          message: "brew command timed out after 60s",
          recoverable: true
        )
      }

      // Read any remaining data
      stdoutPipe.fileHandleForReading.readabilityHandler = nil
      outputData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())

      // Allow non-zero exit if we have output (brew might return warnings)
      if outputData.isEmpty && process.terminationStatus != 0 {
        throw IngestionError(
          phase: "execute",
          message: "brew command failed with code \(process.terminationStatus)",
          recoverable: true
        )
      }

      return outputData
    }.value
  }

  private func parseBrewJson(_ data: Data) throws -> [RawPackageRecord] {
    let decoder = JSONDecoder()
    let response = try decoder.decode(BrewJsonResponse.self, from: data)

    var records: [RawPackageRecord] = []

    for formula in response.formulae {
      guard let installed = formula.installed.first else { continue }

      // 计算 installPath
      let brewPrefix = getBrewPrefix()
      let cellarPath = "\(brewPrefix)/Cellar/\(formula.name)/\(installed.version)"

      // 计算 fingerprint
      let portable = PortablePath(cellarPath, normalizer: normalizer)
      let fingerprint = PackageIdentity.computeFingerprint(
        normalizedPath: portable.normalized,
        arch: SystemInfo.machineArch
      )

      let identity = PackageIdentity(
        ecosystemId: ecosystemId,
        scope: formula.tap,
        name: formula.name,
        version: .exact(installed.version),
        instanceFingerprint: fingerprint
      )

      // 构建元数据 JSON
      let metadata = BrewPackageMetadata(
        installPath: cellarPath,
        description: formula.description,
        homepage: formula.homepage,
        license: formula.license,
        dependencies: formula.dependencies,
        buildDependencies: formula.buildDependencies,
        installedOnRequest: installed.installedOnRequest,
        installedAsDependency: installed.installedAsDependency,
        linkedKeg: formula.linkedKeg,
        pinned: formula.pinned,
        outdated: formula.outdated
      )

      let metadataData = try JSONEncoder().encode(metadata)

      records.append(
        RawPackageRecord(
          identity: identity,
          rawJSON: metadataData
        ))
    }

    return records
  }

  private func getBrewPrefix() -> String {
    // Determine prefix based on which brew path exists
    if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
      return "/opt/homebrew"
    } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
      return "/usr/local"
    }
    return "/opt/homebrew"
  }
}

// MARK: - Brew JSON Models

private struct BrewJsonResponse: Decodable {
  let formulae: [BrewFormula]
  let casks: [BrewCask]?

  enum CodingKeys: String, CodingKey {
    case formulae
    case casks
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    formulae = try container.decodeIfPresent([BrewFormula].self, forKey: .formulae) ?? []
    casks = try container.decodeIfPresent([BrewCask].self, forKey: .casks)
  }
}

private struct BrewFormula: Decodable {
  let name: String
  let fullName: String
  let tap: String
  let description: String?
  let license: String?
  let homepage: String
  let dependencies: [String]
  let buildDependencies: [String]
  let installed: [BrewInstalled]
  let linkedKeg: String?
  let pinned: Bool
  let outdated: Bool

  enum CodingKeys: String, CodingKey {
    case name
    case fullName = "full_name"
    case tap
    case description = "desc"
    case license
    case homepage
    case dependencies
    case buildDependencies = "build_dependencies"
    case installed
    case linkedKeg = "linked_keg"
    case pinned
    case outdated
  }
}

private struct BrewInstalled: Decodable {
  let version: String
  let installedOnRequest: Bool
  let installedAsDependency: Bool
  let runtimeDependencies: [BrewRuntimeDep]?

  enum CodingKeys: String, CodingKey {
    case version
    case installedOnRequest = "installed_on_request"
    case installedAsDependency = "installed_as_dependency"
    case runtimeDependencies = "runtime_dependencies"
  }
}

private struct BrewRuntimeDep: Decodable {
  let fullName: String
  let version: String
  let declaredDirectly: Bool

  enum CodingKeys: String, CodingKey {
    case fullName = "full_name"
    case version
    case declaredDirectly = "declared_directly"
  }
}

private struct BrewCask: Decodable {
  let token: String
  let name: [String]
  let version: String
}

// MARK: - Brew Package Metadata

/// Homebrew 特定的元数据
public struct BrewPackageMetadata: Codable, Sendable {
  public let installPath: String?
  public let description: String?
  public let homepage: String?
  public let license: String?
  public let dependencies: [String]
  public let buildDependencies: [String]
  public let installedOnRequest: Bool
  public let installedAsDependency: Bool
  public let linkedKeg: String?
  public let pinned: Bool
  public let outdated: Bool
}
