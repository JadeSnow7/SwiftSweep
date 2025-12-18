import Foundation

// MARK: - DeveloperCacheRule

/// Detects large developer tool caches (Xcode, CocoaPods, Homebrew, etc.)
public struct DeveloperCacheRule: RecommendationRule {
    public let id = "developer_caches"
    public let displayName = "Developer Caches"
    public let capabilities: [RuleCapability] = [.cleanupItems]
    
    /// Minimum total size to trigger recommendation (bytes)
    private let minTotalSizeBytes: Int64 = 500_000_000  // 500 MB
    
    /// Developer cache paths patterns
    private let developerPaths: [(name: String, path: String, severity: Severity)] = [
        ("Xcode Derived Data", "Library/Developer/Xcode/DerivedData", .warning),
        ("Xcode Archives", "Library/Developer/Xcode/Archives", .info),
        ("Xcode Device Support", "Library/Developer/Xcode/iOS DeviceSupport", .info),
        ("CocoaPods Cache", "Library/Caches/CocoaPods", .warning),
        ("Carthage", "Library/Caches/org.carthage.CarthageKit", .info),
        ("Homebrew Cache", "Library/Caches/Homebrew", .warning),
        ("npm Cache", ".npm/_cacache", .info),
        ("Yarn Cache", "Library/Caches/Yarn", .info),
        ("pip Cache", "Library/Caches/pip", .info),
        ("Gradle Cache", ".gradle/caches", .info),
        ("Maven Cache", ".m2/repository", .info),
    ]
    
    public init() {}
    
    public func evaluate(context: RecommendationContext) async throws -> [Recommendation] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        var recommendations: [Recommendation] = []
        var totalSize: Int64 = 0
        var foundCaches: [(name: String, path: String, size: Int64, severity: Severity)] = []
        
        for (name, relativePath, severity) in developerPaths {
            let fullPath = home.appendingPathComponent(relativePath)
            
            guard fm.fileExists(atPath: fullPath.path) else { continue }
            
            let size = calculateDirectorySize(at: fullPath)
            if size > 50_000_000 { // Only include if > 50MB
                foundCaches.append((name, fullPath.path, size, severity))
                totalSize += size
            }
        }
        
        // Only generate recommendation if total exceeds threshold
        guard totalSize >= minTotalSizeBytes else { return [] }
        
        // Sort by size descending
        foundCaches.sort { $0.size > $1.size }
        
        // Build evidence
        var evidence: [Evidence] = [
            Evidence(kind: .aggregate, label: "Total Developer Cache", value: formatBytes(totalSize)),
            Evidence(kind: .aggregate, label: "Cache Locations", value: "\(foundCaches.count) found")
        ]
        
        // Add top caches as evidence
        for cache in foundCaches.prefix(5) {
            evidence.append(Evidence(
                kind: .path,
                label: cache.name,
                value: formatBytes(cache.size)
            ))
        }
        
        // Determine overall severity
        let overallSeverity: Severity = foundCaches.contains { $0.severity == .warning } ? .warning : .info
        
        // Build actions
        let paths = foundCaches.map { $0.path }
        let actions: [Action] = [
            Action(type: .cleanupTrash, payload: .paths(paths), requiresConfirmation: true, supportsDryRun: true),
            Action(type: .openFinder, payload: .paths([home.appendingPathComponent("Library/Developer").path]), requiresConfirmation: false, supportsDryRun: false)
        ]
        
        recommendations.append(Recommendation(
            id: id,
            title: "Developer Tool Caches",
            summary: "\(foundCaches.count) developer caches totaling \(formatBytes(totalSize)). Safe to clean.",
            severity: overallSeverity,
            risk: .low,
            confidence: .high,
            estimatedReclaimBytes: totalSize,
            evidence: evidence,
            actions: actions,
            requirements: []
        ))
        
        return recommendations
    }
    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var size: Int64 = 0
        
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                size += Int64(fileSize)
            }
        }
        
        return size
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.1f MB", mb)
    }
}
