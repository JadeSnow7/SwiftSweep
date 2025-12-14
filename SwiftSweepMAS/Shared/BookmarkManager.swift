import Foundation

/// Manages security-scoped bookmarks for authorized directories
public final class BookmarkManager: ObservableObject {
    public static let shared = BookmarkManager()
    
    private let defaults: UserDefaults
    
    @Published public private(set) var authorizedDirectories: [ResolvedDirectory] = []
    
    public struct ResolvedDirectory: Identifiable {
        public let id = UUID()
        public let url: URL
        public let path: String
        public let isStale: Bool
        
        public var name: String {
            url.lastPathComponent
        }
    }
    
    private init() {
        defaults = UserDefaults(suiteName: DirectorySyncConstants.suiteName) ?? .standard
        reloadDirectories()
    }
    
    // MARK: - Public API
    
    /// Add a directory to authorized list
    public func addAuthorizedDirectory(_ url: URL) throws {
        guard authorizedDirectories.count < DirectorySyncConstants.maxDirectories else {
            throw BookmarkError.limitReached
        }
        
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        var bookmarks = getBookmarksDict()
        bookmarks[url.path] = bookmark
        defaults.set(bookmarks, forKey: DirectorySyncConstants.bookmarksKey)
        
        incrementVersionAndNotify()
        reloadDirectories()
    }
    
    /// Remove a directory from authorized list
    public func removeAuthorizedDirectory(_ url: URL) {
        var bookmarks = getBookmarksDict()
        bookmarks.removeValue(forKey: url.path)
        defaults.set(bookmarks, forKey: DirectorySyncConstants.bookmarksKey)
        
        incrementVersionAndNotify()
        reloadDirectories()
    }
    
    /// Get bookmark data for a path (for Extension use)
    public func getBookmark(for url: URL) -> Data? {
        let bookmarks = getBookmarksDict()
        
        // Try exact match first
        if let data = bookmarks[url.path] {
            return data
        }
        
        // Try to find a parent directory bookmark
        for (path, data) in bookmarks {
            if url.path.hasPrefix(path) {
                return data
            }
        }
        
        return nil
    }
    
    /// Resolve authorized directories (for Finder Sync registration)
    /// NOTE: Does NOT call startAccessingSecurityScopedResource
    public func resolveAuthorizedDirectories() -> [URL] {
        let bookmarks = getBookmarksDict()
        
        return bookmarks.compactMap { _, data in
            var isStale = false
            return try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        }
    }
    
    /// Reload directories list (for UI)
    public func reloadDirectories() {
        let bookmarks = getBookmarksDict()
        
        authorizedDirectories = bookmarks.compactMap { path, data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            
            return ResolvedDirectory(url: url, path: path, isStale: isStale)
        }
    }
    
    // MARK: - Private
    
    private func getBookmarksDict() -> [String: Data] {
        defaults.dictionary(forKey: DirectorySyncConstants.bookmarksKey) as? [String: Data] ?? [:]
    }
    
    private func incrementVersionAndNotify() {
        // Increment version
        let version = defaults.integer(forKey: DirectorySyncConstants.versionKey)
        defaults.set(version + 1, forKey: DirectorySyncConstants.versionKey)
        
        // Post distributed notification for immediate sync
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(DirectorySyncConstants.syncNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

// MARK: - Errors

public enum BookmarkError: Error, LocalizedError {
    case limitReached
    case accessDenied
    case staleBookmark
    
    public var errorDescription: String? {
        switch self {
        case .limitReached:
            return "Maximum number of directories (\(DirectorySyncConstants.maxDirectories)) reached"
        case .accessDenied:
            return "Access denied to this directory"
        case .staleBookmark:
            return "This directory needs to be re-authorized"
        }
    }
}
