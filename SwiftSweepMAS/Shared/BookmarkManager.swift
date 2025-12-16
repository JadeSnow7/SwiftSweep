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
        defaults = DirectorySyncConstants.userDefaults
        migrateLegacyBookmarks()
        reloadDirectories()
    }
    
    // MARK: - Public API
    
    /// Add a directory to authorized list
    public func addAuthorizedDirectory(_ url: URL) throws {
        guard authorizedDirectories.count < DirectorySyncConstants.maxDirectories else {
            throw BookmarkError.limitReached
        }
        
        guard url.isFileURL else {
            throw BookmarkError.accessDenied
        }
        
        let normalizedPath = normalizedPath(for: url)
        var bookmarks = getBookmarksDict()
        if bookmarks[normalizedPath] != nil {
            return
        }
        
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.accessDenied
        }
        
        bookmarks[normalizedPath] = bookmark
        defaults.set(bookmarks, forKey: DirectorySyncConstants.bookmarksKey)
        
        incrementVersionAndNotify()
        reloadDirectories()
    }
    
    /// Remove a directory from authorized list
    public func removeAuthorizedDirectory(_ url: URL) {
        removeAuthorizedDirectory(path: normalizedPath(for: url))
    }
    
    public func removeAuthorizedDirectory(path: String) {
        var bookmarks = getBookmarksDict()
        bookmarks.removeValue(forKey: path)
        defaults.set(bookmarks, forKey: DirectorySyncConstants.bookmarksKey)
        
        incrementVersionAndNotify()
        reloadDirectories()
    }
    
    /// Get bookmark data for a path (for Extension use)
    public func getBookmark(for url: URL) -> Data? {
        let bookmarks = getBookmarksDict()
        let targetPath = normalizedPath(for: url)
        
        // Try exact match first
        if let data = bookmarks[targetPath] {
            return data
        }
        
        // Try to find the closest parent directory bookmark (longest match)
        var bestMatch: (path: String, data: Data)?
        for (path, data) in bookmarks {
            if targetPath == path || targetPath.hasPrefix(path + "/") {
                if bestMatch == nil || path.count > bestMatch!.path.count {
                    bestMatch = (path, data)
                }
            }
        }
        return bestMatch?.data
    }
    
    /// Resolve authorized directories (for Finder Sync registration)
    /// NOTE: Does NOT call startAccessingSecurityScopedResource
    public func resolveAuthorizedDirectories() -> [URL] {
        let bookmarks = getBookmarksDict()
        
        return bookmarks.compactMap { path, data in
            resolveBookmark(path: path, data: data)?.url
        }
    }
    
    /// Reload directories list (for UI)
    public func reloadDirectories() {
        let bookmarks = getBookmarksDict()
        
        authorizedDirectories = bookmarks.compactMap { path, data in
            resolveBookmark(path: path, data: data)
        }
    }
    
    // MARK: - Private
    
    private func getBookmarksDict() -> [String: Data] {
        defaults.dictionary(forKey: DirectorySyncConstants.bookmarksKey) as? [String: Data] ?? [:]
    }
    
    private func normalizedPath(for url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
    
    /// Upgrade any legacy (non-security-scoped) bookmarks created before entitlements were enabled
    private func migrateLegacyBookmarks() {
        let bookmarks = getBookmarksDict()
        var upgraded: [String: Data] = [:]
        var didUpgrade = false
        
        for (path, data) in bookmarks {
            // If it already resolves with security scope, keep it as-is
            var securityStale = false
            if (try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &securityStale
            )) != nil {
                continue
            }
            
            // Try to resolve legacy bookmark and regenerate with security scope
            var legacyStale = false
            if let legacyURL = try? URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &legacyStale
            ),
               let scoped = try? legacyURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
               ) {
                upgraded[path] = scoped
                didUpgrade = true
            }
        }
        
        guard didUpgrade else { return }
        
        var merged = bookmarks
        upgraded.forEach { merged[$0.key] = $0.value }
        defaults.set(merged, forKey: DirectorySyncConstants.bookmarksKey)
        incrementVersionAndNotify()
    }
    
    /// Resolve bookmark data with a fallback for legacy non-security-scoped entries
    private func resolveBookmark(path: String, data: Data) -> ResolvedDirectory? {
        var isStale = false
        
        // Preferred: security-scoped bookmark
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return ResolvedDirectory(url: url, path: path, isStale: isStale)
        }
        
        // Fallback: legacy bookmark without security scope
        var legacyStale = false
        guard let legacyURL = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &legacyStale
        ) else {
            return nil
        }
        
        // Mark as stale so UI can prompt re-authorization
        return ResolvedDirectory(url: legacyURL, path: path, isStale: true)
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
