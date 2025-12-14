import Foundation

/// Smart filtering logic for app inventory.
public enum SmartFilters {
    
    /// Filter apps by size (large apps first).
    /// Uses `accurateSizeBytes` if available, otherwise `estimatedSizeBytes`.
    /// - Parameters:
    ///   - apps: The list of apps to filter.
    ///   - thresholdBytes: Minimum size to be considered "large". Default 500MB.
    /// - Returns: Apps exceeding the threshold, sorted by size descending.
    public static func largeApps(_ apps: [AppItem], thresholdBytes: Int64 = 500_000_000) -> [AppItem] {
        apps.filter { app in
            let size = app.accurateSizeBytes ?? app.estimatedSizeBytes ?? 0
            return size >= thresholdBytes
        }
        .sorted { ($0.accurateSizeBytes ?? $0.estimatedSizeBytes ?? 0) > ($1.accurateSizeBytes ?? $1.estimatedSizeBytes ?? 0) }
    }
    
    /// Filter apps by last used date (unused apps).
    /// - Parameters:
    ///   - apps: The list of apps.
    ///   - daysSinceLastUse: Days threshold. Default 90.
    /// - Returns: Apps not used within the threshold. Apps with nil `lastUsedDate` are excluded.
    public static func unusedApps(_ apps: [AppItem], daysSinceLastUse: Int = 90) -> [AppItem] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysSinceLastUse, to: Date()) ?? Date()
        return apps.filter { app in
            guard let lastUsed = app.lastUsedDate else { return false }
            return lastUsed < cutoffDate
        }
        .sorted { ($0.lastUsedDate ?? .distantPast) < ($1.lastUsedDate ?? .distantPast) }
    }
    
    /// Filter apps by content modification date (recently updated).
    /// - Parameters:
    ///   - apps: The list of apps.
    ///   - withinDays: Days threshold. Default 30.
    /// - Returns: Apps modified within the threshold, sorted by most recent first.
    public static func recentlyUpdated(_ apps: [AppItem], withinDays: Int = 30) -> [AppItem] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -withinDays, to: Date()) ?? Date()
        return apps.filter { app in
            guard let modDate = app.contentModifiedDate else { return false }
            return modDate >= cutoffDate
        }
        .sorted { ($0.contentModifiedDate ?? .distantPast) > ($1.contentModifiedDate ?? .distantPast) }
    }
    
    /// Filter apps that have no category assigned.
    /// - Parameters:
    ///   - apps: The list of apps.
    ///   - assignments: Current app-to-category assignments.
    /// - Returns: Apps without a category.
    public static func uncategorized(_ apps: [AppItem], assignments: [String: UUID]) -> [AppItem] {
        apps.filter { assignments[$0.id] == nil }
    }
    
    /// Check if "Unused" filter is available for an app (lastUsedDate is not nil).
    public static func isUnusedFilterAvailable(for app: AppItem) -> Bool {
        app.lastUsedDate != nil
    }
}
