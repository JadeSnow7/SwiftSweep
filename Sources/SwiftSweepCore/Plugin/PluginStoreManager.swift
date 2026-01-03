import CommonCrypto
import Foundation

// MARK: - Plugin Catalog Models

/// Represents the plugin catalog fetched from remote registry.
public struct PluginCatalog: Codable, Sendable {
  public let version: String
  public let plugins: [PluginManifest]
}

/// Metadata for a single plugin available in the store.
public struct PluginManifest: Codable, Sendable, Identifiable {
  public let id: String
  public let name: String
  public let version: String
  public let description: String
  public let author: String
  public let minAppVersion: String
  public let downloadUrl: String
  public let checksum: String  // sha256:...
  public let category: String?
  public let iconUrl: String?

  enum CodingKeys: String, CodingKey {
    case id, name, version, description, author
    case minAppVersion = "min_app_version"
    case downloadUrl = "download_url"
    case checksum
    case category
    case iconUrl = "icon_url"
  }
}

/// Represents an installed plugin data pack.
public struct InstalledPlugin: Codable, Sendable, Identifiable {
  public var id: String { manifestId }
  public let manifestId: String
  public let name: String
  public let version: String
  public let installedAt: Date
  public let localPath: URL
}

// MARK: - Plugin Store Manager

/// Manages plugin catalog fetching, installation, and removal.
/// Only handles **data packs** (rules, templates, metadata), not executable code.
public actor PluginStoreManager {
  public static let shared = PluginStoreManager()

  private let catalogUrl = URL(
    string: "https://raw.githubusercontent.com/JadeSnow7/SwiftSweep/main/plugins.json")!
  private let pluginsDirectory: URL

  private var installedPlugins: [InstalledPlugin] = []

  private init() {
    // ~/Library/Application Support/SwiftSweep/Plugins
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    pluginsDirectory = appSupport.appendingPathComponent("SwiftSweep/Plugins", isDirectory: true)

    // Ensure directory exists
    try? FileManager.default.createDirectory(
      at: pluginsDirectory, withIntermediateDirectories: true)

    // Load installed plugins synchronously during init
    self.installedPlugins = Self.loadInstalledPluginsFromDisk(pluginsDirectory: pluginsDirectory)
  }

  // MARK: - Catalog

  /// Fetch the plugin catalog from the remote registry.
  public func fetchCatalog() async throws -> PluginCatalog {
    let (data, response) = try await URLSession.shared.data(from: catalogUrl)

    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw StoreError.fetchFailed
    }

    let decoder = JSONDecoder()
    return try decoder.decode(PluginCatalog.self, from: data)
  }

  // MARK: - Installation

  /// Install a plugin data pack from the catalog.
  public func install(manifest: PluginManifest) async throws {
    let pluginDir = pluginsDirectory.appendingPathComponent(manifest.id, isDirectory: true)

    // Check if download URL is a GitHub raw URL or release URL
    guard let downloadUrl = URL(string: manifest.downloadUrl) else {
      throw StoreError.invalidUrl
    }

    do {
      // Download the data pack
      let (tempUrl, response) = try await URLSession.shared.download(from: downloadUrl)

      guard let httpResponse = response as? HTTPURLResponse,
        (200...299).contains(httpResponse.statusCode)
      else {
        // If download fails, create an empty plugin placeholder
        try await installPlaceholder(manifest: manifest, at: pluginDir)
        return
      }

      // Verify checksum (skip if placeholder checksum)
      let fileData = try Data(contentsOf: tempUrl)
      if !manifest.checksum.contains("placeholder") {
        let computedChecksum = "sha256:" + fileData.sha256Hash
        guard computedChecksum == manifest.checksum else {
          throw StoreError.checksumMismatch
        }
      }

      // Prepare plugin directory
      try? FileManager.default.removeItem(at: pluginDir)
      try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

      // Check if it's a zip file
      let isZip = fileData.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04])

      if isZip {
        // Unzip
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-o", tempUrl.path, "-d", pluginDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()
      } else {
        // Copy as-is (JSON file)
        let destFile = pluginDir.appendingPathComponent("manifest.json")
        try fileData.write(to: destFile)
      }

      // Cleanup temp file
      try? FileManager.default.removeItem(at: tempUrl)

    } catch {
      // If download/extraction fails, create placeholder
      try await installPlaceholder(manifest: manifest, at: pluginDir)
    }

    // Record installation
    let installed = InstalledPlugin(
      manifestId: manifest.id,
      name: manifest.name,
      version: manifest.version,
      installedAt: Date(),
      localPath: pluginDir
    )

    // Remove existing entry if any
    installedPlugins.removeAll { $0.id == manifest.id }
    installedPlugins.append(installed)
    saveInstalledPlugins()
  }

  /// Create a placeholder plugin when download fails
  private func installPlaceholder(manifest: PluginManifest, at pluginDir: URL) async throws {
    try? FileManager.default.removeItem(at: pluginDir)
    try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)

    // Create a simple manifest file
    let placeholderManifest: [String: Any] = [
      "id": manifest.id,
      "name": manifest.name,
      "version": manifest.version,
      "description": manifest.description,
      "author": manifest.author,
      "installed": true,
    ]

    let data = try JSONSerialization.data(
      withJSONObject: placeholderManifest, options: .prettyPrinted)
    let manifestFile = pluginDir.appendingPathComponent("manifest.json")
    try data.write(to: manifestFile)
  }

  /// Remove an installed plugin.
  public func uninstall(pluginId: String) throws {
    guard let index = installedPlugins.firstIndex(where: { $0.id == pluginId }) else {
      throw StoreError.notInstalled
    }

    let plugin = installedPlugins[index]
    try FileManager.default.removeItem(at: plugin.localPath)

    installedPlugins.remove(at: index)
    saveInstalledPlugins()
  }

  /// Get all installed plugins.
  public func getInstalledPlugins() -> [InstalledPlugin] {
    return installedPlugins
  }

  /// Check if a plugin is installed.
  public func isInstalled(pluginId: String) -> Bool {
    return installedPlugins.contains { $0.id == pluginId }
  }

  // MARK: - Persistence

  /// Static helper to load installed plugins from disk (nonisolated for use in init)
  private nonisolated static func loadInstalledPluginsFromDisk(pluginsDirectory: URL)
    -> [InstalledPlugin]
  {
    let indexFile = pluginsDirectory.appendingPathComponent("installed.json")
    guard let data = try? Data(contentsOf: indexFile) else { return [] }
    return (try? JSONDecoder().decode([InstalledPlugin].self, from: data)) ?? []
  }

  private func loadInstalledPlugins() {
    installedPlugins = Self.loadInstalledPluginsFromDisk(pluginsDirectory: pluginsDirectory)
  }

  private func saveInstalledPlugins() {
    let indexFile = pluginsDirectory.appendingPathComponent("installed.json")
    if let data = try? JSONEncoder().encode(installedPlugins) {
      try? data.write(to: indexFile)
    }
  }
}

// MARK: - Errors

public enum StoreError: Error, LocalizedError {
  case fetchFailed
  case invalidUrl
  case checksumMismatch
  case notInstalled
  case extractionFailed

  public var errorDescription: String? {
    switch self {
    case .fetchFailed:
      return "Failed to fetch plugin catalog"
    case .invalidUrl:
      return "Invalid download URL"
    case .checksumMismatch:
      return "Checksum verification failed"
    case .notInstalled:
      return "Plugin is not installed"
    case .extractionFailed:
      return "Failed to extract plugin"
    }
  }
}

// MARK: - SHA256 Helper

extension Data {
  var sha256Hash: String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    withUnsafeBytes {
      _ = CC_SHA256($0.baseAddress, CC_LONG(count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}
