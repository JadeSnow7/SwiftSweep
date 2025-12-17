import Foundation

/// Locates external tools and provides environment configuration
public struct ToolLocator: Sendable {
    
    /// Common paths to search for executables
    public static let searchPaths = [
        "/opt/homebrew/bin",    // Apple Silicon Homebrew
        "/usr/local/bin",       // Intel Homebrew / npm / etc.
        "/usr/bin",             // System binaries
        "/bin"                  // Core binaries
    ]
    
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
        var env: [String: String] = [
            "PATH": searchPaths.joined(separator: ":"),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            // Prevent Homebrew from auto-updating during scan
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_INSTALL_CLEANUP": "1",
            // Prevent npm from checking for updates
            "NO_UPDATE_NOTIFIER": "1"
        ]
        
        // Add HOME from current environment (required for brew/npm to function)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env["HOME"] = home
        }
        
        // Add USER if available
        if let user = ProcessInfo.processInfo.environment["USER"] {
            env["USER"] = user
        }
        
        return env
    }
}
