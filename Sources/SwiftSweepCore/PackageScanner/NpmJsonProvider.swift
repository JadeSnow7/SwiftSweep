import Foundation

// MARK: - NpmJsonProvider

/// 基于 JSON 的 npm 全局包采集器
public actor NpmJsonProvider: PackageMetadataProvider {
  public let ecosystemId = "npm"

  private let npmPath: String
  private let normalizer: PathNormalizer

  public init(
    npmPath: String = "/usr/local/bin/npm",
    normalizer: PathNormalizer = PathNormalizer()
  ) {
    self.npmPath = npmPath
    self.normalizer = normalizer
  }

  public func fetchInstalledRecords() async -> IngestionResult {
    do {
      // 获取 npm 全局根目录
      let globalRoot = try await getNpmGlobalRoot()

      // 执行 npm ls -g --json --depth=0
      let jsonData = try await executeNpmCommand()

      // 解析 JSON
      let records = try parseNpmJson(jsonData, globalRoot: globalRoot)

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

  private func executeNpmCommand() async throws -> Data {
    let npmExecutable = findNpmPath()

    guard FileManager.default.fileExists(atPath: npmExecutable) else {
      throw IngestionError(
        phase: "execute",
        message: "npm not found",
        recoverable: true
      )
    }

    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: npmExecutable)
      process.arguments = ["ls", "-g", "--json", "--depth=0"]
      process.environment = ToolLocator.packageFinderEnvironment

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      // Read data BEFORE wait to prevent pipe buffer deadlock
      var outputData = Data()
      stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        outputData.append(handle.availableData)
      }

      try process.run()

      // Timeout of 30 seconds for npm
      let deadline = Date().addingTimeInterval(30)
      while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }

      if process.isRunning {
        process.terminate()
        throw IngestionError(
          phase: "execute",
          message: "npm command timed out after 30s",
          recoverable: true
        )
      }

      // Read remaining data
      stdoutPipe.fileHandleForReading.readabilityHandler = nil
      outputData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())

      // npm ls often returns exit code 1 for unmet peer deps, but output is still valid JSON
      // Only fail if no output at all
      if outputData.isEmpty {
        throw IngestionError(
          phase: "execute",
          message: "npm produced no output (exit: \(process.terminationStatus))",
          recoverable: true
        )
      }

      return outputData
    }.value
  }

  private func getNpmGlobalRoot() async throws -> String {
    let npmExecutable = findNpmPath()

    guard FileManager.default.fileExists(atPath: npmExecutable) else {
      return "/usr/local/lib/node_modules"
    }

    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: npmExecutable)
      process.arguments = ["root", "-g"]
      process.environment = ToolLocator.packageFinderEnvironment

      let pipe = Pipe()
      process.standardOutput = pipe

      var outputData = Data()
      pipe.fileHandleForReading.readabilityHandler = { handle in
        outputData.append(handle.availableData)
      }

      try process.run()

      let deadline = Date().addingTimeInterval(10)
      while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
      }

      pipe.fileHandleForReading.readabilityHandler = nil
      outputData.append(pipe.fileHandleForReading.readDataToEndOfFile())

      return String(data: outputData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
        ?? "/usr/local/lib/node_modules"
    }.value
  }

  private func findNpmPath() -> String {
    let home = NSHomeDirectory()
    // Check common locations including nvm, volta, fnm
    let paths = [
      "/opt/homebrew/bin/npm",
      "/usr/local/bin/npm",
      "\(home)/.nvm/current/bin/npm",
      "\(home)/.volta/bin/npm",
      "\(home)/.fnm/current/bin/npm",
      "\(home)/.local/bin/npm",
      npmPath,
    ]

    for path in paths {
      if FileManager.default.fileExists(atPath: path) {
        return path
      }
    }

    return npmPath
  }

  private func parseNpmJson(_ data: Data, globalRoot: String) throws -> [RawPackageRecord] {
    let decoder = JSONDecoder()
    let response = try decoder.decode(NpmJsonResponse.self, from: data)

    var records: [RawPackageRecord] = []

    for (name, info) in response.dependencies ?? [:] {
      // 解析 scope (e.g., @types/react -> scope: @types, name: react)
      let (scope, packageName) = parseNpmPackageName(name)

      // 计算 installPath
      let installPath = "\(globalRoot)/\(name)"

      // 计算 fingerprint
      let portable = PortablePath(installPath, normalizer: normalizer)
      let fingerprint = PackageIdentity.computeFingerprint(
        normalizedPath: portable.normalized,
        arch: SystemInfo.machineArch
      )

      let identity = PackageIdentity(
        ecosystemId: ecosystemId,
        scope: scope,
        name: packageName,
        version: .exact(info.version),
        instanceFingerprint: fingerprint
      )

      // 构建元数据
      let metadata = NpmPackageMetadata(
        installPath: installPath,
        overridden: info.overridden ?? false
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

  private func parseNpmPackageName(_ fullName: String) -> (scope: String?, name: String) {
    if fullName.hasPrefix("@") {
      let parts = fullName.split(separator: "/", maxSplits: 1)
      if parts.count == 2 {
        return (String(parts[0]), String(parts[1]))
      }
    }
    return (nil, fullName)
  }
}

// MARK: - npm JSON Models

private struct NpmJsonResponse: Decodable {
  let name: String?
  let dependencies: [String: NpmDependencyInfo]?
}

private struct NpmDependencyInfo: Decodable {
  let version: String
  let overridden: Bool?
}

// MARK: - npm Package Metadata

/// npm 特定的元数据
public struct NpmPackageMetadata: Codable, Sendable {
  public let installPath: String?
  public let overridden: Bool
}
