import Foundation

/// File-backed sync store shared between Host App and Finder Extension (App Group container).
public enum DirectorySyncStore {
    public struct Snapshot: Codable, Sendable {
        public var version: Int
        public var bookmarks: [String: Data]
        
        public init(version: Int = 0, bookmarks: [String: Data] = [:]) {
            self.version = version
            self.bookmarks = bookmarks
        }
    }
    
    private static let lock = NSLock()
    
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    
    private static let decoder = PropertyListDecoder()
    
    private static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DirectorySyncConstants.suiteName)
    }
    
    private static func storeURL(containerURL: URL) -> URL {
        containerURL.appendingPathComponent(DirectorySyncConstants.storeFileName, isDirectory: false)
    }
    
    public static func load() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        
        guard let containerURL = appGroupContainerURL() else {
            return Snapshot()
        }
        
        let url = storeURL(containerURL: containerURL)
        if let data = try? Data(contentsOf: url),
           let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            return snapshot
        }
        
        // One-time bootstrap: migrate legacy App Group preferences into a file store.
        let snapshot = migrateFromLegacyPreferences(containerURL: containerURL)
        
        // Always create the store file to avoid repeated legacy checks.
        saveUnlocked(snapshot, to: url)
        return snapshot
    }
    
    @discardableResult
    public static func update(_ mutate: (inout Snapshot) -> Void) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        
        guard let containerURL = appGroupContainerURL() else {
            var snapshot = Snapshot()
            mutate(&snapshot)
            return snapshot
        }
        
        let url = storeURL(containerURL: containerURL)
        var snapshot: Snapshot
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(Snapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = migrateFromLegacyPreferences(containerURL: containerURL)
        }
        
        mutate(&snapshot)
        saveUnlocked(snapshot, to: url)
        return snapshot
    }
    
    // MARK: - Private
    
    private static func saveUnlocked(_ snapshot: Snapshot, to url: URL) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort: never crash host app / extension due to persistence.
        }
    }
    
    private static func migrateFromLegacyPreferences(containerURL: URL) -> Snapshot {
        let legacyPrefsURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(DirectorySyncConstants.suiteName).plist", isDirectory: false)
        
        guard let data = try? Data(contentsOf: legacyPrefsURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            return Snapshot()
        }
        
        let bookmarks: [String: Data]
        if let raw = dict[DirectorySyncConstants.bookmarksKey] as? [String: Data] {
            bookmarks = raw
        } else if let raw = dict[DirectorySyncConstants.bookmarksKey] as? [String: Any] {
            bookmarks = raw.compactMapValues { $0 as? Data }
        } else {
            bookmarks = [:]
        }
        
        let version: Int
        if let num = dict[DirectorySyncConstants.versionKey] as? NSNumber {
            version = num.intValue
        } else {
            version = bookmarks.isEmpty ? 0 : 1
        }
        
        return Snapshot(version: version, bookmarks: bookmarks)
    }
}

