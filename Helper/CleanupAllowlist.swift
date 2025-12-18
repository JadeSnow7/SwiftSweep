import Foundation

/// Shared allowlist for cleanup operations
/// Used by both CleanupEngine (pre-check) and Helper (enforcement)
public enum CleanupAllowlist {
    /// Cleanup operation roots (existing, restrictive)
    public static let cleanupRoots = ["/Library/Logs", "/Library/Caches"]
    
    /// Uninstall operation roots (more permissive, includes /Applications)
    public static let uninstallRoots: [String] = {
        let home = NSHomeDirectory()
        return [
            "/Applications",
            "\(home)/Applications",
            "\(home)/Library/Caches",
            "\(home)/Library/Preferences",
            "\(home)/Library/Application Support",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Containers",
            "\(home)/Library/Logs",
            "\(home)/Library/Saved Application State",
        ]
    }()
    
    /// Normalize path: strip trailing slashes, standardize
    public static func normalize(_ path: String) -> String? {
        guard !path.isEmpty, path.hasPrefix("/"), path != "/" else { return nil }
        var p = path
        while p.hasSuffix("/") && p.count > 1 { p = String(p.dropLast()) }
        return URL(fileURLWithPath: p).standardized.path
    }
    
    /// Target path: must be UNDER root (not equal to root)
    /// - Parameter forUninstall: If true, uses uninstallRoots instead of cleanupRoots
    public static func isTargetAllowed(_ path: String, forUninstall: Bool = false) -> Bool {
        let roots = forUninstall ? uninstallRoots : cleanupRoots
        guard let norm = normalize(path) else { return false }
        return roots.contains { norm.hasPrefix($0 + "/") }
    }
    
    /// Parent path: can equal root OR be under root
    /// - Parameter forUninstall: If true, uses uninstallRoots instead of cleanupRoots
    public static func isParentAllowed(_ path: String, forUninstall: Bool = false) -> Bool {
        let roots = forUninstall ? uninstallRoots : cleanupRoots
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
