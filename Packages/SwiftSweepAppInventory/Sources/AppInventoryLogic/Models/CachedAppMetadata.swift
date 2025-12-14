import Foundation

/// Cached metadata for an application's Deep Scan results.
public struct CachedAppMetadata: Codable {
    public let sizeBytes: Int64
    public let scannedAt: Date
    public let bundleVersion: String?
    public let bundleMTime: Date
    
    public init(sizeBytes: Int64, scannedAt: Date, bundleVersion: String?, bundleMTime: Date) {
        self.sizeBytes = sizeBytes
        self.scannedAt = scannedAt
        self.bundleVersion = bundleVersion
        self.bundleMTime = bundleMTime
    }
}
