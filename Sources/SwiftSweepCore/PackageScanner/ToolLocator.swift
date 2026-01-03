import Foundation

/// Locates external tools and provides environment configuration
public struct ToolLocator: Sendable {

  /// Common paths to search for executables
  /// Ordered by priority: Homebrew → Language-specific → System → User
  public static let searchPaths: [String] = {
    let home = NSHomeDirectory()
    return [
      // Homebrew (highest priority)
      "/opt/homebrew/bin",  // Apple Silicon
      "/usr/local/bin",  // Intel / npm / pyenv

      // System binaries
      "/usr/bin",
      "/bin",

      // Language-specific package managers
      "\(home)/.cargo/bin",  // Rust (Cargo)
      "\(home)/go/bin",  // Go
      "\(home)/.composer/vendor/bin",  // PHP (Composer)

      // Alternative package managers
      "/opt/local/bin",  // MacPorts
      "/usr/pkg/bin",  // pkgsrc

      // Python user installations
      "\(home)/.local/bin",  // pip --user
      "\(home)/Library/Python/3.9/bin",
      "\(home)/Library/Python/3.10/bin",
      "\(home)/Library/Python/3.11/bin",
      "\(home)/Library/Python/3.12/bin",
    ]
  }()

  /// Find an executable by name in common paths
  /// - Parameter name: Name of the executable (e.g., "brew", "npm")
  /// - Returns: URL to the executable, or nil if not found
  public static func find(_ name: String) -> URL? {
    let fm = FileManager.default
    for path in searchPaths {
      let fullPath = "\(path)/\(name)"
      if fm.isExecutableFile(atPath: fullPath) {
        return URL(fileURLWithPath: fullPath)
      }
    }
    return nil
  }

  /// Environment variables for Package Finder commands
  /// Includes PATH, HOME, and settings to prevent unwanted updates
  public static var packageFinderEnvironment: [String: String] {
    // Include sbin paths for Homebrew
    let pathWithSbin =
      searchPaths.joined(separator: ":") + ":/opt/homebrew/sbin:/usr/local/sbin:/usr/sbin:/sbin"

    var env: [String: String] = [
      "PATH": pathWithSbin,
      "LANG": "en_US.UTF-8",
      "LC_ALL": "en_US.UTF-8",
      // Prevent Homebrew from auto-updating during scan
      "HOMEBREW_NO_AUTO_UPDATE": "1",
      "HOMEBREW_NO_INSTALL_CLEANUP": "1",
      // Homebrew prefix environment (required for brew to function properly)
      "HOMEBREW_PREFIX": "/opt/homebrew",
      "HOMEBREW_CELLAR": "/opt/homebrew/Cellar",
      "HOMEBREW_REPOSITORY": "/opt/homebrew",
      // Prevent npm from checking for updates
      "NO_UPDATE_NOTIFIER": "1",
    ]

    // Add HOME from current environment (required for brew/npm to function)
    if let home = ProcessInfo.processInfo.environment["HOME"] {
      env["HOME"] = home
    }

    // Add USER if available
    if let user = ProcessInfo.processInfo.environment["USER"] {
      env["USER"] = user
    }

    // Add SHELL if available (some tools check this)
    if let shell = ProcessInfo.processInfo.environment["SHELL"] {
      env["SHELL"] = shell
    }

    return env
  }
}
