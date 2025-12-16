import Foundation

/// Shared constants for directory sync between Host App and Finder Extension
public enum DirectorySyncConstants {
    /// App Group suite name for shared UserDefaults
    public static let suiteName = "group.com.swiftsweep.mas"
    
    /// Key for storing authorized directory bookmarks
    public static let bookmarksKey = "authorizedDirectoryBookmarks"
    
    /// Key for version tracking (incremented on each change)
    public static let versionKey = "authorizedDirectoriesVersion"
    
    /// Distributed notification name for immediate sync
    public static let syncNotificationName = "com.swiftsweep.mas.directoriesChanged"
    
    /// Maximum number of authorized directories (for Finder performance)
    public static let maxDirectories = 20
    
    /// Recommended number of directories
    public static let recommendedDirectories = 8
    
    /// Shared UserDefaults for the App Group (falls back to `.standard` if the container is unavailable).
    public static let userDefaults: UserDefaults = {
        // Touch container first; if the App Group entitlement is missing, avoid using the suite to
        // prevent noisy CFPrefs warnings and fall back to `.standard`.
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) != nil,
              let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return defaults
    }()
}
