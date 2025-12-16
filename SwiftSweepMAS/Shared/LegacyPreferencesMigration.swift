import Foundation

/// One-time migration from legacy App Group `UserDefaults` storage into per-app preferences + file-backed sync store.
///
/// - Copies `appInventory.*` keys into `UserDefaults.standard` (so the Host App no longer depends on App Group defaults).
/// - Copies onboarding/UX flags into `UserDefaults.standard`.
/// - Bootstraps `DirectorySyncStore` (bookmarks/version) from the legacy App Group preferences file if needed.
public enum LegacyPreferencesMigration {
    private static let migrationFlagKey = "didMigrateFromAppGroupDefaults.v1"
    
    public static func performIfNeeded() {
        guard isHostApp else { return }
        
        let standard = UserDefaults.standard
        guard !standard.bool(forKey: migrationFlagKey) else { return }
        defer { standard.set(true, forKey: migrationFlagKey) }
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DirectorySyncConstants.suiteName) else {
            _ = DirectorySyncStore.load()
            return
        }
        
        let legacyPrefsURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(DirectorySyncConstants.suiteName).plist", isDirectory: false)
        
        guard let data = try? Data(contentsOf: legacyPrefsURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            _ = DirectorySyncStore.load()
            return
        }
        
        copyIfAbsent(key: "hasCompletedOnboarding", from: dict, to: standard)
        copyIfAbsent(key: "hasConfirmedExtensionEnabled", from: dict, to: standard)
        
        for (key, value) in dict where key.hasPrefix("appInventory.") {
            guard standard.object(forKey: key) == nil else { continue }
            standard.set(value, forKey: key)
        }
        
        // Ensure bookmarks/version are migrated into the file-backed store.
        _ = DirectorySyncStore.load()
    }
    
    private static func copyIfAbsent(key: String, from dict: [String: Any], to standard: UserDefaults) {
        guard standard.object(forKey: key) == nil, let value = dict[key] else { return }
        standard.set(value, forKey: key)
    }
    
    private static var isHostApp: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        return !bundleID.hasSuffix(".findersync")
    }
}

