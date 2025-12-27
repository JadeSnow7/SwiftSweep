import Foundation

// MARK: - PipMetadataProvider

/// 基于 .dist-info/METADATA 的 Python 包采集器
public actor PipMetadataProvider: PackageMetadataProvider {
  public let ecosystemId = "pip"

  private let normalizer: PathNormalizer

  public init(normalizer: PathNormalizer = PathNormalizer()) {
    self.normalizer = normalizer
  }

  public func fetchInstalledRecords() async -> IngestionResult {
    do {
      let records = try await scanSitePackages()
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

  private func scanSitePackages() async throws -> [RawPackageRecord] {
    // Find site-packages directories
    let sitePackagesPaths = findSitePackagesPaths()

    guard !sitePackagesPaths.isEmpty else {
      throw IngestionError(
        phase: "scan",
        message: "No site-packages directories found",
        recoverable: true
      )
    }

    var records: [RawPackageRecord] = []

    for sitePackages in sitePackagesPaths {
      let fm = FileManager.default
      guard let contents = try? fm.contentsOfDirectory(atPath: sitePackages) else { continue }

      for item in contents {
        guard item.hasSuffix(".dist-info") else { continue }

        let distInfoPath = (sitePackages as NSString).appendingPathComponent(item)
        let metadataPath = (distInfoPath as NSString).appendingPathComponent("METADATA")

        guard fm.fileExists(atPath: metadataPath),
          let metadataContent = try? String(contentsOfFile: metadataPath, encoding: .utf8)
        else { continue }

        // Parse METADATA file
        guard let parsed = parseMetadata(metadataContent) else { continue }

        // Calculate package path (without .dist-info)
        let _ = String(item.dropLast(".dist-info".count))
        let packagePath = sitePackages

        // Calculate size
        let size = calculatePackageSize(name: parsed.name, in: sitePackages)

        // Create identity
        let portable = PortablePath(packagePath, normalizer: normalizer)
        let fingerprint = PackageIdentity.computeFingerprint(
          normalizedPath: portable.normalized,
          arch: SystemInfo.machineArch
        )

        let identity = PackageIdentity(
          ecosystemId: ecosystemId,
          scope: nil,
          name: parsed.name,
          version: .exact(parsed.version),
          instanceFingerprint: fingerprint
        )

        // Build metadata
        let metadata = PipPackageMetadata(
          installPath: distInfoPath,
          size: size,
          summary: parsed.summary,
          author: parsed.author,
          requiresDist: parsed.requiresDist
        )

        let metadataData = try JSONEncoder().encode(metadata)

        records.append(
          RawPackageRecord(
            identity: identity,
            rawJSON: metadataData
          ))
      }
    }

    return records
  }

  private func findSitePackagesPaths() -> [String] {
    var paths: [String] = []
    let home = NSHomeDirectory()
    let fm = FileManager.default

    // Common Python site-packages locations
    let candidates = [
      // Homebrew Python
      "/opt/homebrew/lib/python3.12/site-packages",
      "/opt/homebrew/lib/python3.11/site-packages",
      "/opt/homebrew/lib/python3.10/site-packages",
      "/opt/homebrew/lib/python3.9/site-packages",
      // Intel Homebrew
      "/usr/local/lib/python3.12/site-packages",
      "/usr/local/lib/python3.11/site-packages",
      "/usr/local/lib/python3.10/site-packages",
      // User site-packages
      "\(home)/Library/Python/3.12/lib/python/site-packages",
      "\(home)/Library/Python/3.11/lib/python/site-packages",
      "\(home)/Library/Python/3.10/lib/python/site-packages",
      "\(home)/.local/lib/python3.12/site-packages",
      "\(home)/.local/lib/python3.11/site-packages",
      "\(home)/.local/lib/python3.10/site-packages",
      // pyenv
      "\(home)/.pyenv/versions",
    ]

    for path in candidates {
      if fm.fileExists(atPath: path) {
        paths.append(path)
      }
    }

    return paths
  }

  private func parseMetadata(_ content: String) -> (
    name: String, version: String, summary: String?, author: String?, requiresDist: [String]
  )? {
    var name: String?
    var version: String?
    var summary: String?
    var author: String?
    var requiresDist: [String] = []

    let lines = content.components(separatedBy: .newlines)
    for line in lines {
      if line.hasPrefix("Name: ") {
        name = String(line.dropFirst("Name: ".count)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("Version: ") {
        version = String(line.dropFirst("Version: ".count)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("Summary: ") {
        summary = String(line.dropFirst("Summary: ".count)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("Author: ") {
        author = String(line.dropFirst("Author: ".count)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("Requires-Dist: ") {
        let dep = String(line.dropFirst("Requires-Dist: ".count)).trimmingCharacters(
          in: .whitespaces)
        // Extract just the package name (before any version specifier)
        let depName =
          dep.components(separatedBy: CharacterSet(charactersIn: " <>=!;[")).first ?? dep
        requiresDist.append(depName)
      }
    }

    guard let n = name, let v = version else { return nil }
    return (n, v, summary, author, requiresDist)
  }

  private func calculatePackageSize(name: String, in sitePackages: String) -> Int64? {
    let fm = FileManager.default
    var totalSize: Int64 = 0

    // Check for package directory
    let packagePath = (sitePackages as NSString).appendingPathComponent(name)
    if fm.fileExists(atPath: packagePath) {
      if let enumerator = fm.enumerator(atPath: packagePath) {
        while let file = enumerator.nextObject() as? String {
          let fullPath = (packagePath as NSString).appendingPathComponent(file)
          if let attrs = try? fm.attributesOfItem(atPath: fullPath),
            let fileSize = attrs[.size] as? Int64
          {
            totalSize += fileSize
          }
        }
      }
    }

    // Also check for .dist-info directory
    let distInfoPath = (sitePackages as NSString).appendingPathComponent("\(name).dist-info")
    if let enumerator = fm.enumerator(atPath: distInfoPath) {
      while let file = enumerator.nextObject() as? String {
        let fullPath = (distInfoPath as NSString).appendingPathComponent(file)
        if let attrs = try? fm.attributesOfItem(atPath: fullPath),
          let fileSize = attrs[.size] as? Int64
        {
          totalSize += fileSize
        }
      }
    }

    return totalSize > 0 ? totalSize : nil
  }
}

// MARK: - Pip Package Metadata

/// Python 特定的元数据
public struct PipPackageMetadata: Codable, Sendable {
  public let installPath: String?
  public let size: Int64?
  public let summary: String?
  public let author: String?
  public let requiresDist: [String]
}
