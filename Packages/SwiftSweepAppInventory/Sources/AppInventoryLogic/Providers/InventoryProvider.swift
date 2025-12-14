import Foundation
import CoreServices

/// Protocol for providing a list of installed applications.
public protocol InventoryProviding {
    func fetchApps() async -> [AppItem]
}

/// Provides app listings using Spotlight (NSMetadataQuery) with FileManager fallback.
public final class InventoryProvider: InventoryProviding {
    
    private let applicationsPath = "/Applications"
    
    public init() {}
    
    public func fetchApps() async -> [AppItem] {
        // Try Spotlight first
        let spotlightApps = await querySpotlight()
        if !spotlightApps.isEmpty {
            return deduplicateApps(spotlightApps)
        }
        
        // Fallback to FileManager
        let fileSystemApps = scanFileSystem()
        return deduplicateApps(fileSystemApps)
    }
    
    // MARK: - Spotlight Query
    
    private func querySpotlight() async -> [AppItem] {
        await withCheckedContinuation { continuation in
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
            query.searchScopes = [URL(fileURLWithPath: applicationsPath)]
            query.valueListAttributes = [
                NSMetadataItemPathKey as String,
                NSMetadataItemDisplayNameKey as String,
                NSMetadataItemFSContentChangeDateKey as String,
                "kMDItemCFBundleIdentifier",
                "kMDItemVersion",
                "kMDItemLastUsedDate"
            ]
            
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak query] _ in
                query?.stop()
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                
                guard let results = query?.results as? [NSMetadataItem] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let apps = results.compactMap { item -> AppItem? in
                    guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                          path.hasSuffix(".app") else {
                        return nil
                    }
                    
                    let url = URL(fileURLWithPath: path)
                    let displayName = (item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    let bundleID = item.value(forAttribute: "kMDItemCFBundleIdentifier") as? String
                    let version = item.value(forAttribute: "kMDItemVersion") as? String
                    let lastUsed = item.value(forAttribute: "kMDItemLastUsedDate") as? Date
                    let contentModified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
                    
                    let id = bundleID ?? url.path
                    
                    return AppItem(
                        id: id,
                        url: url,
                        displayName: displayName,
                        version: version,
                        estimatedSizeBytes: nil, // Spotlight doesn't provide reliable size
                        lastUsedDate: lastUsed,
                        contentModifiedDate: contentModified,
                        source: .spotlight
                    )
                }
                continuation.resume(returning: apps)
            }
            
            query.start()
        }
    }
    
    // MARK: - FileManager Fallback
    
    private func scanFileSystem() -> [AppItem] {
        let fm = FileManager.default
        let appsURL = URL(fileURLWithPath: applicationsPath)
        
        guard let contents = try? fm.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .localizedNameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        return contents.compactMap { url -> AppItem? in
            guard url.pathExtension == "app" else { return nil }
            
            let displayName = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? url.deletingPathExtension().lastPathComponent
            let contentModified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            
            let id = bundleID ?? url.path
            
            return AppItem(
                id: id,
                url: url,
                displayName: displayName,
                version: version,
                estimatedSizeBytes: nil,
                lastUsedDate: nil,
                contentModifiedDate: contentModified,
                source: .filesystem
            )
        }
    }
    
    // MARK: - Deduplication
    
    /// Deduplicates apps by ID, preferring /Applications, then shortest path, then latest mtime.
    private func deduplicateApps(_ apps: [AppItem]) -> [AppItem] {
        var seen: [String: AppItem] = [:]
        
        for app in apps {
            if let existing = seen[app.id] {
                // Prefer /Applications path
                let appIsInApplications = app.url.path.hasPrefix(applicationsPath + "/")
                let existingIsInApplications = existing.url.path.hasPrefix(applicationsPath + "/")
                
                if appIsInApplications && !existingIsInApplications {
                    seen[app.id] = app
                } else if !appIsInApplications && existingIsInApplications {
                    // Keep existing
                } else {
                    // Both in same location preference, use shorter path
                    if app.url.path.count < existing.url.path.count {
                        seen[app.id] = app
                    } else if app.url.path.count == existing.url.path.count {
                        // Use latest mtime
                        if (app.contentModifiedDate ?? .distantPast) > (existing.contentModifiedDate ?? .distantPast) {
                            seen[app.id] = app
                        }
                    }
                }
            } else {
                seen[app.id] = app
            }
        }
        
        return Array(seen.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
