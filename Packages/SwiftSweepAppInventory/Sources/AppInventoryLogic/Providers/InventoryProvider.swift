@preconcurrency import Foundation
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
        print("[InventoryProvider] fetchApps() START")
        // Try Spotlight first
        let spotlightApps = await querySpotlight()
        print("[InventoryProvider] Spotlight returned \(spotlightApps.count) apps")
        if !spotlightApps.isEmpty {
            return deduplicateApps(spotlightApps)
        }
        
        // Fallback to FileManager
        print("[InventoryProvider] Falling back to FileManager")
        let fileSystemApps = scanFileSystem()
        print("[InventoryProvider] FileManager returned \(fileSystemApps.count) apps")
        return deduplicateApps(fileSystemApps)
    }
    
    // MARK: - Spotlight Query
    
    private func querySpotlight() async -> [AppItem] {
        return await withCheckedContinuation { continuation in
            let path = applicationsPath
            Task { @MainActor in
                let wrapper = SpotlightQueryWrapper(applicationsPath: path, continuation: continuation)
                wrapper.start()
            }
        }
    }
    
    // MARK: - Spotlight Helper
    
    @MainActor
    private class SpotlightQueryWrapper {
        private let query = NSMetadataQuery()
        private let applicationsPath: String
        private let continuation: CheckedContinuation<[AppItem], Never>
        private var observer: NSObjectProtocol?
        private var timeoutWorkItem: DispatchWorkItem?
        private var hasFinished = false
        
        init(applicationsPath: String, continuation: CheckedContinuation<[AppItem], Never>) {
            self.applicationsPath = applicationsPath
            self.continuation = continuation
        }
        
        func start() {
            // Setup query
            query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
            query.searchScopes = [URL(fileURLWithPath: applicationsPath)]
            query.valueListAttributes = [
                NSMetadataItemPathKey as String,
                NSMetadataItemDisplayNameKey as String,
                NSMetadataItemFSContentChangeDateKey as String,
                NSMetadataItemFSSizeKey as String,
                "kMDItemCFBundleIdentifier",
                "kMDItemVersion",
                "kMDItemLastUsedDate"
            ]
            
            // Setup timeout
            let workItem = DispatchWorkItem { [self] in
                Task { @MainActor in
                    self.finish(with: [])
                }
            }
            self.timeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            
            // Setup observer
            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [self] _ in
                Task { @MainActor in
                    self.processResults()
                }
            }
            
            if !query.start() {
                finish(with: [])
            }
        }
        
        private func processResults() {
            guard let results = query.results as? [NSMetadataItem] else {
                finish(with: [])
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
                let estimatedSize = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value
                
                let id = bundleID ?? url.path
                
                return AppItem(
                    id: id,
                    url: url,
                    displayName: displayName,
                    version: version,
                    estimatedSizeBytes: estimatedSize,
                    lastUsedDate: lastUsed,
                    contentModifiedDate: contentModified,
                    source: .spotlight
                )
            }
            
            finish(with: apps)
        }
        
        private func finish(with apps: [AppItem]) {
            guard !hasFinished else { return }
            hasFinished = true
            
            timeoutWorkItem?.cancel()
            timeoutWorkItem = nil
            query.stop()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            
            continuation.resume(returning: apps)
        }
        
        deinit {
            timeoutWorkItem?.cancel()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            query.stop()
            if !hasFinished {
                continuation.resume(returning: [])
            }
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
