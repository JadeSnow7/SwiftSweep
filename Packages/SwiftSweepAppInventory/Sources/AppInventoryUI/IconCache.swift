import AppKit

/// Shared cache for application icons to avoid repeated loading.
public final class IconCache {
    
    public static let shared = IconCache()
    
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        // Limit cache size
        cache.countLimit = 200
    }
    
    /// Get cached icon or load and cache it.
    public func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        
        if let cached = cache.object(forKey: key) {
            return cached
        }
        
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        cache.setObject(icon, forKey: key)
        return icon
    }
    
    /// Preload icons for a list of URLs (call from background).
    public func preload(urls: [URL]) {
        for url in urls {
            _ = icon(for: url)
        }
    }
    
    /// Clear the cache.
    public func clear() {
        cache.removeAllObjects()
    }
}
