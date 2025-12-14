import Foundation

public struct AppItem: Identifiable, Hashable, Codable {
    public let id: String
    public let url: URL
    public let displayName: String
    public let version: String?
    
    // Metadata from Spotlight (Baseline)
    public var estimatedSizeBytes: Int64?
    public var lastUsedDate: Date?
    public var contentModifiedDate: Date?
    
    // Metadata from Deep Scan (Accurate)
    public var accurateSizeBytes: Int64?
    
    // Source tracking
    public enum Source: String, Codable {
        case spotlight
        case filesystem
    }
    public let source: Source
    
    public init(
        id: String,
        url: URL,
        displayName: String,
        version: String? = nil,
        estimatedSizeBytes: Int64? = nil,
        lastUsedDate: Date? = nil,
        contentModifiedDate: Date? = nil,
        accurateSizeBytes: Int64? = nil,
        source: Source
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.version = version
        self.estimatedSizeBytes = estimatedSizeBytes
        self.lastUsedDate = lastUsedDate
        self.contentModifiedDate = contentModifiedDate
        self.accurateSizeBytes = accurateSizeBytes
        self.source = source
    }
}
