import Foundation

/// Shared constants for directory sync between Host App and Finder Extension
public enum DirectorySyncConstants {
    /// App Group suite name for shared UserDefaults
    public static let suiteName = "group.com.swiftsweep.mas"

    /// File name used for bookmark sync storage inside the App Group container
    public static let storeFileName = "authorized-directories-store.plist"
    
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
}
