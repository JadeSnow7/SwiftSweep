import Foundation

/// Shared allowlist for cleanup operations
/// Used by both CleanupEngine (pre-check) and Helper (enforcement)
public enum CleanupAllowlist {
    public static let roots = ["/Library/Logs", "/Library/Caches"]
    
    /// Normalize path: strip trailing slashes, standardize
    public static func normalize(_ path: String) -> String? {
        guard !path.isEmpty, path.hasPrefix("/"), path != "/" else { return nil }
        var p = path
        while p.hasSuffix("/") && p.count > 1 { p = String(p.dropLast()) }
        return URL(fileURLWithPath: p).standardized.path
    }
    
    /// Target path: must be UNDER root (not equal to root)
    public static func isTargetAllowed(_ path: String) -> Bool {
        guard let norm = normalize(path) else { return false }
        return roots.contains { norm.hasPrefix($0 + "/") }
    }
    
    /// Parent path: can equal root OR be under root
    public static func isParentAllowed(_ path: String) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
