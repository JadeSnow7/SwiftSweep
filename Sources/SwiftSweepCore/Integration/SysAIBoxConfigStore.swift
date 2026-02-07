import Foundation

/// Stores Sys AI Box configuration (baseURL) in UserDefaults.
/// Tokens are NOT stored here; see TokenManager for Keychain storage.
public final class SysAIBoxConfigStore: @unchecked Sendable {
  public static let shared = SysAIBoxConfigStore()

  private let urlKey = "sysAIBoxBaseURL"
  // UserDefaults is thread-safe, so we use @unchecked Sendable
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Returns the stored base URL, or nil if not configured.
  public func loadBaseURL() -> URL? {
    guard let urlString = defaults.string(forKey: urlKey) else { return nil }
    return URL(string: urlString)
  }

  /// Saves the base URL after validation.
  /// - Throws: `ConfigError.invalidURL` or `ConfigError.httpsRequired`
  public func save(baseURL: URL) throws {
    // Validate URL structure
    guard let host = baseURL.host, !host.isEmpty else {
      throw ConfigError.invalidURL
    }

    // Allow HTTP for: localhost, 127.0.0.1, 192.168.x.x, 10.x.x.x, 172.16-31.x.x, and any IP (dev mode)
    let isLocalhost = host == "localhost" || host == "127.0.0.1"
    let isPrivateIP =
      host.hasPrefix("192.168.") || host.hasPrefix("10.")
      || host.hasPrefix("172.16.") || host.hasPrefix("172.17.")
      || host.hasPrefix("172.18.") || host.hasPrefix("172.19.")
      || host.hasPrefix("172.2") || host.hasPrefix("172.3")

    // For development, also allow any IP address (we can tighten this in production)
    #if DEBUG
      let allowHTTP = true
    #else
      let allowHTTP = isLocalhost || isPrivateIP
    #endif

    if !allowHTTP && baseURL.scheme != "https" {
      throw ConfigError.httpsRequired
    }

    defaults.set(baseURL.absoluteString, forKey: urlKey)
  }

  /// Clears the stored base URL.
  public func clear() {
    defaults.removeObject(forKey: urlKey)
  }

  public enum ConfigError: Error, LocalizedError {
    case invalidURL
    case httpsRequired

    public var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid URL format"
      case .httpsRequired:
        return "HTTPS is required for non-local connections"
      }
    }
  }
}
