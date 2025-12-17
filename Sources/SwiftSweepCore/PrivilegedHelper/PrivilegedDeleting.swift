import Foundation

/// Status of the Privileged Helper
public enum PrivilegedHelperStatus: Sendable {
    case available
    case notInstalled
    case versionMismatch
    case unknown
}

/// Protocol for privileged deletion capabilities
public protocol PrivilegedDeleting: Sendable {
    /// Delete item at URL using privileged helper.
    /// - Parameter url: The file URL to delete.
    /// - Throws: Error if deletion fails or helper is unavailable.
    func deleteItem(at url: URL) async throws
    
    /// Get the current status of the helper availability.
    func status() async -> PrivilegedHelperStatus
}
